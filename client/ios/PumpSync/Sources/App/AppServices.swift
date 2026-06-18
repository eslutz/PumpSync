import Foundation
import Observation

@MainActor
@Observable
final class AppServices {
  let apiClient: PumpSyncAPIClient
  let backendConfigurationStore: BackendConfigurationStore
  let diagnosticsLogStore: DiagnosticsLogStore
  let authService: AuthService
  let credentialStore: TandemCredentialStore
  let healthKitService: HealthKitService
  let importedSampleLedger: ImportedSampleLedger
  let syncMetadataStore: SyncMetadataStore
  let syncCoordinator: SyncCoordinator
  let backgroundSyncScheduler: BackgroundSyncScheduler

  private init(
    apiClient: PumpSyncAPIClient,
    backendConfigurationStore: BackendConfigurationStore,
    diagnosticsLogStore: DiagnosticsLogStore,
    authService: AuthService,
    credentialStore: TandemCredentialStore,
    healthKitService: HealthKitService,
    importedSampleLedger: ImportedSampleLedger,
    syncMetadataStore: SyncMetadataStore,
    syncCoordinator: SyncCoordinator,
    backgroundSyncScheduler: BackgroundSyncScheduler
  ) {
    self.apiClient = apiClient
    self.backendConfigurationStore = backendConfigurationStore
    self.diagnosticsLogStore = diagnosticsLogStore
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
    let backendConfigurationStore = BackendConfigurationStore()
    _ = backendConfigurationStore.apply(to: apiClient)
    let diagnosticsLogStore = DiagnosticsLogStore()
    let keychain = SecureKeychainStore(service: "dev.ericslutz.PumpSync")
    let credentialStore = TandemCredentialStore(keychain: keychain)
    let authService = AuthService(apiClient: apiClient, configurationStore: backendConfigurationStore, diagnostics: diagnosticsLogStore)
    let healthKitService = HealthKitService(diagnostics: diagnosticsLogStore)
    let importedSampleLedger = ImportedSampleLedger(keychain: keychain)
    let syncMetadataStore = SyncMetadataStore()
    let syncCoordinator = SyncCoordinator(
      apiClient: apiClient,
      authService: authService,
      credentialStore: credentialStore,
      healthKitService: healthKitService,
      importedSampleLedger: importedSampleLedger,
      syncMetadataStore: syncMetadataStore,
      diagnostics: diagnosticsLogStore
    )
    let backgroundSyncScheduler = BackgroundSyncScheduler(identifier: AppConstants.backgroundTaskIdentifier)

    return AppServices(
      apiClient: apiClient,
      backendConfigurationStore: backendConfigurationStore,
      diagnosticsLogStore: diagnosticsLogStore,
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
