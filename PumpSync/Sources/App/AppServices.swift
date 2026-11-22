import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class AppServices {
  let previewSource: DataSourceMode
  let dataSource: any TandemDataSource
  let credentialStore: TandemCredentialStore
  let legacyInstallationID: String?
  let diagnosticsLogStore: DiagnosticsLogStore
  let nativeDiagnosticsStore: NativeDiagnosticsStore
  let insulinConcentrationStore: InsulinConcentrationStore
  let healthKitService: HealthKitService
  let importedSampleLedger: ImportedSampleLedger
  let syncMetadataStore: SyncMetadataStore
  let syncCoordinator: SyncCoordinator
  let backgroundSyncScheduler: BackgroundSyncScheduler
  let foregroundRecovery: ForegroundRecoveryController
  private let metricKitDiagnosticsCollector: MetricKitDiagnosticsCollector

  private init(dataSource: any TandemDataSource, keychain: SecureKeychainStore,
               credentialStore: TandemCredentialStore, defaults: UserDefaults,
               fixturePersistence: HealthSamplePersisting? = nil) {
    previewSource = fixturePersistence == nil ? .tandemSource : .syntheticDemo
    self.dataSource = dataSource
    self.credentialStore = credentialStore
    legacyInstallationID = AppConstants.legacyInstallationID(defaults: defaults)
    let diagnostics = DiagnosticsLogStore(defaults: defaults)
    diagnosticsLogStore = diagnostics
    let nativeDiagnostics = NativeDiagnosticsStore(defaults: defaults)
    nativeDiagnosticsStore = nativeDiagnostics
    let concentration = InsulinConcentrationStore(defaults: defaults)
    insulinConcentrationStore = concentration
    let context = { @MainActor in credentialStore.currentImportSnapshot }
    let health: HealthKitService
    if let fixturePersistence {
      health = HealthKitService(insulinConcentrationStore: concentration, diagnostics: diagnostics,
                                currentContext: context, persistence: fixturePersistence)
    } else {
      health = HealthKitService(insulinConcentrationStore: concentration, diagnostics: diagnostics, currentContext: context)
    }
    healthKitService = health
    let ledger = ImportedSampleLedger(keychain: keychain, defaults: defaults)
    importedSampleLedger = ledger
    let metadata = SyncMetadataStore(defaults: defaults)
    syncMetadataStore = metadata
    let sync = SyncCoordinator(dataSource: dataSource, credentialStore: credentialStore, healthKitService: health,
                               importedSampleLedger: ledger, syncMetadataStore: metadata, diagnostics: diagnostics,
                               attemptStore: SyncAttemptStore(defaults: defaults, diagnostics: diagnostics))
    syncCoordinator = sync
    let scheduler = BackgroundSyncScheduler(identifier: AppConstants.backgroundTaskIdentifier) { error in
      Task { @MainActor in diagnostics.record(error: error, source: .sync, title: "Background scheduling failed") }
    } onEvent: { event, message in
      Task { @MainActor in diagnostics.record(source: .sync, title: event, message: message) }
    }
    backgroundSyncScheduler = scheduler
    metricKitDiagnosticsCollector = MetricKitDiagnosticsCollector(store: nativeDiagnostics, isEnabled: fixturePersistence == nil)
    foregroundRecovery = ForegroundRecoveryController(setVisible: sync.setForegroundActive) {
      guard fixturePersistence == nil else { return }
      credentialStore.refreshStatus()
      nativeDiagnostics.reloadIfUnavailable()
      health.refreshAuthorizationStatus()
      scheduler.scheduleDailySync(trigger: "appActive")
      guard credentialStore.hasValidatedCredentials else { return }
      do { _ = try ledger.migrateHmacKeyForBackgroundAccess() }
      catch {
        diagnostics.record(source: .sync, severity: .warning, title: "Ledger key migration deferred")
        return
      }
      _ = await sync.reconcileForegroundRecovery()
    }
  }

  static func live() -> AppServices {
    let keychain = SecureKeychainStore(service: "dev.ericslutz.PumpSync")
    let credentials = TandemCredentialStore(keychain: InstallScopedCredentialStorage(keychain: keychain))
    return AppServices(dataSource: DirectTandemDataSource(), keychain: keychain,
                       credentialStore: credentials, defaults: .standard)
  }

#if DEBUG
  static func screenshotFixture() -> AppServices {
    let suite = "dev.ericslutz.PumpSync.screenshots"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let keychain = SecureKeychainStore(service: suite)
    let store = TandemCredentialStore(keychain: keychain)
    let arguments = ProcessInfo.processInfo.arguments
    do {
      try store.delete()
      if !arguments.contains("--pumpsync-screenshot-new-account") {
        defaults.set("B9871802-191D-40DA-A8F0-28432FA23762", forKey: InstallStateReconciler.legacyInstallationIdKey)
        let credentials = TandemCredentials(username: "demo@pumpsync.app", password: "synthetic-only", region: "us")
        if arguments.contains("--pumpsync-screenshot-legacy-account") {
          // Older installations saved this payload before direct validation existed.
          try keychain.writeData(try JSONEncoder().encode(credentials), account: "tandem-source-credentials")
          store.refreshStatus()
        } else {
          try store.saveValidated(credentials)
        }
      }
    } catch { preconditionFailure("Could not prepare the isolated test account") }
    let services = AppServices(dataSource: ScreenshotDataSource(state: AppLaunchEnvironment.screenshotPreviewState),
                               keychain: keychain, credentialStore: store, defaults: defaults,
                               fixturePersistence: ScreenshotHealthPersistence())
    let limitedHealth = arguments.contains("--pumpsync-screenshot-sync-notice")
    services.healthKitService.applyScreenshotAuthorization(granted: !arguments.contains("--pumpsync-screenshot-health-setup"),
                                                           deniedType: limitedHealth ? .dietaryCarbohydrates : nil)
    var metadata = SyncMetadata(lastAttemptAt: nil, lastSuccessfulSyncAt: nil, lastSampleCount: 0,
                                lastImportedCount: 0, lastErrorMessage: nil, initialImportRange: .pastTwoWeeks)
    metadata.owner = store.accountId.map { TandemSyncOwner(accountId: $0) }
    if !AppLaunchEnvironment.isScreenshotInitialSync && store.hasValidatedCredentials {
      let recent = Date().addingTimeInterval(-45 * 60)
      metadata.lastAttemptAt = recent
      metadata.lastSuccessfulSyncAt = recent
      metadata.syncWatermark = recent.addingTimeInterval(-24 * 60 * 60)
      metadata.lastSampleCount = 48
      metadata.lastImportedCount = AppLaunchEnvironment.isScreenshotSyncSuccess ? 4 : 48
      metadata.lastPermissionSkippedCount = limitedHealth ? 2 : 0
    }
    services.syncMetadataStore.applyScreenshotMetadata(metadata)
    if AppLaunchEnvironment.isScreenshotSyncing {
      services.syncCoordinator.applyScreenshotSyncing()
    } else if AppLaunchEnvironment.isScreenshotSyncSuccess {
      services.syncCoordinator.applyScreenshotSuccess(completedAt: metadata.lastSuccessfulSyncAt ?? Date(),
                                                      permissionSkipped: metadata.lastPermissionSkippedCount ?? 0)
    } else if AppLaunchEnvironment.isScreenshotSyncFailure {
      services.syncCoordinator.applyScreenshotFailure()
    } else if arguments.contains("--pumpsync-screenshot-settings-failure") || arguments.contains("--pumpsync-screenshot-connection-failure") {
      store.invalidateValidation()
      services.syncCoordinator.applyScreenshotFailure(recovery: .account)
    }
    let diagnosticsLogStore = services.diagnosticsLogStore
    let nativeDiagnosticsStore = services.nativeDiagnosticsStore
    diagnosticsLogStore.record(source: .credential, title: "Tandem account validated")
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
    if ProcessInfo.processInfo.arguments.contains("--pumpsync-screenshot-diagnostics") {
      let now = Date()
      let report = NativeDiagnosticReport.make(from: [
        "applicationTimeMetrics": ["cumulativeForegroundTime": "15 sec"],
        "cpuMetrics": ["cumulativeCPUTime": "1 sec"]
      ], windowStart: now.addingTimeInterval(-86_400), windowEnd: now)
      nativeDiagnosticsStore.applyScreenshotEntries([
        NativeDiagnosticEntry(timestamp: now, kind: .performance, title: "Performance metrics",
          summary: "CPU time: 1 sec", appVersion: "1.0.0", buildNumber: "54", report: report),
        NativeDiagnosticEntry(timestamp: now.addingTimeInterval(-86_400), kind: .performance,
          title: "Legacy performance metrics", summary: "Retained summary", appVersion: "1.0.0", buildNumber: "53")
      ])
      diagnosticsLogStore.clear()
      var attempt = SyncAttempt(operationID: UUID(), trigger: .manual, startedAt: now.addingTimeInterval(-5), stage: .recovering)
      diagnosticsLogStore.record(source: .sync, title: "Owned sync attempt", syncAttempt: attempt)
      attempt.stage = .downloading
      diagnosticsLogStore.record(source: .sync, title: "Owned sync attempt", syncAttempt: attempt)
      attempt.stage = .terminal
      attempt.outcome = .completed
      attempt.reason = .completed
      attempt.returnedCount = 48
      attempt.importedCount = 4
      attempt.completedAt = now
      attempt.durationSeconds = 5
      diagnosticsLogStore.record(source: .sync, title: "Owned sync attempt", syncAttempt: attempt)
    }
    return services
  }
#endif
}

/// Recheck the install marker before credential access. If iOS protects Keychain at launch,
/// the later unlocked read must complete fresh-install cleanup before it can return credentials.
@MainActor
private struct InstallScopedCredentialStorage: TandemCredentialPersistence {
  let keychain: SecureKeychainStore

  private func prepare() throws {
    _ = try InstallStateReconciler.reconcile { try keychain.deleteAll() }
    try LegacyConnectionCleanup.run(in: keychain, defaults: .standard)
  }

  func readData(account: String) throws -> Data? {
    try prepare()
    return try keychain.readData(account: account)
  }

  func writeData(_ data: Data, account: String) throws {
    try prepare()
    try keychain.writeData(data, account: account)
  }

  func delete(account: String) throws {
    try prepare()
    try keychain.delete(account: account)
  }
}

#if DEBUG
private struct ScreenshotDataSource: TandemDataSource {
  let state: String?

  func load(_ request: TandemSyncRequest) async throws -> TandemSyncResponse {
    if state == "loading" { try await Task.sleep(for: .seconds(120)) }
    let start = Date(timeIntervalSince1970: 1_791_158_400)
    let end = start.addingTimeInterval(30 * 60)
    let source = SourceDTO(deviceId: "Synthetic pump", eventIds: [])
    let samples: [SampleDTO] = state == "empty" ? [] : [
      .init(externalId: "fixture-basal", type: "insulin.basal", value: 0.25, unit: "IU",
            startAt: start, endAt: end, metadata: [:], source: source),
      .init(externalId: "fixture-bolus", type: "insulin.bolus", value: 1.2, unit: "IU",
            startAt: end, endAt: end, metadata: [:], source: source),
      .init(externalId: "fixture-carbs", type: "nutrition.carbohydrates", value: 24, unit: "g",
            startAt: end, endAt: end, metadata: [:], source: source)
    ]
    return .init(samples: samples, effectiveMinDate: start, effectiveMaxDate: start.addingTimeInterval(86400),
                 dataSourceMode: .syntheticDemo)
  }
}

@MainActor
private struct ScreenshotHealthPersistence: HealthSamplePersisting {
  func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus { .notDetermined }
  func save(_ samples: [HKQuantitySample], completion: @escaping @Sendable (Bool, Error?) -> Void) {
    completion(false, HealthKitError.writeFailed)
  }
}
#endif
