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
    let keychain = SecureKeychainStore(service: "dev.ericslutz.PumpSync")
    do {
      _ = try InstallStateReconciler.reconcile {
        try keychain.deleteAll()
      }
    } catch {
      assertionFailure("Fresh-install Keychain cleanup failed: \(error.localizedDescription)")
    }
    let backendConfigurationStore = BackendConfigurationStore()
    _ = backendConfigurationStore.apply(to: apiClient)
    let diagnosticsLogStore = DiagnosticsLogStore()
    let nativeDiagnosticsStore = NativeDiagnosticsStore()
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
    let backgroundSyncScheduler = BackgroundSyncScheduler(identifier: AppConstants.backgroundTaskIdentifier) { error in
      Task { @MainActor in
        diagnosticsLogStore.record(error: error, source: .sync, title: "Background sync scheduling failed")
      }
    } onEvent: { event in
      Task { @MainActor in
        diagnosticsLogStore.record(source: .sync, title: event)
      }
    }
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
    let diagnosticsLogStore = DiagnosticsLogStore(defaults: defaults)
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
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in
        BackendSessionResponse(
          accessToken: "screenshot-self-hosted-token",
          expiresAt: Date().addingTimeInterval(60 * 60),
          serviceMode: "selfHosted",
          dataSourceMode: "tandemSource"
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
    let screenshotMetadata = if AppLaunchEnvironment.isScreenshotInitialSync {
      SyncMetadata(
        lastAttemptAt: nil,
        lastSuccessfulSyncAt: nil,
        lastSampleCount: 0,
        lastImportedCount: 0,
        lastErrorMessage: nil,
        initialImportRange: .pastTwoWeeks
      )
    } else {
      SyncMetadata(
        lastAttemptAt: Date().addingTimeInterval(-45 * 60),
        lastSuccessfulSyncAt: Date().addingTimeInterval(-45 * 60),
        lastSampleCount: 48,
        lastImportedCount: 48,
        lastErrorMessage: nil,
        initialImportRange: .pastWeek
      )
    }
    syncMetadataStore.applyScreenshotMetadata(screenshotMetadata)
    if AppLaunchEnvironment.isScreenshotSyncing {
      syncCoordinator.applyScreenshotSyncing()
    } else if AppLaunchEnvironment.isScreenshotSyncSuccess {
      syncCoordinator.applyScreenshotSuccess()
    } else if AppLaunchEnvironment.isScreenshotSyncFailure {
      syncCoordinator.applyScreenshotFailure()
    }
    diagnosticsLogStore.record(source: .auth, title: "PumpSync subscription active")
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
