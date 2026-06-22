import Foundation
import Observation

@MainActor
@Observable
final class AppServices {
  let apiClient: PumpSyncAPIClient
  let backendConfigurationStore: BackendConfigurationStore
  let diagnosticsLogStore: DiagnosticsLogStore
  let nativeDiagnosticsStore: NativeDiagnosticsStore
  let authService: AuthService
  let credentialStore: TandemCredentialStore
  let insulinConcentrationStore: InsulinConcentrationStore
  let healthKitService: HealthKitService
  let importedSampleLedger: ImportedSampleLedger
  let syncMetadataStore: SyncMetadataStore
  let syncCoordinator: SyncCoordinator
  let backgroundSyncScheduler: BackgroundSyncScheduler
  private let metricKitDiagnosticsCollector: MetricKitDiagnosticsCollector

  private init(
    apiClient: PumpSyncAPIClient,
    backendConfigurationStore: BackendConfigurationStore,
    diagnosticsLogStore: DiagnosticsLogStore,
    nativeDiagnosticsStore: NativeDiagnosticsStore,
    authService: AuthService,
    credentialStore: TandemCredentialStore,
    insulinConcentrationStore: InsulinConcentrationStore,
    healthKitService: HealthKitService,
    importedSampleLedger: ImportedSampleLedger,
    syncMetadataStore: SyncMetadataStore,
    syncCoordinator: SyncCoordinator,
    backgroundSyncScheduler: BackgroundSyncScheduler,
    metricKitDiagnosticsCollector: MetricKitDiagnosticsCollector
  ) {
    self.apiClient = apiClient
    self.backendConfigurationStore = backendConfigurationStore
    self.diagnosticsLogStore = diagnosticsLogStore
    self.nativeDiagnosticsStore = nativeDiagnosticsStore
    self.authService = authService
    self.credentialStore = credentialStore
    self.insulinConcentrationStore = insulinConcentrationStore
    self.healthKitService = healthKitService
    self.importedSampleLedger = importedSampleLedger
    self.syncMetadataStore = syncMetadataStore
    self.syncCoordinator = syncCoordinator
    self.backgroundSyncScheduler = backgroundSyncScheduler
    self.metricKitDiagnosticsCollector = metricKitDiagnosticsCollector
  }

  static func live() -> AppServices {
    let apiClient = PumpSyncAPIClient.live()
    let backendConfigurationStore = BackendConfigurationStore()
    _ = backendConfigurationStore.apply(to: apiClient)
    let diagnosticsLogStore = DiagnosticsLogStore()
    let nativeDiagnosticsStore = NativeDiagnosticsStore()
    let keychain = SecureKeychainStore(service: "dev.ericslutz.PumpSync")
    let sessionStore = BackendSessionStore(keychain: keychain)
    let credentialStore = TandemCredentialStore(keychain: keychain)
    let authService = AuthService(
      apiClient: apiClient,
      configurationStore: backendConfigurationStore,
      sessionStore: sessionStore,
      diagnostics: diagnosticsLogStore
    )
    let insulinConcentrationStore = InsulinConcentrationStore()
    let healthKitService = HealthKitService(
      insulinConcentrationStore: insulinConcentrationStore,
      diagnostics: diagnosticsLogStore
    )
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
    let metricKitDiagnosticsCollector = MetricKitDiagnosticsCollector(store: nativeDiagnosticsStore)

    return AppServices(
      apiClient: apiClient,
      backendConfigurationStore: backendConfigurationStore,
      diagnosticsLogStore: diagnosticsLogStore,
      nativeDiagnosticsStore: nativeDiagnosticsStore,
      authService: authService,
      credentialStore: credentialStore,
      insulinConcentrationStore: insulinConcentrationStore,
      healthKitService: healthKitService,
      importedSampleLedger: importedSampleLedger,
      syncMetadataStore: syncMetadataStore,
      syncCoordinator: syncCoordinator,
      backgroundSyncScheduler: backgroundSyncScheduler,
      metricKitDiagnosticsCollector: metricKitDiagnosticsCollector
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
    let nativeDiagnosticsStore = NativeDiagnosticsStore(defaults: defaults)
    let keychain = SecureKeychainStore(service: "dev.ericslutz.PumpSync.screenshots")
    let sessionStore = BackendSessionStore(keychain: keychain)
    let credentialStore = TandemCredentialStore(keychain: keychain)
    let insulinConcentrationStore = InsulinConcentrationStore(defaults: defaults)
    let healthKitService = HealthKitService(
      insulinConcentrationStore: insulinConcentrationStore,
      diagnostics: diagnosticsLogStore
    )
    let importedSampleLedger = ImportedSampleLedger(keychain: keychain)
    let syncMetadataStore = SyncMetadataStore(defaults: defaults)
    let authService = AuthService(
      apiClient: apiClient,
      configurationStore: backendConfigurationStore,
      sessionStore: sessionStore,
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
    backendConfigurationStore.selfHostedBaseURLString = ""
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
    nativeDiagnosticsStore.applyScreenshotEntries([
      NativeDiagnosticEntry(
        timestamp: Date().addingTimeInterval(-2 * 60 * 60),
        kind: .performance,
        title: "Performance metrics",
        summary: "cumulativeHangTime: 0 ms\nhistogrammedTimeToFirstDraw: nominal",
        appVersion: "1.0",
        buildNumber: "1"
      )
    ])
    let metricKitDiagnosticsCollector = MetricKitDiagnosticsCollector(store: nativeDiagnosticsStore, isEnabled: false)

    return AppServices(
      apiClient: apiClient,
      backendConfigurationStore: backendConfigurationStore,
      diagnosticsLogStore: diagnosticsLogStore,
      nativeDiagnosticsStore: nativeDiagnosticsStore,
      authService: authService,
      credentialStore: credentialStore,
      insulinConcentrationStore: insulinConcentrationStore,
      healthKitService: healthKitService,
      importedSampleLedger: importedSampleLedger,
      syncMetadataStore: syncMetadataStore,
      syncCoordinator: syncCoordinator,
      backgroundSyncScheduler: backgroundSyncScheduler,
      metricKitDiagnosticsCollector: metricKitDiagnosticsCollector
    )
  }
#endif
}
