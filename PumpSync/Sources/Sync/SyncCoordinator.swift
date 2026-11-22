import Foundation
import Observation

enum SyncTriggerReason: String, Equatable, Codable, Sendable {
  case appOpen
  case manual
  case background
}

enum SyncPhase: String, Equatable {
  case preparing
  case downloading
  case updatingHealth

  var message: String {
    switch self {
    case .preparing:
      return "Preparing sync…"
    case .downloading:
      return "Downloading pump data…"
    case .updatingHealth:
      return "Updating Apple Health…"
    }
  }
}

enum SyncRecovery: String, Codable {
  case retry
  case account
  case health
  case waitAndRetry
  case none
}

struct SyncProgress: Equatable {
  let phase: SyncPhase
  let trigger: SyncTriggerReason
  let startedAt: Date
}

struct SyncCompletion: Equatable {
  let received: Int
  let saved: Int
  var permissionSkipped: Int = 0
  var gapBefore: Date?
  let completedAt: Date
}

struct SyncFailure: Equatable {
  let message: String
  let recovery: SyncRecovery
  var retryAfter: Date?
}

enum SyncOperationState: Equatable {
  case idle
  case running(SyncProgress)
  case succeeded(SyncCompletion)
  case failed(SyncFailure)
}

/// The slice of HealthKitService's surface SyncCoordinator depends on,
/// extracted as a seam so tests can substitute a fake — real HealthKit
/// authorization/writes require device interaction and aren't something a
/// unit test can drive deterministically.
@MainActor
protocol SyncHealthWriting {
  func refreshAuthorizationStatus()
  var hasAnyWritePermission: Bool { get }
  var concentration: InsulinConcentration { get }
  /// Returns the subset of samples actually written to Apple Health.
  func save(batch: HealthImportBatch) async throws -> [SampleDTO]
}

extension HealthKitService: SyncHealthWriting {}

protocol SyncSampleLedger {
  func filterUnseen(_ samples: [SampleDTO]) throws -> [SampleDTO]
  func recordImported(_ samples: [SampleDTO], importedAt: Date) throws
}

extension ImportedSampleLedger: SyncSampleLedger {}

@MainActor
@Observable
final class SyncCoordinator {
  /// Subtracted from the effective import window's end before
  /// recording the watermark, so a slow request or a late-arriving Tandem
  /// upload near the boundary is still covered by the next sync. Re-fetched
  /// samples are deduplicated by ImportedSampleLedger, so this is safe.
  private static let watermarkOverlap: TimeInterval = 24 * 60 * 60

  /// Surface gaps exceeding an hour when an old cursor falls outside the lookback.
  private static let lookbackGapTolerance: TimeInterval = 60 * 60

  private let dataSource: any TandemDataSource
  private let credentialStore: TandemCredentialStore
  private let healthKitService: SyncHealthWriting
  private let importedSampleLedger: any SyncSampleLedger
  private let syncMetadataStore: SyncMetadataStore
  private let diagnostics: DiagnosticsLogStore?
  let attemptStore: SyncAttemptStore
  private var syncTask: Task<SyncRunOutcome, Never>?
  private var syncOperationID: UUID?
  private var syncPreparation: SyncProgress?
  private var syncWaiters: [UUID: [UUID: SyncExecutionLease]] = [:]
  private var foregroundActive = false
  // Results remain available in the Sync screen until another operation or explicit recovery.
  private(set) var operationState: SyncOperationState = .idle

  private var ownsDisplayedHistory: Bool {
    credentialStore.ownershipAvailable && !credentialStore.needsDirectReconnect
      && syncMetadataStore.metadata.owner?.accountId == credentialStore.accountId
  }

  var dashboardHistory: SyncHistoryPresentation? {
    guard ownsDisplayedHistory else { return nil }
    return SyncHistoryPresentation(metadata: syncMetadataStore.metadata,
      attempts: (attemptStore.active.map { [$0] } ?? []) + attemptStore.history)
  }

  /// Live events drive announcements. The dashboard also displays this account's
  /// durable result after relaunch or a background completion.
  var dashboardState: SyncOperationState {
    let metadata = syncMetadataStore.metadata
    guard ownsDisplayedHistory else { return .idle }
    switch operationState {
    case .running, .succeeded: return operationState
    case .failed(let failure) where needsRecovery(failure): return operationState
    default: break
    }
    let latest = attemptStore.history.first { $0.historyScopeID == metadata.historyScopeID }
    if let latest, latest.startedAt > (metadata.lastSuccessfulSyncAt ?? .distantPast) {
      switch latest.outcome {
      case .interrupted, .canceled:
        return .failed(SyncFailure(message: String(localized: "The last sync didn’t finish."), recovery: .retry))
      case .failed where metadata.latestFailure == nil:
        return .failed(SyncFailure(message: String(localized: "The last sync failed."), recovery: .retry))
      case .blocked where latest.reason == .credentials && !credentialStore.hasValidatedCredentials:
        return .failed(SyncFailure(message: String(localized: "Reconnect to Tandem to sync."), recovery: .account))
      case .blocked where latest.reason == .healthPermission && !healthKitService.hasAnyWritePermission:
        return .failed(SyncFailure(message: String(localized: "Allow Apple Health access to sync."), recovery: .health))
      default: break
      }
    }
    if let failure = metadata.latestFailure, needsRecovery(failure) {
      return .failed(failure)
    }
    guard let success = metadata.lastSuccessfulSyncAt else { return .idle }
    return .succeeded(SyncCompletion(received: metadata.lastSampleCount, saved: metadata.lastImportedCount,
      permissionSkipped: metadata.lastPermissionSkippedCount ?? 0, gapBefore: metadata.lastGapBefore, completedAt: success))
  }

  private func needsRecovery(_ failure: SyncFailure) -> Bool {
    switch failure.recovery {
    case .account: !credentialStore.hasValidatedCredentials
    case .health: !healthKitService.hasAnyWritePermission
    default: true
    }
  }

  private(set) var activeInitialImportRange: InitialImportRange?

  /// Includes foreground recovery and freshness evaluation before visible syncing.
  var hasActiveSyncExecution: Bool { syncTask != nil }

  var isSyncing: Bool {
    if case .running = operationState {
      return true
    }
    return false
  }

  var syncPhase: SyncPhase? {
    guard case .running(let progress) = operationState else {
      return nil
    }
    return progress.phase
  }

#if DEBUG
  func applyScreenshotFeedbackState(_ state: SyncOperationState) {
    guard AppLaunchEnvironment.isScreenshotMode,
          ProcessInfo.processInfo.arguments.contains("--pumpsync-feedback-sequence") else { return }
    operationState = state
  }

  func applyScreenshotSyncing() {
    operationState = .running(SyncProgress(phase: .preparing, trigger: .manual, startedAt: Date()))
  }

  func applyScreenshotSuccess(completedAt: Date = Date(), permissionSkipped: Int = 0) {
    operationState = .succeeded(SyncCompletion(received: 48, saved: 4, permissionSkipped: permissionSkipped, completedAt: completedAt))
  }

  func applyScreenshotFailure(recovery: SyncRecovery = .retry) {
    operationState = .failed(SyncFailure(message: recovery == .account ? "Check your connection settings before syncing again." : "Sync could not be completed. Try again.", recovery: recovery))
  }
#endif

  init(
    dataSource: any TandemDataSource,
    credentialStore: TandemCredentialStore,
    healthKitService: SyncHealthWriting,
    importedSampleLedger: any SyncSampleLedger,
    syncMetadataStore: SyncMetadataStore,
    diagnostics: DiagnosticsLogStore? = nil,
    attemptStore: SyncAttemptStore? = nil
  ) {
    self.dataSource = dataSource
    self.credentialStore = credentialStore
    self.healthKitService = healthKitService
    self.importedSampleLedger = importedSampleLedger
    self.syncMetadataStore = syncMetadataStore
    self.diagnostics = diagnostics
    self.attemptStore = attemptStore ?? SyncAttemptStore(defaults: UserDefaults(suiteName: "SyncAttempts.\(UUID())")!, diagnostics: diagnostics)
    reconcileHistoryOwner()
    observeHistoryOwner()
  }

  private func reconcileHistoryOwner() {
    guard credentialStore.ownershipAvailable else { return }
    // Wait for foreground confirmation before adopting legacy account history.
    if credentialStore.needsDirectReconnect { return }
    let owner = credentialStore.accountId.map { TandemSyncOwner(accountId: $0) }
    let previous = syncMetadataStore.metadata.owner
    syncMetadataStore.reconcileOwner(owner)
    if previous != owner, !isSyncing { operationState = .idle }
  }

  private func observeHistoryOwner() {
    withObservationTracking {
      _ = credentialStore.accountId
      _ = credentialStore.ownershipAvailable
      _ = credentialStore.needsDirectReconnect
      _ = credentialStore.hasValidatedCredentials
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.reconcileHistoryOwner()
        self?.observeHistoryOwner()
      }
    }
  }

  @discardableResult
  func refreshIfStale(reason: SyncTriggerReason, lease: SyncExecutionLease? = nil) async -> SyncRunOutcome {
    guard !Task.isCancelled else { return .canceled }
    // Join an existing owner before evaluating freshness: it may be committing
    // the success that makes this request fresh.
    if syncTask != nil { return await run(reason: reason, lease: lease) }
    if reason == .background {
      diagnostics?.record(
        source: .sync,
        title: "Background sync policy evaluated",
        message: "build=\(BackgroundSyncDiagnostics.buildNumber) reason=background decision=sync policy=grantedTask"
      )
      return await run(reason: reason, lease: lease)
    }

    guard shouldRefresh(reason: reason) else { return .skippedFresh }
    return await run(reason: reason, lease: lease)
  }

  /// Check freshness when the foreground scene can perform an import.
  @discardableResult
  func reconcileForegroundRecovery() async -> SyncRunOutcome {
    await refreshIfStale(reason: .appOpen)
  }

  private func shouldRefresh(reason: SyncTriggerReason) -> Bool {
    reconcileHistoryOwner()
    let lastSuccessfulSyncAt = syncMetadataStore.metadata.lastSuccessfulSyncAt
    let ageSeconds = lastSuccessfulSyncAt.map { max(0, Date().timeIntervalSince($0)) }
    let shouldRefresh = ageSeconds.map { $0 >= AppConstants.staleSyncInterval } ?? true
    let ageDescription = ageSeconds.map { String(Int($0)) } ?? "none"
    diagnostics?.record(
      source: .sync,
      title: "Background sync freshness evaluated",
      message: "build=\(BackgroundSyncDiagnostics.buildNumber) reason=\(reason.rawValue) decision=\(shouldRefresh ? "sync" : "skip") lastSuccessAgeSeconds=\(ageDescription) targetSeconds=\(Int(AppConstants.staleSyncInterval))"
    )

    if !shouldRefresh {
      diagnostics?.record(source: .sync, title: "Sync skipped", message: "Last successful sync is within the four-hour freshness target.")
    }
    return shouldRefresh
  }

  func startManualSync() {
    guard foregroundActive else { return }
    let lease = SyncExecutionLease(kind: .foreground)
    let task: Task<SyncRunOutcome, Never>
    if let existing = syncTask {
      guard !existing.isCancelled else { return }
      task = existing
    } else {
      guard let created = makeSyncTask(reason: .manual) else { return }
      task = created
    }
    guard let operationID = syncOperationID else { return }
    let waiterID = UUID()
    syncWaiters[operationID, default: [:]][waiterID] = lease
    showSyncProgress()
    Task { _ = await awaitSyncTask(task, operationID: operationID, waiterID: waiterID, lease: lease, trigger: .manual) }
  }

  func setForegroundActive(_ active: Bool) {
    foregroundActive = active
    guard !active, let operationID = syncOperationID else { return }
    if let waiters = syncWaiters[operationID] {
      for lease in waiters.values where lease.kind == .foreground { lease.revoke() }
    }
    if !hasExecutionLease(operationID) { syncTask?.cancel() }
  }

  func retry() {
    guard case .failed(let failure) = dashboardState,
          failure.recovery == .retry || failure.recovery == .waitAndRetry else {
      return
    }
    startManualSync()
  }

  func dismissResult() {
    switch operationState {
    case .succeeded, .failed:
      operationState = .idle
    case .idle, .running:
      break
    }
  }

  @discardableResult
  func sync(reason: SyncTriggerReason, lease: SyncExecutionLease? = nil) async -> Bool {
    await run(reason: reason, lease: lease).succeeded
  }

  /// All triggers share one execution and retain their individual leases.
  /// Canceling one caller cannot cancel work still owned by another caller.
  func run(reason: SyncTriggerReason, lease: SyncExecutionLease? = nil) async -> SyncRunOutcome {
    guard !Task.isCancelled else { return .canceled }
    guard reason != .background || lease?.kind == .background else { return .deferred(.executionLeaseExpired) }
    let lease = lease ?? SyncExecutionLease(kind: .foreground)
    guard lease.isValid, lease.kind != .foreground || foregroundActive else { return .deferred(.executionLeaseExpired) }
    if let previous = syncTask, previous.isCancelled {
      _ = await previous.value
      guard !Task.isCancelled else { return .canceled }
      guard lease.isValid, lease.kind != .foreground || foregroundActive else { return .deferred(.executionLeaseExpired) }
    }
    if let syncTask { return await awaitSyncTask(syncTask, lease: lease, trigger: reason) }
    reconcileHistoryOwner()
    if isRateLimited { return .deferred(.rateLimited) }
    guard let task = makeSyncTask(reason: reason) else { return .failed }
    return await awaitSyncTask(task, lease: lease, trigger: reason)
  }

  private func awaitSyncTask(
    _ task: Task<SyncRunOutcome, Never>, operationID: UUID? = nil, waiterID: UUID = UUID(), lease: SyncExecutionLease, trigger: SyncTriggerReason
  ) async -> SyncRunOutcome {
    guard let operationID = operationID ?? syncOperationID else { return .contextReplaced }
    syncWaiters[operationID, default: [:]][waiterID] = lease
    if trigger == .manual { showSyncProgress() }
    defer { removeSyncWaiter(waiterID, operationID: operationID) }
    return await withTaskCancellationHandler(operation: {
      let result = await task.value
      if Task.isCancelled || result == .canceled { return .canceled }
      guard lease.isValid else { return lease.kind == .foreground ? .canceled : .deferred(.executionLeaseExpired) }
      return result
    }, onCancel: {
      lease.revoke()
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.removeSyncWaiter(waiterID, operationID: operationID)
        if self.syncOperationID == operationID, !self.hasExecutionLease(operationID) { task.cancel() }
      }
    })
  }

  private func hasExecutionLease(_ operationID: UUID) -> Bool {
    syncWaiters[operationID]?.values.contains(where: { $0.isValid }) == true
  }

  private func removeSyncWaiter(_ waiterID: UUID, operationID: UUID) {
    syncWaiters[operationID]?.removeValue(forKey: waiterID)
    if syncWaiters[operationID]?.isEmpty == true { syncWaiters[operationID] = nil }
  }

  private var isRateLimited: Bool {
    guard let deadline = syncMetadataStore.metadata.lastRetryAfter else { return false }
    return deadline > Date()
  }

  private func makeSyncTask(reason: SyncTriggerReason) -> Task<SyncRunOutcome, Never>? {
    guard syncTask == nil, !isSyncing else { return nil }
    reconcileHistoryOwner()
    guard !isRateLimited else { return nil }
    let metadata = syncMetadataStore.metadata
    let range = metadata.initialImportRange
    activeInitialImportRange = metadata.lastSuccessfulSyncAt == nil ? range : nil
    syncPreparation = SyncProgress(phase: .preparing, trigger: reason, startedAt: Date())
    showSyncProgress()
    let operationID = UUID()
    let intent = SyncIntent(operationID: operationID, trigger: reason,
      context: credentialStore.currentImportSnapshot, concentration: healthKitService.concentration, initialRange: range)
    attemptStore.begin(operationID: operationID, trigger: reason, historyScopeID: syncMetadataStore.metadata.historyScopeID)
    let task = Task { @MainActor [weak self] in
      guard let self else { return SyncRunOutcome.canceled }
      let result = await self.performSync(intent: intent)
      self.attemptStore.finish(operationID: operationID, result: result)
      if self.syncOperationID == operationID {
        self.syncTask = nil
        self.syncOperationID = nil
        self.syncPreparation = nil
        self.activeInitialImportRange = nil
      }
      return result
    }
    syncOperationID = operationID
    syncTask = task
    return task
  }

  private func showSyncProgress() {
    guard !isSyncing, let syncPreparation else { return }
    operationState = .running(syncPreparation)
  }

  private func performSync(intent: SyncIntent) async -> SyncRunOutcome {
    let reason = intent.trigger
    let concentration = intent.concentration
    guard let startedAt = syncPreparation?.startedAt else { return .failed }

    if let stopped = stoppedOutcome(intent) { recordCancellation(reason: reason); return stopped }

    // A background launch has no view lifecycle to refresh permission state,
    // so refresh it here rather than relying on a view's .task/.onAppear.
    healthKitService.refreshAuthorizationStatus()

    attemptStore.advance(operationID: intent.operationID, stage: .validating)
    guard let credentials = try? credentialStore.load(), let context = intent.context,
          let current = credentialStore.currentImportSnapshot else {
      fail("Validate your Tandem account before syncing.", recovery: .account)
      return .blocked(.credentials)
    }
    guard context == current else {
      operationState = .idle
      return .contextReplaced
    }
    guard healthKitService.hasAnyWritePermission else {
      fail("Enable Apple Health write access before syncing.", recovery: .health)
      diagnostics?.record(source: .sync, severity: .warning, title: "Sync blocked", message: "No Apple Health write permissions are enabled.")
      return .blocked(.healthPermission)
    }

    // Honor expiration even when authorization checks ran synchronously.
    if let stopped = stoppedOutcome(intent) {
      recordCancellation(reason: reason)
      return stopped
    }

    let historyOwner = TandemSyncOwner(accountId: context.accountId)
    diagnostics?.record(source: .sync, title: "Sync started", message: "Reason: \(reason.rawValue)")
    recordBackgroundStage(.preparing, startedAt: startedAt, reason: reason)

    do {
      let now = Date()
      let requestMinDate = syncMetadataStore.metadata.syncWatermark
        ?? intent.initialRange.minimumDate(relativeTo: startedAt)
      let request = TandemSyncRequest(
        tandem: credentials,
        minDate: requestMinDate,
        maxDate: now,
        // Tandem reports pump-local wall-clock timestamps; use
        // the device's zone to anchor them, or every sample lands hours off.
        timeZoneIdentifier: TimeZone.current.identifier
      )
      operationState = .running(SyncProgress(phase: .downloading, trigger: reason, startedAt: startedAt))
      attemptStore.advance(operationID: intent.operationID, stage: .downloading)
      recordBackgroundStage(.downloading, startedAt: startedAt, reason: reason)
      if let stopped = stoppedOutcome(intent) {
        recordCancellation(reason: reason)
        return stopped
      }
      let response = try await dataSource.load(request)
      try checkExecution(intent)
      guard let current = credentialStore.currentImportSnapshot else { throw HealthImportError.staleContext }
      let plan = try NativePerformance.measure("Import conversion") {
        try ImportPlanner.makePlan(response: response, context: context, concentration: concentration)
      }
      _ = try HealthImportPolicy.authorize(plan: plan, current: current)
      syncMetadataStore.recordAttempt()
      let unseenSamples = try importedSampleLedger.filterUnseen(plan.samples.map(\.original))
      attemptStore.recordCounts(operationID: intent.operationID, returned: response.samples.count, imported: nil, permissionSkipped: nil)
      // Record only what Apple Health confirmed: save() drops samples whose
      // per-type permission is missing, and marking those imported would
      // permanently lose them because a
      // later permission grant could never backfill an already-ledgered
      // sample.
      operationState = .running(SyncProgress(phase: .updatingHealth, trigger: reason, startedAt: startedAt))
      attemptStore.advance(operationID: intent.operationID, stage: .updatingHealth)
      recordBackgroundStage(.updatingHealth, startedAt: startedAt, reason: reason)
      try checkExecution(intent)
      guard let current = credentialStore.currentImportSnapshot else { throw HealthImportError.staleContext }
      let batch = try HealthImportPolicy.authorize(plan: plan.selectingSamples(unseenSamples), current: current, executionIsValid: { [weak self] in
        self?.syncOperationID == intent.operationID && self?.hasExecutionLease(intent.operationID) == true
      })
      attemptStore.checkpoint(operationID: intent.operationID, checkpoint: .healthSaveStarted)
      let writtenSamples = try await healthKitService.save(batch: batch)
      attemptStore.recordCounts(operationID: intent.operationID, returned: response.samples.count, imported: writtenSamples.count, permissionSkipped: unseenSamples.count - writtenSamples.count)
      attemptStore.checkpoint(operationID: intent.operationID, checkpoint: .healthSaveCompleted)
      attemptStore.checkpoint(operationID: intent.operationID, checkpoint: .ledgerCommitStarted)
      try importedSampleLedger.recordImported(writtenSamples, importedAt: Date())
      attemptStore.checkpoint(operationID: intent.operationID, checkpoint: .ledgerCommitCompleted)
      let importedCount = writtenSamples.count
      let permissionSkippedCount = unseenSamples.count - writtenSamples.count
      // An already-submitted HealthKit save cannot be recalled. Ledger confirmed
      // writes for deduplication, but never publish success for abandoned work.
      try checkExecution(intent)
      try HealthImportPolicy.validate(batch: batch, current: credentialStore.currentImportSnapshot)
      let watermark = permissionSkippedCount > 0
        ? min(syncMetadataStore.metadata.syncWatermark ?? response.effectiveMinDate, response.effectiveMinDate)
        : max(response.effectiveMinDate, response.effectiveMaxDate.addingTimeInterval(-Self.watermarkOverlap))
      let gapBefore = response.effectiveMinDate.timeIntervalSince(requestMinDate) > Self.lookbackGapTolerance
        ? response.effectiveMinDate : nil
      let completion = SyncCompletion(received: response.samples.count, saved: importedCount,
        permissionSkipped: permissionSkippedCount, gapBefore: gapBefore, completedAt: Date())
      syncMetadataStore.recordSuccess(sampleCount: completion.received, importedCount: importedCount,
        completedAt: completion.completedAt, watermark: watermark, owner: historyOwner,
        permissionSkippedCount: permissionSkippedCount, gapBefore: gapBefore)
      attemptStore.checkpoint(operationID: intent.operationID, checkpoint: .metadataCommitted)
      if gapBefore != nil {
        diagnostics?.record(
          source: .sync,
          severity: .warning,
          title: "Sync window clamped",
          message: "The requested history predates the available import window."
        )
      }

      diagnostics?.record(
        source: .sync,
        title: "Sync completed",
        message: "Returned \(response.samples.count), imported \(importedCount), reason \(reason.rawValue)."
      )
      if reason == .background {
        operationState = .idle
      } else {
        operationState = .succeeded(completion)
      }
      return .completed
    } catch {
      if let stopped = stoppedOutcome(intent) {
        recordCancellation(reason: reason)
        return stopped
      }
      if error is CancellationError { recordCancellation(reason: reason); return .canceled }
      guard credentialStore.currentImportSnapshot == context else {
        operationState = .idle
        return .contextReplaced
      }
      let failure: SyncFailure
      if let providerError = error as? DirectTandemError {
        let recovery: SyncRecovery
        var retryAfter: Date?
        switch providerError {
        case .credentialsRejected:
          credentialStore.invalidateValidation()
          recovery = .account
        case .rateLimited(let deadline):
          recovery = .waitAndRetry
          retryAfter = deadline
        default: recovery = .retry
        }
        failure = SyncFailure(message: providerError.localizedDescription, recovery: recovery, retryAfter: retryAfter)
      } else if let importError = error as? HealthImportError {
        failure = SyncFailure(message: importError.localizedDescription, recovery: .retry)
      } else if isHealthAuthorizationFailure(error) {
        failure = SyncFailure(message: "Enable Apple Health write access before syncing.", recovery: .health)
      } else {
        failure = SyncFailure(message: "Sync could not be completed. Try again.", recovery: .retry)
      }
      syncMetadataStore.recordFailure(failure)
      operationState = .failed(failure)
      diagnostics?.record(source: .sync, severity: .error, title: "Sync failed", message: failure.message)
      return .failed
    }
  }

  private func stoppedOutcome(_ intent: SyncIntent) -> SyncRunOutcome? {
    if !hasExecutionLease(intent.operationID) { return Task.isCancelled ? .canceled : .deferred(.executionLeaseExpired) }
    return Task.isCancelled ? .canceled : nil
  }

  private func checkExecution(_ intent: SyncIntent) throws {
    if stoppedOutcome(intent) != nil { throw CancellationError() }
  }

  private func fail(_ message: String, recovery: SyncRecovery) {
    let failure = SyncFailure(message: message, recovery: recovery)
    if syncMetadataStore.metadata.owner != nil { syncMetadataStore.recordFailure(failure) }
    operationState = .failed(failure)
  }

  private func recordCancellation(reason: SyncTriggerReason) {
    if isSyncing { operationState = .idle }
    diagnostics?.record(
      source: .sync,
      title: "Sync cancelled",
      message: "Reason: \(reason.rawValue)"
    )
  }

  private func recordBackgroundStage(_ phase: SyncPhase, startedAt: Date, reason: SyncTriggerReason) {
    guard reason == .background else {
      return
    }

    let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
    diagnostics?.record(
      source: .sync,
      title: "Background sync stage",
      message: BackgroundSyncDiagnostics.stageDescription(
        buildNumber: BackgroundSyncDiagnostics.buildNumber,
        stage: phase.rawValue,
        elapsedMs: elapsedMs
      )
    )
  }

  private func isHealthAuthorizationFailure(_ error: Error) -> Bool {
    guard let healthError = error as? HealthKitError else {
      return false
    }
    if case .authorizationDenied = healthError {
      return true
    }
    return false
  }

  func performBackgroundSync(lease: SyncExecutionLease) async -> Bool {
    await refreshIfStale(reason: .background, lease: lease).succeeded
  }

}
