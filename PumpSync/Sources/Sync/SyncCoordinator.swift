import Foundation
import Observation

enum SyncTriggerReason: String {
  case appOpen
  case manual
  case background
}

/// The slice of HealthKitService's surface SyncCoordinator depends on,
/// extracted as a seam so tests can substitute a fake — real HealthKit
/// authorization/writes require device interaction and aren't something a
/// unit test can drive deterministically.
@MainActor
protocol SyncHealthWriting {
  func refreshAuthorizationStatus()
  var hasAnyWritePermission: Bool { get }
  func save(samples: [SampleDTO]) async throws -> Int
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

  private let apiClient: PumpSyncAPIClient
  private let authService: AuthService
  private let credentialStore: TandemCredentialStore
  private let healthKitService: SyncHealthWriting
  private let importedSampleLedger: ImportedSampleLedger
  private let syncMetadataStore: SyncMetadataStore
  private let diagnostics: DiagnosticsLogStore?

  private(set) var isSyncing = false
  private(set) var lastMessage: String?

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
    guard shouldRefreshForStaleness else {
      return
    }

    await sync(reason: reason)
  }

  func sync(reason: SyncTriggerReason) async {
    guard !isSyncing else {
      return
    }

    // A background launch has no view lifecycle to refresh permission state,
    // so refresh it here rather than relying on a view's .task/.onAppear.
    healthKitService.refreshAuthorizationStatus()

    guard let accessToken = await authService.accessTokenRecoveringIfNeeded() else {
      lastMessage = "Connect PumpSync before syncing."
      diagnostics?.record(source: .sync, severity: .warning, title: "Sync blocked", message: "Missing connection session.")
      return
    }

    guard credentialStore.hasValidatedCredentials else {
      lastMessage = "Save your pump account credentials before syncing."
      diagnostics?.record(source: .sync, severity: .warning, title: "Sync blocked", message: "Pump account credentials are not validated.")
      return
    }

    guard let credentials = try? credentialStore.load() else {
      lastMessage = "Add your pump account before syncing."
      diagnostics?.record(source: .sync, severity: .warning, title: "Sync blocked", message: "Missing pump account credentials.")
      return
    }

    guard healthKitService.hasAnyWritePermission else {
      lastMessage = "Enable Apple Health write access before syncing."
      diagnostics?.record(source: .sync, severity: .warning, title: "Sync blocked", message: "No Apple Health write permissions are enabled.")
      return
    }

    isSyncing = true
    lastMessage = nil
    syncMetadataStore.recordAttempt()
    diagnostics?.record(source: .sync, title: "Sync started", message: "Reason: \(reason.rawValue)")

    do {
      let now = Date()
      let request = TandemSyncRequest(
        tandem: credentials,
        deviceId: nil,
        minDate: syncMetadataStore.metadata.syncWatermark
          ?? syncMetadataStore.metadata.initialImportRange.minimumDate(relativeTo: now),
        maxDate: now
      )
      let response = try await apiClient.syncTandem(request, accessToken: accessToken)
      let unseenSamples = try importedSampleLedger.filterUnseen(response.samples)
      let importedCount = try await healthKitService.save(samples: unseenSamples)
      try importedSampleLedger.recordImported(unseenSamples)
      let watermark = response.effectiveMaxDate.addingTimeInterval(-Self.watermarkOverlap)
      syncMetadataStore.recordSuccess(sampleCount: response.samples.count, importedCount: importedCount, completedAt: Date(), watermark: watermark)
      lastMessage = message(sampleCount: response.samples.count, importedCount: importedCount, reason: reason)
      diagnostics?.record(
        source: .sync,
        title: "Sync completed",
        message: "Returned \(response.samples.count), imported \(importedCount), reason \(reason.rawValue)."
      )
    } catch {
      if (error as? APIClientError)?.isAuthenticationFailure == true {
        authService.clearSessionForAuthenticationFailure()
      }
      syncMetadataStore.recordFailure(error)
      lastMessage = "Sync could not be completed. Try again."
      diagnostics?.record(error: error, source: .sync, title: "Sync failed")
    }

    isSyncing = false
  }

  func performBackgroundSync() async {
    await refreshIfStale(reason: .background)
  }

  func recordDailySyncRequested() {
    diagnostics?.record(source: .backgroundSync, title: "Daily background sync requested")
  }

  private var shouldRefreshForStaleness: Bool {
    guard let lastSuccessfulSyncAt = syncMetadataStore.metadata.lastSuccessfulSyncAt else {
      return true
    }

    return Date().timeIntervalSince(lastSuccessfulSyncAt) >= AppConstants.staleSyncInterval
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
