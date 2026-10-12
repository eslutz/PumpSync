import Foundation
import Observation

enum SyncTriggerReason: String, Equatable, Codable {
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
      return "Starting secure service…"
    case .downloading:
      return "Downloading pump data…"
    case .updatingHealth:
      return "Updating Apple Health…"
    }
  }
}

enum SyncRecovery: Equatable {
  case retry
  case openSubscription
  case openSettings
  case waitAndRetry
  case none
}

struct SyncProgress: Equatable {
  let phase: SyncPhase
  let trigger: SyncTriggerReason
  let startedAt: Date
}

struct SyncCompletion: Equatable {
  let message: String
  let completedAt: Date
}

struct SyncFailure: Equatable {
  let message: String
  let recovery: SyncRecovery
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
  /// Subtracted from the server-reported effective sync window's end before
  /// recording the watermark, so a slow request or a late-arriving Tandem
  /// upload near the boundary is still covered by the next sync. Re-fetched
  /// samples are deduplicated by ImportedSampleLedger, so this is safe.
  private static let watermarkOverlap: TimeInterval = 24 * 60 * 60

  /// How far the server may clamp the requested window start forward before
  /// the sync surfaces a data-gap notice. Small clock differences between
  /// device and server are expected; an hour of slack keeps routine syncs
  /// quiet while a real multi-day gap is always far larger.
  private static let lookbackGapTolerance: TimeInterval = 60 * 60

  private let apiClient: PumpSyncAPIClient
  private let authService: AuthService
  private let credentialStore: TandemCredentialStore
  private let healthKitService: SyncHealthWriting
  private let importedSampleLedger: any SyncSampleLedger
  private let syncMetadataStore: SyncMetadataStore
  private let diagnostics: DiagnosticsLogStore?
  let attemptStore: SyncAttemptStore
  private var demoPreviewActive = false
  private var syncTask: Task<SyncRunOutcome, Never>?
  private var syncOperationID: UUID?
  private struct Waiter {
    let lease: SyncExecutionLease
    let trigger: SyncTriggerReason
    let recoveryPolicy: SessionRecoveryPolicy
  }
  private var syncWaiters: [UUID: [UUID: Waiter]] = [:]
  private var foregroundActive = false
  private var notificationDismissalTask: Task<Void, Never>?

  private(set) var isNotificationDismissed = false

  private(set) var operationState: SyncOperationState = .idle {
    didSet {
      // Progress phases belong to one notification. Its result and the next
      // operation are new notifications, even if progress was dismissed.
      if case .running(let previous) = oldValue,
         case .running(let current) = operationState,
         previous.startedAt == current.startedAt {
        return
      }
      isNotificationDismissed = false
      scheduleNotificationDismissal()
    }
  }

  var isSyncing: Bool {
    if case .running = operationState {
      return true
    }
    return false
  }

  var lastMessage: String? {
    switch operationState {
    case .succeeded(let completion):
      return completion.message
    case .failed(let failure):
      return failure.message
    case .idle, .running:
      return nil
    }
  }

  var syncPhase: SyncPhase? {
    guard case .running(let progress) = operationState else {
      return nil
    }
    return progress.phase
  }

#if DEBUG
  func applyScreenshotSyncing() {
    operationState = .running(SyncProgress(phase: .preparing, trigger: .manual, startedAt: Date()))
  }

  func applyScreenshotSuccess() {
    operationState = .succeeded(SyncCompletion(message: "Imported 4 new samples.", completedAt: Date()))
  }

  func applyScreenshotFailure() {
    operationState = .failed(SyncFailure(message: "Sync could not be completed. Try again.", recovery: .retry))
  }
#endif

  init(
    apiClient: PumpSyncAPIClient,
    authService: AuthService,
    credentialStore: TandemCredentialStore,
    healthKitService: SyncHealthWriting,
    importedSampleLedger: any SyncSampleLedger,
    syncMetadataStore: SyncMetadataStore,
    diagnostics: DiagnosticsLogStore? = nil,
    attemptStore: SyncAttemptStore? = nil
  ) {
    self.apiClient = apiClient
    self.authService = authService
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
    guard !demoPreviewActive, credentialStore.ownershipAvailable else { return }
    let backendIdentity = authService.importConfigurationSnapshot.backendIdentity
    let owner = credentialStore.accountId.flatMap { accountId in
      backendIdentity.map { TandemSyncOwner(accountId: accountId, backendIdentity: $0) }
    }
    let previous = syncMetadataStore.metadata.owner
    syncMetadataStore.reconcileOwner(owner, resetReason: backendIdentity == nil ? .backendChanged : nil)
    if previous != owner, case .succeeded = operationState { operationState = .idle }
  }

  private func observeHistoryOwner() {
    withObservationTracking {
      _ = credentialStore.accountId
      _ = credentialStore.ownershipAvailable
      _ = authService.importConfigurationSnapshot.backendIdentity
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.reconcileHistoryOwner()
        self?.observeHistoryOwner()
      }
    }
  }

  var isDemoPreviewActive: Bool { demoPreviewActive }

  func setDemoPreviewActive(_ active: Bool) {
    demoPreviewActive = active
  }

  @discardableResult
  func refreshIfStale(reason: SyncTriggerReason, lease: SyncExecutionLease? = nil) async -> SyncRunOutcome {
    guard !Task.isCancelled else { return .canceled }
    // Join an existing owner before evaluating freshness: it may be committing
    // the success that makes this request fresh.
    if syncTask != nil { return await run(reason: reason, lease: lease) }
    guard !demoPreviewActive else { return .skippedPreviewActive }
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

  /// Foreground bootstrap and late committed-auth signals enter the same owner.
  /// Capture guards before auth and reevaluate freshness after it completes.
  @discardableResult
  func reconcileForegroundRecovery() async -> SyncRunOutcome {
    await run(reason: .appOpen, recoveryPolicy: .foreground, reevaluatesFreshnessAfterRecovery: true)
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
    let lease = SyncExecutionLease(kind: .foreground)
    guard syncTask == nil, foregroundActive,
          let task = makeSyncTask(reason: .manual, lease: lease),
          let operationID = syncOperationID else { return }
    let waiterID = UUID()
    syncWaiters[operationID, default: [:]][waiterID] = Waiter(lease: lease, trigger: .manual, recoveryPolicy: .foreground)
    Task { _ = await awaitSyncTask(task, operationID: operationID, waiterID: waiterID, lease: lease, trigger: .manual, recoveryPolicy: .foreground) }
  }

  func setForegroundActive(_ active: Bool) {
    foregroundActive = active
    guard !active, let operationID = syncOperationID else { return }
    if let waiters = syncWaiters[operationID] {
      for waiter in waiters.values where waiter.lease.kind == .foreground { waiter.lease.revoke() }
    }
    if !hasExecutionLease(operationID) { syncTask?.cancel() }
  }

  func retry() {
    guard case .failed(let failure) = operationState, failure.recovery == .retry else {
      return
    }
    startManualSync()
  }

  func dismissNotification() {
    isNotificationDismissed = true
    notificationDismissalTask?.cancel()
    notificationDismissalTask = nil
  }

  private func scheduleNotificationDismissal() {
    notificationDismissalTask?.cancel()
    notificationDismissalTask = nil
    guard case .succeeded(let completion) = operationState else { return }
    // Reconciliation may briefly replace and restore this result. Its original
    // deadline belongs to the completion, not to a SwiftUI view's lifetime.
    let remaining = max(0, completion.completedAt.addingTimeInterval(8).timeIntervalSinceNow)
    notificationDismissalTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(remaining)) }
      catch { return }
      guard let self, self.operationState == .succeeded(completion) else { return }
      self.dismissNotification()
    }
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
  func run(reason: SyncTriggerReason, lease: SyncExecutionLease? = nil, recoveryPolicy: SessionRecoveryPolicy? = nil, reevaluatesFreshnessAfterRecovery: Bool = false) async -> SyncRunOutcome {
    guard !Task.isCancelled else { return .canceled }
    guard !demoPreviewActive else { return .skippedPreviewActive }
    guard reason != .background || lease?.kind == .background else { return .deferred(.executionLeaseExpired) }
    let lease = lease ?? SyncExecutionLease(kind: .foreground)
    let recoveryPolicy = recoveryPolicy ?? (reason == .manual ? .foreground : (reason == .background ? .backgroundWithReenrollment : .background))
    guard lease.isValid, lease.kind != .foreground || foregroundActive else { return .deferred(.executionLeaseExpired) }
    if let previous = syncTask, previous.isCancelled {
      _ = await previous.value
      guard !Task.isCancelled else { return .canceled }
      guard lease.isValid, lease.kind != .foreground || foregroundActive else { return .deferred(.executionLeaseExpired) }
    }
    if let syncTask { return await awaitSyncTask(syncTask, lease: lease, trigger: reason, recoveryPolicy: recoveryPolicy) }
    guard let task = makeSyncTask(reason: reason, lease: lease, recoveryPolicy: recoveryPolicy, reevaluatesFreshnessAfterRecovery: reevaluatesFreshnessAfterRecovery) else { return .failed }
    return await awaitSyncTask(task, lease: lease, trigger: reason, recoveryPolicy: recoveryPolicy)
  }

  private func awaitSyncTask(
    _ task: Task<SyncRunOutcome, Never>, operationID: UUID? = nil, waiterID: UUID = UUID(), lease: SyncExecutionLease, trigger: SyncTriggerReason, recoveryPolicy: SessionRecoveryPolicy
  ) async -> SyncRunOutcome {
    guard let operationID = operationID ?? syncOperationID else { return .contextReplaced }
    syncWaiters[operationID, default: [:]][waiterID] = Waiter(lease: lease, trigger: trigger, recoveryPolicy: recoveryPolicy)
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
    syncWaiters[operationID]?.values.contains(where: { $0.lease.isValid }) == true
  }

  private func hasForcedSyncWaiter(_ operationID: UUID) -> Bool {
    syncWaiters[operationID]?.values.contains(where: { $0.lease.isValid && $0.trigger != .appOpen }) == true
  }

  private func recoveryPolicy(for intent: SyncIntent) -> SessionRecoveryPolicy {
    let owners = syncWaiters[intent.operationID]?.values.filter { $0.lease.isValid } ?? []
    if foregroundActive, owners.contains(where: { $0.lease.kind == .foreground && $0.recoveryPolicy.allowsInteractiveRecovery }) {
      return .foreground
    }
    if owners.contains(where: { $0.lease.kind == .background }) { return .backgroundWithReenrollment }
    return .background
  }

  private func removeSyncWaiter(_ waiterID: UUID, operationID: UUID) {
    syncWaiters[operationID]?.removeValue(forKey: waiterID)
    if syncWaiters[operationID]?.isEmpty == true { syncWaiters[operationID] = nil }
  }

  private func makeSyncTask(reason: SyncTriggerReason, lease: SyncExecutionLease, recoveryPolicy: SessionRecoveryPolicy? = nil, reevaluatesFreshnessAfterRecovery: Bool = false) -> Task<SyncRunOutcome, Never>? {
    let previousPresentation = operationState
    let previousNotificationDismissed = isNotificationDismissed
    guard beginSync(reason: reason) else { return nil }
    let operationID = UUID()
    let intent = SyncIntent(operationID: operationID, trigger: reason,
      configuration: authService.importConfigurationSnapshot, credentialRevision: credentialStore.revision,
      concentration: healthKitService.concentration,
      initialContext: authService.operationImportSnapshot(credentialRevision: credentialStore.revision), lease: lease,
      recoveryPolicy: recoveryPolicy ?? (reason == .manual ? .foreground : (reason == .background ? .backgroundWithReenrollment : .background)),
      reevaluatesFreshnessAfterRecovery: reevaluatesFreshnessAfterRecovery)
    attemptStore.begin(operationID: operationID, trigger: reason)
    let task = Task { @MainActor [weak self] in
      guard let self else { return SyncRunOutcome.canceled }
      let result = await self.performSync(intent: intent, capturedContext: intent.initialContext)
      self.attemptStore.finish(operationID: operationID, result: result)
      if self.syncOperationID == operationID {
        if result == .skippedFresh, case .succeeded = previousPresentation {
          self.operationState = previousPresentation
          self.isNotificationDismissed = previousNotificationDismissed
        }
        self.syncTask = nil
        self.syncOperationID = nil
      }
      return result
    }
    syncOperationID = operationID
    syncTask = task
    return task
  }

  private func beginSync(reason: SyncTriggerReason) -> Bool {
    guard !isSyncing, !demoPreviewActive else {
      return false
    }
    operationState = .running(SyncProgress(phase: .preparing, trigger: reason, startedAt: Date()))
    return true
  }

  private func performSync(
    intent: SyncIntent,
    capturedContext: ImportSessionSnapshot? = nil,
    replacementAttemptUsed: Bool = false
  ) async -> SyncRunOutcome {
    let reason = intent.trigger
    let configuration = intent.configuration
    let credentialRevision = intent.credentialRevision
    let concentration = intent.concentration
    let startedAt: Date
    if case .running(let progress) = operationState {
      startedAt = progress.startedAt
    } else {
      return .failed
    }

    if let stopped = stoppedOutcome(intent) { recordCancellation(reason: reason); return stopped }

    // A background launch has no view lifecycle to refresh permission state,
    // so refresh it here rather than relying on a view's .task/.onAppear.
    healthKitService.refreshAuthorizationStatus()

    let policyProvider: SessionRecoveryPolicyProvider = { [weak self] in
      self?.recoveryPolicy(for: intent) ?? .background
    }
    attemptStore.advance(operationID: intent.operationID, stage: .recovering)
    let recovery = await authService.recoverSessionIfNeeded(policy: policyProvider(), policyProvider: policyProvider, backendCorrelation: { [weak self] value in
      self?.attemptStore.correlate(operationID: intent.operationID, value: value)
    })
    let recoveredAccessToken: String?
    if case .ready(let connection, _) = recovery { recoveredAccessToken = connection.session.accessToken }
    else { recoveredAccessToken = nil }
    if let stopped = stoppedOutcome(intent) { recordCancellation(reason: reason); return stopped }

    guard configuration == authService.importConfigurationSnapshot else {
      fail(HealthImportError.staleContext.localizedDescription, recovery: .openSettings)
      return .contextReplaced
    }

    if recovery == .rejected(.connectionReplaced) {
      fail(HealthImportError.staleContext.localizedDescription, recovery: .openSettings)
      return .contextReplaced
    }
    guard let accessToken = recoveredAccessToken else {
      if authService.requiresSubscriptionAction {
        fail(
          "Your PumpSync subscription isn’t active. Subscribe or renew to resume syncing.",
          recovery: .openSubscription
        )
      } else {
        fail("Connect PumpSync before syncing.", recovery: .openSettings)
      }
      diagnostics?.record(source: .sync, severity: .warning, title: "Sync blocked", message: "Missing connection session.")
      switch recovery {
      case .deferred(let reason): return .deferred(.recovery(reason))
      case .requiresUserAction(let reason), .rejected(let reason): return .blocked(.session(reason))
      case .canceled: return .canceled
      case .ready: return .failed
      }
    }

    attemptStore.advance(operationID: intent.operationID, stage: .validating)
    guard credentialRevision == credentialStore.revision else {
      fail(HealthImportError.staleContext.localizedDescription, recovery: .openSettings)
      return .contextReplaced
    }
    if intent.reevaluatesFreshnessAfterRecovery, !hasForcedSyncWaiter(intent.operationID), !shouldRefresh(reason: reason) {
      operationState = .idle
      return .skippedFresh
    }

    reconcileHistoryOwner()
    guard credentialStore.hasValidatedCredentials else {
      fail("Save your pump account credentials before syncing.", recovery: .openSettings)
      diagnostics?.record(source: .sync, severity: .warning, title: "Sync blocked", message: "Pump account credentials are not validated.")
      return .blocked(.credentials)
    }

    guard let credentials = try? credentialStore.load() else {
      fail("Add your pump account before syncing.", recovery: .openSettings)
      diagnostics?.record(source: .sync, severity: .warning, title: "Sync blocked", message: "Missing pump account credentials.")
      return .blocked(.credentials)
    }

    guard let accountId = credentialStore.accountId else {
      fail("Validate your pump account before syncing.", recovery: .openSettings)
      return .blocked(.credentials)
    }
    guard healthKitService.hasAnyWritePermission else {
      fail("Enable Apple Health write access before syncing.", recovery: .openSettings)
      diagnostics?.record(source: .sync, severity: .warning, title: "Sync blocked", message: "No Apple Health write permissions are enabled.")
      return .blocked(.healthPermission)
    }

    // Cancellation can arrive while validating local prerequisites after auth
    // recovery. Do not issue a new request after the BGTask budget has expired.
    if let stopped = stoppedOutcome(intent) {
      recordCancellation(reason: reason)
      return stopped
    }

    guard credentialStore.revision == credentialRevision,
          let currentContext = authService.currentImportSnapshot(credentialRevision: credentialStore.revision) else {
      fail(HealthImportError.staleContext.localizedDescription, recovery: .openSettings)
      return .contextReplaced
    }
    if let capturedContext, capturedContext != currentContext,
       case .ready(_, transition: .reenrolled) = recovery, !replacementAttemptUsed {
      return await performSync(intent: intent, capturedContext: currentContext, replacementAttemptUsed: true)
    }
    let context = capturedContext ?? currentContext
    guard context.dataSourceMode == .tandemSource else {
      let error: HealthImportError = context.dataSourceMode == .syntheticDemo ? .previewOnly : .unverifiedSource
      fail(error.localizedDescription, recovery: .openSettings)
      return .blocked(.unverifiedSource)
    }
    let historyOwner = TandemSyncOwner(accountId: accountId, backendIdentity: context.backendIdentity)
    guard context == currentContext else {
      fail(HealthImportError.staleContext.localizedDescription, recovery: .openSettings)
      return .contextReplaced
    }
    guard let submittedConnection = authService.authenticatedConnection,
          submittedConnection.session.accessToken == accessToken else {
      fail(HealthImportError.staleContext.localizedDescription, recovery: .openSettings)
      return .contextReplaced
    }
    diagnostics?.record(source: .sync, title: "Sync started", message: "Reason: \(reason.rawValue)")
    recordBackgroundStage(.preparing, startedAt: startedAt, reason: reason)

    do {
      let now = Date()
      let requestMinDate = syncMetadataStore.metadata.syncWatermark
        ?? syncMetadataStore.metadata.initialImportRange.minimumDate(relativeTo: now)
      let request = TandemSyncRequest(
        tandem: credentials,
        minDate: requestMinDate,
        maxDate: now,
        // Tandem reports pump-local wall-clock timestamps; the backend needs
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
      let response = try await apiClient.syncTandem(request, accessToken: accessToken, backendCorrelation: { [weak self] value in
        self?.attemptStore.correlate(operationID: intent.operationID, value: value)
      })
      try checkExecution(intent)
      guard let current = authService.currentImportSnapshot(credentialRevision: credentialStore.revision) else { throw HealthImportError.staleContext }
      let plan = try ImportPlanner.makePlan(response: response, context: context, concentration: concentration)
      _ = try HealthImportPolicy.authorize(plan: plan, current: current)
      syncMetadataStore.recordAttempt()
      authService.markHostedSubscriptionAccessRestored()
      let unseenSamples = try importedSampleLedger.filterUnseen(response.samples)
      // Record only what Apple Health confirmed: save() drops samples whose
      // per-type permission is missing, and marking those imported would
      // permanently lose them — the backend retains nothing to replay, so a
      // later permission grant could never backfill an already-ledgered
      // sample.
      operationState = .running(SyncProgress(phase: .updatingHealth, trigger: reason, startedAt: startedAt))
      attemptStore.advance(operationID: intent.operationID, stage: .updatingHealth)
      recordBackgroundStage(.updatingHealth, startedAt: startedAt, reason: reason)
      try checkExecution(intent)
      guard let current = authService.currentImportSnapshot(credentialRevision: credentialStore.revision) else { throw HealthImportError.staleContext }
      let batch = try HealthImportPolicy.authorize(plan: plan.selectingSamples(unseenSamples), current: current, executionIsValid: { [weak self] in
        self?.syncOperationID == intent.operationID && self?.hasExecutionLease(intent.operationID) == true
      })
      let writtenSamples = try await healthKitService.save(batch: batch)
      try importedSampleLedger.recordImported(writtenSamples, importedAt: Date())
      // An already-submitted HealthKit save cannot be recalled. Ledger confirmed
      // writes for deduplication, but never publish success for abandoned work.
      try checkExecution(intent)
      try HealthImportPolicy.validate(batch: batch, current: authService.currentImportSnapshot(credentialRevision: credentialStore.revision))
      let importedCount = writtenSamples.count
      let watermark = response.effectiveMaxDate.addingTimeInterval(-Self.watermarkOverlap)
      syncMetadataStore.recordSuccess(sampleCount: response.samples.count, importedCount: importedCount, completedAt: Date(), watermark: watermark, owner: historyOwner)
      var completionMessage = message(sampleCount: response.samples.count, importedCount: importedCount, reason: reason)

      // Tandem Source only retains ~14 days of history. If the requested
      // window start was clamped forward, data between the watermark and the
      // effective start is unrecoverable — say so once instead of reporting
      // an unqualified success.
      if response.effectiveMinDate.timeIntervalSince(requestMinDate) > Self.lookbackGapTolerance {
        let gapEnd = response.effectiveMinDate.formatted(date: .abbreviated, time: .omitted)
        completionMessage += " Pump data before \(gapEnd) is no longer available from Tandem Source and could not be imported."
        diagnostics?.record(
          source: .sync,
          severity: .warning,
          title: "Sync window clamped",
          message: "Requested history from \(requestMinDate.formatted()) but Tandem Source data begins \(response.effectiveMinDate.formatted())."
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
        operationState = .succeeded(SyncCompletion(message: completionMessage, completedAt: Date()))
      }
      return .completed
    } catch {
      let apiError = error as? APIClientError
      attemptStore.correlate(operationID: intent.operationID, value: apiError?.correlationId)
      if let stopped = stoppedOutcome(intent) {
        recordCancellation(reason: reason)
        return stopped
      }
      if error is CancellationError { recordCancellation(reason: reason); return .canceled }
      // A response belongs to the captured operation, not to replacement
      // credentials or a new connection established during the download.
      // Refuse stale failures before any session/validation/metadata mutation.
      guard configuration == authService.importConfigurationSnapshot,
            credentialRevision == credentialStore.revision,
            authService.operationImportSnapshot(credentialRevision: credentialStore.revision) == context else {
        fail(HealthImportError.staleContext.localizedDescription, recovery: .openSettings)
        diagnostics?.record(source: .sync, severity: .warning, title: "Stale sync response discarded")
        return .contextReplaced
      }
      // Same-family refresh keeps successful downloads eligible. A rejection
      // of the old request token does not invalidate the fresh token, though.
      // Its import context still matches: report the obsolete request's failure
      // rather than claiming that the connection/account context was replaced.
      if case .httpStatus(401, _, _, _)? = apiError,
         authService.session?.accessToken != accessToken {
        fail(HealthImportError.staleContext.localizedDescription, recovery: .openSettings)
        diagnostics?.record(source: .sync, severity: .warning, title: "Superseded authentication failure discarded")
        return .failed
      }
      let subscriptionRequired = authService.isHostedMode && apiError?.isActiveSubscriptionRequired == true
      if apiError?.isAuthenticationFailure == true && !subscriptionRequired {
        authService.clearSessionForAuthenticationFailure(expectedSource: submittedConnection)
      }
      if apiError?.isTandemCredentialFailure == true {
        // Tandem rejected the stored pump credentials — retrying cannot
        // succeed. Drop the validated flag so the UI routes the user to the
        // credential form, and show the backend's remediation message.
        credentialStore.invalidateValidation()
      }
      if !(error is HealthImportError) {
        syncMetadataStore.recordFailure(error)
      }
      if let importError = error as? HealthImportError {
        fail(importError.localizedDescription, recovery: .openSettings)
      } else if apiError?.isTandemCredentialFailure == true {
        fail(
          apiError?.errorDescription
            ?? "Tandem Source did not accept your pump account credentials. Re-save your Tandem account.",
          recovery: .openSettings
        )
      } else if subscriptionRequired,
                !replacementAttemptUsed,
                await authService.recoverHostedSubscriptionAfterAccessDenied(policy: policyProvider(), policyProvider: policyProvider) {
        diagnostics?.record(
          source: .sync,
          title: "Subscription access recovered",
          message: "retry=sync reason=\(reason.rawValue)"
        )
        if let stopped = stoppedOutcome(intent) { recordCancellation(reason: reason); return stopped }
        guard configuration == authService.importConfigurationSnapshot,
              credentialRevision == credentialStore.revision,
              let freshContext = authService.currentImportSnapshot(credentialRevision: credentialRevision) else {
          fail(HealthImportError.staleContext.localizedDescription, recovery: .openSettings)
          return .contextReplaced
        }
        return await performSync(intent: intent, capturedContext: freshContext, replacementAttemptUsed: true)
      } else if subscriptionRequired {
        fail(
          "Your PumpSync subscription isn’t active. Subscribe or renew to resume syncing.",
          recovery: .openSubscription
        )
      } else if apiError?.isAuthenticationFailure == true {
        fail("Sync could not be completed. Try again.", recovery: .openSettings)
      } else if apiError?.isRateLimited == true {
        fail("Sync limit reached. Wait a while before trying again.", recovery: .waitAndRetry)
      } else if isHealthAuthorizationFailure(error) {
        fail("Enable Apple Health write access before syncing.", recovery: .openSettings)
      } else if apiError?.backendCode == "tandem_source_request_rejected"
                  || apiError?.backendCode == "tandem_source_error"
                  || apiError?.backendCode == "tandem_source_access_denied" {
        fail(
          apiError?.errorDescription ?? "Tandem Source could not provide your pump data. Try again later.",
          recovery: .waitAndRetry
        )
      } else if apiError?.isTransient == true || isTransientNetworkFailure(error) {
        fail("Sync could not be completed. Try again.", recovery: .retry)
      } else {
        fail("Sync could not be completed. Try again.", recovery: .none)
      }
      diagnostics?.record(error: error, source: .sync, title: "Sync failed")
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
    operationState = .failed(SyncFailure(message: message, recovery: recovery))
  }

  private func recordCancellation(reason: SyncTriggerReason) {
    operationState = .idle
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

  private func isTransientNetworkFailure(_ error: Error) -> Bool {
    let error = error as NSError
    guard error.domain == NSURLErrorDomain else {
      return false
    }
    return [
      NSURLErrorTimedOut,
      NSURLErrorCannotFindHost,
      NSURLErrorCannotConnectToHost,
      NSURLErrorNetworkConnectionLost,
      NSURLErrorDNSLookupFailed,
      NSURLErrorNotConnectedToInternet
    ].contains(error.code)
  }

  func performBackgroundSync(lease: SyncExecutionLease) async -> Bool {
    await refreshIfStale(reason: .background, lease: lease).succeeded
  }

  private func message(sampleCount: Int, importedCount: Int, reason: SyncTriggerReason) -> String {
    if sampleCount == 0 {
      return "No new pump samples were returned."
    }

    if importedCount == 0 {
      return "All returned pump samples were already imported."
    }

    return "Imported \(importedCount) new samples."
  }
}
