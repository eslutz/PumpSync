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

  private(set) var isSyncing = false
  private(set) var lastMessage: String?

  init(
    apiClient: PumpSyncAPIClient,
    authService: AuthService,
    credentialStore: TandemCredentialStore,
    healthKitService: HealthKitService,
    importedSampleLedger: ImportedSampleLedger,
    syncMetadataStore: SyncMetadataStore
  ) {
    self.apiClient = apiClient
    self.authService = authService
    self.credentialStore = credentialStore
    self.healthKitService = healthKitService
    self.importedSampleLedger = importedSampleLedger
    self.syncMetadataStore = syncMetadataStore
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
      lastMessage = "Sign in before syncing."
      return
    }

    guard let credentials = try? credentialStore.load() else {
      lastMessage = "Add Tandem credentials before syncing."
      return
    }

    isSyncing = true
    lastMessage = nil
    syncMetadataStore.recordAttempt()

    do {
      let request = TandemSyncRequest(
        tandem: credentials,
        deviceId: nil,
        minDate: syncMetadataStore.metadata.lastSuccessfulSyncAt,
        maxDate: Date()
      )
      let response = try await apiClient.syncTandem(request, accessToken: accessToken)
      let unseenSamples = try importedSampleLedger.filterUnseen(response.samples)
      let importedCount = try await healthKitService.save(samples: unseenSamples)
      try importedSampleLedger.recordImported(unseenSamples)
      syncMetadataStore.recordSuccess(sampleCount: response.samples.count, importedCount: importedCount)
      lastMessage = message(sampleCount: response.samples.count, importedCount: importedCount, reason: reason)
    } catch {
      syncMetadataStore.recordFailure(error)
      lastMessage = error.localizedDescription
    }

    isSyncing = false
  }

  func performBackgroundSync() async {
    await refreshIfStale(reason: .background)
  }

  func recordDailySyncRequested() {
    lastMessage = "Daily background sync requested."
  }

  private var shouldRefreshForStaleness: Bool {
    guard let lastSuccessfulSyncAt = syncMetadataStore.metadata.lastSuccessfulSyncAt else {
      return true
    }

    return Date().timeIntervalSince(lastSuccessfulSyncAt) >= AppConstants.staleSyncInterval
  }

  private func message(sampleCount: Int, importedCount: Int, reason: SyncTriggerReason) -> String {
    if sampleCount == 0 {
      return "No new Tandem samples were returned."
    }

    if importedCount == 0 {
      return "All returned Tandem samples were already imported."
    }

    return "Imported \(importedCount) of \(sampleCount) samples from \(reason.rawValue)."
  }
}
