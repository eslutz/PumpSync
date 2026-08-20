import Foundation
import Observation

enum SyncTriggerReason: String, Equatable {
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
  /// Returns the subset of samples actually written to Apple Health.
  func save(samples: [SampleDTO]) async throws -> [SampleDTO]
}

extension HealthKitService: SyncHealthWriting {}

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
  private let importedSampleLedger: ImportedSampleLedger
  private let syncMetadataStore: SyncMetadataStore
  private let diagnostics: DiagnosticsLogStore?

  private(set) var operationState: SyncOperationState = .idle

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
    importedSampleLedger: ImportedSampleLedger,
    syncMetadataStore: SyncMetadataStore,
    diagnostics: DiagnosticsLogStore? = nil
  ) {
    self.apiClient = apiClient
    self.authService = authService
    self.credentialStore = credentialStore
    self.healthKitService = healthKitService
    self.importedSampleLedger = importedSampleLedger
    self.syncMetadataStore = syncMetadataStore
    self.diagnostics = diagnostics
  }

  func refreshIfStale(reason: SyncTriggerReason) async {
    let lastSuccessfulSyncAt = syncMetadataStore.metadata.lastSuccessfulSyncAt
    let ageSeconds = lastSuccessfulSyncAt.map { max(0, Date().timeIntervalSince($0)) }
    let shouldRefresh = ageSeconds.map { $0 >= AppConstants.staleSyncInterval } ?? true
    let ageDescription = ageSeconds.map { String(Int($0)) } ?? "none"
    diagnostics?.record(
      source: .sync,
      title: "Background sync freshness evaluated",
      message: "build=\(BackgroundSyncDiagnostics.buildNumber) reason=\(reason.rawValue) decision=\(shouldRefresh ? "sync" : "skip") lastSuccessAgeSeconds=\(ageDescription) targetSeconds=\(Int(AppConstants.staleSyncInterval))"
    )

    guard shouldRefresh else {
      diagnostics?.record(source: .sync, title: "Sync skipped", message: "Last successful sync is within the four-hour freshness target.")
      return
    }

    await sync(reason: reason)
  }

  func startManualSync() {
    guard beginSync(reason: .manual) else {
      return
    }

    Task { [weak self] in
      await self?.performSync(reason: .manual)
    }
  }

  func retry() {
    guard case .failed(let failure) = operationState, failure.recovery == .retry else {
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

  func sync(reason: SyncTriggerReason) async {
    guard beginSync(reason: reason) else {
      return
    }

    await performSync(reason: reason)
  }

  private func beginSync(reason: SyncTriggerReason) -> Bool {
    guard !isSyncing else {
      return false
    }
    operationState = .running(SyncProgress(phase: .preparing, trigger: reason, startedAt: Date()))
    return true
  }

  private func performSync(reason: SyncTriggerReason) async {
    let startedAt: Date
    if case .running(let progress) = operationState {
      startedAt = progress.startedAt
    } else {
      return
    }

    // A background launch has no view lifecycle to refresh permission state,
    // so refresh it here rather than relying on a view's .task/.onAppear.
    healthKitService.refreshAuthorizationStatus()

    guard let accessToken = await authService.accessTokenRecoveringIfNeeded(
      allowInteractiveRecovery: reason == .manual
    ) else {
      fail("Connect PumpSync before syncing.", recovery: .openSettings)
      diagnostics?.record(source: .sync, severity: .warning, title: "Sync blocked", message: "Missing connection session.")
      return
    }

    guard credentialStore.hasValidatedCredentials else {
      fail("Save your pump account credentials before syncing.", recovery: .openSettings)
      diagnostics?.record(source: .sync, severity: .warning, title: "Sync blocked", message: "Pump account credentials are not validated.")
      return
    }

    guard let credentials = try? credentialStore.load() else {
      fail("Add your pump account before syncing.", recovery: .openSettings)
      diagnostics?.record(source: .sync, severity: .warning, title: "Sync blocked", message: "Missing pump account credentials.")
      return
    }

    guard healthKitService.hasAnyWritePermission else {
      fail("Enable Apple Health write access before syncing.", recovery: .openSettings)
      diagnostics?.record(source: .sync, severity: .warning, title: "Sync blocked", message: "No Apple Health write permissions are enabled.")
      return
    }

    syncMetadataStore.recordAttempt()
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
      recordBackgroundStage(.downloading, startedAt: startedAt, reason: reason)
      let response = try await apiClient.syncTandem(request, accessToken: accessToken)
      let unseenSamples = try importedSampleLedger.filterUnseen(response.samples)
      // Record only what Apple Health confirmed: save() drops samples whose
      // per-type permission is missing, and marking those imported would
      // permanently lose them — the backend retains nothing to replay, so a
      // later permission grant could never backfill an already-ledgered
      // sample.
      operationState = .running(SyncProgress(phase: .updatingHealth, trigger: reason, startedAt: startedAt))
      recordBackgroundStage(.updatingHealth, startedAt: startedAt, reason: reason)
      let writtenSamples = try await healthKitService.save(samples: unseenSamples)
      try importedSampleLedger.recordImported(writtenSamples)
      let importedCount = writtenSamples.count
      let watermark = response.effectiveMaxDate.addingTimeInterval(-Self.watermarkOverlap)
      syncMetadataStore.recordSuccess(sampleCount: response.samples.count, importedCount: importedCount, completedAt: Date(), watermark: watermark)
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
    } catch {
      let apiError = error as? APIClientError
      if apiError?.isAuthenticationFailure == true {
        authService.clearSessionForAuthenticationFailure()
      }
      if apiError?.isTandemCredentialFailure == true {
        // Tandem rejected the stored pump credentials — retrying cannot
        // succeed. Drop the validated flag so the UI routes the user to the
        // credential form, and show the backend's remediation message.
        credentialStore.invalidateValidation()
      }
      syncMetadataStore.recordFailure(error)
      if apiError?.isTandemCredentialFailure == true {
        fail(
          apiError?.errorDescription
            ?? "Tandem Source did not accept your pump account credentials. Re-save your Tandem account.",
          recovery: .openSettings
        )
      } else if apiError?.isAuthenticationFailure == true {
        fail("Sync could not be completed. Try again.", recovery: .openSettings)
      } else if apiError?.isRateLimited == true {
        fail("Sync limit reached. Wait a while before trying again.", recovery: .waitAndRetry)
      } else if isHealthAuthorizationFailure(error) {
        fail("Enable Apple Health write access before syncing.", recovery: .openSettings)
      } else if apiError?.isTransient == true || isTransientNetworkFailure(error) {
        fail("Sync could not be completed. Try again.", recovery: .retry)
      } else {
        fail("Sync could not be completed. Try again.", recovery: .none)
      }
      diagnostics?.record(error: error, source: .sync, title: "Sync failed")
    }

  }

  private func fail(_ message: String, recovery: SyncRecovery) {
    operationState = .failed(SyncFailure(message: message, recovery: recovery))
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

  func performBackgroundSync() async {
    await refreshIfStale(reason: .background)
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
