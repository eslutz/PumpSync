import Foundation
import Observation

@MainActor
@Observable
final class AppServices {
  let apiClient: PumpSyncAPIClient
  let authService: AuthService
  let credentialStore: TandemCredentialStore
  let healthKitService: HealthKitService
  let importedSampleLedger: ImportedSampleLedger
  let syncMetadataStore: SyncMetadataStore
  let syncCoordinator: SyncCoordinator
  let backgroundSyncScheduler: BackgroundSyncScheduler

  private init(
    apiClient: PumpSyncAPIClient,
    authService: AuthService,
    credentialStore: TandemCredentialStore,
    healthKitService: HealthKitService,
    importedSampleLedger: ImportedSampleLedger,
    syncMetadataStore: SyncMetadataStore,
    syncCoordinator: SyncCoordinator,
    backgroundSyncScheduler: BackgroundSyncScheduler
  ) {
    self.apiClient = apiClient
    self.authService = authService
    self.credentialStore = credentialStore
    self.healthKitService = healthKitService
    self.importedSampleLedger = importedSampleLedger
    self.syncMetadataStore = syncMetadataStore
    self.syncCoordinator = syncCoordinator
    self.backgroundSyncScheduler = backgroundSyncScheduler
  }

  static func live() -> AppServices {
    let apiClient = PumpSyncAPIClient.live()
    let keychain = SecureKeychainStore(service: "com.ericslutz.PumpSync")
    let credentialStore = TandemCredentialStore(keychain: keychain)
    let authService = AuthService(apiClient: apiClient)
    let healthKitService = HealthKitService()
    let importedSampleLedger = ImportedSampleLedger(keychain: keychain)
    let syncMetadataStore = SyncMetadataStore()
    let syncCoordinator = SyncCoordinator(
      apiClient: apiClient,
      authService: authService,
      credentialStore: credentialStore,
      healthKitService: healthKitService,
      importedSampleLedger: importedSampleLedger,
      syncMetadataStore: syncMetadataStore
    )
    let backgroundSyncScheduler = BackgroundSyncScheduler(identifier: AppConstants.backgroundTaskIdentifier)

    return AppServices(
      apiClient: apiClient,
      authService: authService,
      credentialStore: credentialStore,
      healthKitService: healthKitService,
      importedSampleLedger: importedSampleLedger,
      syncMetadataStore: syncMetadataStore,
      syncCoordinator: syncCoordinator,
      backgroundSyncScheduler: backgroundSyncScheduler
    )
  }
}
