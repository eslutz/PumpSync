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
  let connectionSettings: ConnectionSettingsController
  let foregroundRecovery: ForegroundRecoveryController
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
    metricKitDiagnosticsCollector: MetricKitDiagnosticsCollector,
    connectionStorage: ConnectionActivationStorage? = nil
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
    connectionSettings = ConnectionSettingsController(configuration: backendConfigurationStore, auth: authService, api: apiClient,
      sync: syncCoordinator, storage: connectionStorage ?? ConnectionActivationStorage(root: SecureKeychainStore(service: "dev.ericslutz.PumpSync.screenshots.connections")), diagnostics: diagnosticsLogStore)
    foregroundRecovery = ForegroundRecoveryController(
      setVisible: {
        authService.setConnectionProgressVisible($0)
        syncCoordinator.setForegroundActive($0)
      }
    ) {
#if DEBUG
      // Screenshot sessions are synthetic presentation fixtures, with no
      // hardware proof enrollment. Keep scene visibility, but do not replace
      // their state by attempting real foreground authentication recovery.
      guard !AppLaunchEnvironment.isScreenshotMode else { return }
#endif
      do {
        if try importedSampleLedger.migrateHmacKeyForBackgroundAccess() {
          diagnosticsLogStore.record(source: .sync, title: "Background sync ledger key migrated")
        }
      } catch {
        diagnosticsLogStore.record(error: error, source: .sync, title: "Background sync ledger migration deferred")
      }
      backgroundSyncScheduler.scheduleDailySync(trigger: "appActive")
      if let connectionStorage, !authService.isReplacingConnection {
        do { try connectionStorage.restoreConfiguration(backendConfigurationStore, apiClient: apiClient) }
        catch { return }
      }
      nativeDiagnosticsStore.reloadIfUnavailable()
      healthKitService.refreshAuthorizationStatus()
      await syncCoordinator.reconcileForegroundRecovery()
    }
    foregroundRecovery.observeSessionRecovery(authService, syncCoordinator: syncCoordinator)
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
    let connectionStorage = ConnectionActivationStorage(root: keychain)
    // The Keychain activation pointer is authoritative after a crash; replay
    // preferences before constructing services that capture configuration.
    do { try connectionStorage.restoreConfiguration(backendConfigurationStore, apiClient: apiClient) }
    catch { /* Router reads fail closed until the Keychain becomes available. */ }
    _ = backendConfigurationStore.apply(to: apiClient)
    let diagnosticsLogStore = DiagnosticsLogStore()
    let nativeDiagnosticsStore = NativeDiagnosticsStore()
    let sessionStore = BackendSessionStore(keychain: connectionStorage)
    let proofProvider = DeviceSessionProofProvider(
      keychain: connectionStorage,
      diagnostics: diagnosticsLogStore
    )
    let credentialStore = TandemCredentialStore(keychain: keychain)
    let authService = AuthService(
      apiClient: apiClient,
      configurationStore: backendConfigurationStore,
      sessionStore: sessionStore,
      proofProvider: proofProvider,
      diagnostics: diagnosticsLogStore
    )
    authService.configurationDidCommit = { try connectionStorage.updateConfiguration(backendConfigurationStore) }
    let insulinConcentrationStore = InsulinConcentrationStore()
    let healthKitService = HealthKitService(
      insulinConcentrationStore: insulinConcentrationStore,
      diagnostics: diagnosticsLogStore,
      currentContext: { authService.currentImportSnapshot(credentialRevision: credentialStore.revision) }
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
      diagnostics: diagnosticsLogStore,
      attemptStore: SyncAttemptStore(diagnostics: diagnosticsLogStore)
    )
    let backgroundSyncScheduler = BackgroundSyncScheduler(identifier: AppConstants.backgroundTaskIdentifier) { error in
      Task { @MainActor in
        diagnosticsLogStore.record(error: error, source: .sync, title: "Background sync scheduling failed")
      }
    } onEvent: { event, message in
      Task { @MainActor in
        diagnosticsLogStore.record(source: .sync, title: event, message: message)
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
      metricKitDiagnosticsCollector: metricKitDiagnosticsCollector,
      connectionStorage: connectionStorage
    )
  }

#if DEBUG
  static func screenshotFixture() -> AppServices {
    let defaultsSuiteName = "dev.ericslutz.PumpSync.screenshots"
    let defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
    defaults.removePersistentDomain(forName: defaultsSuiteName)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ScreenshotPreviewURLProtocol.self]
    let apiClient = PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: URLSession(configuration: configuration), maxRetryCount: 0)
    let backendConfigurationStore = BackendConfigurationStore(defaults: defaults)
    let diagnosticsLogStore = DiagnosticsLogStore(defaults: defaults)
    let nativeDiagnosticsStore = NativeDiagnosticsStore(defaults: defaults)
    let keychain = SecureKeychainStore(service: AppLaunchEnvironment.screenshotPreviewState == nil
      ? "dev.ericslutz.PumpSync.screenshots" : "dev.ericslutz.PumpSync.screenshots.preview")
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
      diagnostics: diagnosticsLogStore,
      proofProvider: DeviceSessionProofProvider(
        keychain: keychain,
        diagnostics: diagnosticsLogStore
      )
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
    if AppLaunchEnvironment.screenshotPreviewState != nil {
      backendConfigurationStore.selfHostedBaseURLString = "https://example.com/api"
      backendConfigurationStore.mode = .selfHosted
      _ = backendConfigurationStore.apply(to: apiClient)
      authService.applyScreenshotSession(serviceMode: "selfHosted")
    } else {
      authService.applyScreenshotSession(serviceMode: "hosted")
    }
    credentialStore.applyScreenshotStatus(
      redactedUsername: "demo@pumpsync.app",
      validatedAt: Date().addingTimeInterval(-60 * 60)
    )
    do {
      try credentialStore.saveValidated(.init(username: "demo@pumpsync.app", password: "synthetic-only", region: "us"))
    } catch {
      assertionFailure("Could not prepare synthetic screenshot credentials")
    }
    healthKitService.applyScreenshotAuthorization()
    var screenshotMetadata = if AppLaunchEnvironment.isScreenshotInitialSync {
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
    screenshotMetadata.owner = credentialStore.accountId.flatMap { accountId in
      backendConfigurationStore.selectedBaseURL.map { TandemSyncOwner(accountId: accountId, backendIdentity: ImportSessionSnapshot.canonicalBackendIdentity($0)) }
    }
    let screenshotCompletionDate = Date()
    if AppLaunchEnvironment.isScreenshotSyncSuccess {
      screenshotMetadata.lastAttemptAt = screenshotCompletionDate.addingTimeInterval(-5)
      screenshotMetadata.lastSuccessfulSyncAt = screenshotCompletionDate
      screenshotMetadata.lastSampleCount = 48
      screenshotMetadata.lastImportedCount = 4
      screenshotMetadata.lastPermissionSkippedCount = 0
      screenshotMetadata.lastErrorMessage = nil
    }
    syncMetadataStore.applyScreenshotMetadata(screenshotMetadata)
    if AppLaunchEnvironment.isScreenshotSyncing {
      syncCoordinator.applyScreenshotSyncing()
    } else if AppLaunchEnvironment.isScreenshotSyncSuccess {
      syncCoordinator.applyScreenshotSuccess(completedAt: screenshotCompletionDate)
    } else if AppLaunchEnvironment.isScreenshotSyncFailure {
      syncCoordinator.applyScreenshotFailure()
    } else if ProcessInfo.processInfo.arguments.contains("--pumpsync-screenshot-connection-failure") {
      authService.clearSessionForConnectionChange()
      syncCoordinator.applyScreenshotFailure(recovery: .openSettings)
    }
    diagnosticsLogStore.record(source: .auth, title: "PumpSync subscription active")
    diagnosticsLogStore.record(source: .sync, title: "Sync completed", message: "Returned 48, imported 48.")
    nativeDiagnosticsStore.applyScreenshotEntries([
      NativeDiagnosticEntry(
        timestamp: Date().addingTimeInterval(-2 * 60 * 60),
        kind: .performance,
        title: "Performance metrics",
        summary: "cumulativeHangTime: 0 ms\nhistogrammedTimeToFirstDraw: nominal",
        appVersion: "1.0.0",
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
