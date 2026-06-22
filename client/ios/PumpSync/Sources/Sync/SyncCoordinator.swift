import Foundation
import Observation

enum SyncTriggerReason: String {
  case appOpen
  case manual
  case background
}

@MainActor
@Observable
final class SyncCoordinator {
  private let apiClient: PumpSyncAPIClient
  private let authService: AuthService
  private let credentialStore: TandemCredentialStore
  private let healthKitService: HealthKitService
  private let importedSampleLedger: ImportedSampleLedger
  private let syncMetadataStore: SyncMetadataStore
  private let diagnostics: DiagnosticsLogStore?

  private(set) var isSyncing = false
  private(set) var lastMessage: String?

  init(
    apiClient: PumpSyncAPIClient,
    authService: AuthService,
    credentialStore: TandemCredentialStore,
    healthKitService: HealthKitService,
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

    guard let accessToken = authService.accessToken else {
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
        minDate: syncMetadataStore.metadata.lastSuccessfulSyncAt
          ?? syncMetadataStore.metadata.initialImportRange.minimumDate(relativeTo: now),
        maxDate: now
      )
      let response = try await apiClient.syncTandem(request, accessToken: accessToken)
      let unseenSamples = try importedSampleLedger.filterUnseen(response.samples)
      let importedCount = try await healthKitService.save(samples: unseenSamples)
      try importedSampleLedger.recordImported(unseenSamples)
      syncMetadataStore.recordSuccess(sampleCount: response.samples.count, importedCount: importedCount)
      lastMessage = message(sampleCount: response.samples.count, importedCount: importedCount, reason: reason)
      diagnostics?.record(
        source: .sync,
        title: "Sync completed",
        message: "Returned \(response.samples.count), imported \(importedCount), reason \(reason.rawValue)."
      )
    } catch {
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
