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

#if DEBUG
  static func screenshotFixture() -> AppServices {
    let defaultsSuiteName = "dev.ericslutz.PumpSync.screenshots"
    let defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
    defaults.removePersistentDomain(forName: defaultsSuiteName)

    let apiClient = PumpSyncAPIClient.live()
    apiClient.maxRetryCount = 0
    let backendConfigurationStore = BackendConfigurationStore(defaults: defaults)
    let diagnosticsLogStore = DiagnosticsLogStore()
    let keychain = SecureKeychainStore(service: "dev.ericslutz.PumpSync.screenshots")
    let credentialStore = TandemCredentialStore(keychain: keychain)
    let healthKitService = HealthKitService(diagnostics: diagnosticsLogStore)
    let importedSampleLedger = ImportedSampleLedger(keychain: keychain)
    let syncMetadataStore = SyncMetadataStore(defaults: defaults)
    let authService = AuthService(
      apiClient: apiClient,
      configurationStore: backendConfigurationStore,
      currentEntitlementJWS: { "screenshot-transaction-jws" },
      createSubscriptionSession: { _ in
        BackendSessionResponse(
          accessToken: "screenshot-access-token",
          expiresAt: Date().addingTimeInterval(60 * 60),
          entitlementActive: true,
          serviceMode: "hosted"
        )
      },
      createSelfHostedSession: { _ in
        BackendSessionResponse(
          accessToken: "screenshot-self-hosted-token",
          expiresAt: Date().addingTimeInterval(60 * 60),
          entitlementActive: true,
          serviceMode: "selfHosted"
        )
      },
      diagnostics: diagnosticsLogStore
    )
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

    backendConfigurationStore.mode = .hosted
    backendConfigurationStore.selfHostedBaseURLString = "https://self-hosted.example.com/api"
    authService.applyScreenshotSession(serviceMode: "hosted")
    credentialStore.applyScreenshotStatus(
      redactedUsername: "demo@pumpsync.app",
      validatedAt: Date().addingTimeInterval(-60 * 60)
    )
    healthKitService.applyScreenshotAuthorization()
    syncMetadataStore.applyScreenshotMetadata(
      SyncMetadata(
        lastAttemptAt: Date().addingTimeInterval(-45 * 60),
        lastSuccessfulSyncAt: Date().addingTimeInterval(-45 * 60),
        lastSampleCount: 48,
        lastImportedCount: 48,
        lastErrorMessage: nil,
        initialImportRange: .pastWeek
      )
    )
    diagnosticsLogStore.record(source: .auth, title: "Hosted subscription active")
    diagnosticsLogStore.record(source: .sync, title: "Sync completed", message: "Returned 48, imported 48.")

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
#endif
}
