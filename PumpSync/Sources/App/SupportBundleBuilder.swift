import Foundation
import UIKit

struct AppBundleInfo {
  let version: String
  let build: String

  init(version: String, build: String) {
    self.version = version
    self.build = build
  }

  init(bundle: Bundle = .main) {
    version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
  }
}

struct SupportBundleContext {
  let bundleInfo: AppBundleInfo
  let systemVersion: String
  let deviceModel: String
  let backendMode: String
  let syncMetadata: SyncMetadata
  let appDiagnostics: [DiagnosticEntry]
  let nativeDiagnostics: [NativeDiagnosticEntry]
  var syncAttempts: [SyncAttempt] = []
  var activeSyncAttempt: SyncAttempt? = nil
  var sessionProtocolVersion: Int? = nil
  var deviceProofKind: String? = nil
  var refreshCredentialExpiresAt: Date? = nil
  var refreshCredentialAbsoluteExpiresAt: Date? = nil
}

enum SupportBundleBuilder {
  static func build(context: SupportBundleContext, generatedAt: Date = Date()) -> String {
    let history = SyncHistoryPresentation(metadata: context.syncMetadata,
      attempts: (context.activeSyncAttempt.map { [$0] } ?? []) + context.syncAttempts)
    let lines = [
      "# PumpSync Support Bundle",
      "",
      "Generated: \(format(generatedAt))",
      "App Version: \(context.bundleInfo.version) (\(context.bundleInfo.build))",
      "iOS Version: \(context.systemVersion)",
      "Device Model: \(context.deviceModel)",
      "Connection Mode: \(context.backendMode)",
      "",
      "## Authentication",
      "Session Protocol: \(context.sessionProtocolVersion.map(String.init) ?? "None")",
      "Device Proof: \(context.deviceProofKind ?? "None")",
      "Refresh Credential Idle Expiry: \(format(context.refreshCredentialExpiresAt))",
      "Refresh Credential Absolute Expiry: \(format(context.refreshCredentialAbsoluteExpiresAt))",
      "",
      "## Sync — current pump account and server",
      "Last Attempt: \(format(history.lastAttempt))",
      "Last Success: \(format(context.syncMetadata.lastSuccessfulSyncAt))",
      "Last Returned Count: \(history.returned.map(String.init) ?? "Not recorded")",
      "Last Imported Count: \(history.imported.map(String.init) ?? "Not recorded")",
      "Last Error: \(redacted(context.syncMetadata.lastErrorMessage ?? ((context.activeSyncAttempt != nil || !context.syncAttempts.isEmpty) ? "See owned attempt history" : "None")))",
      "Initial Import Range: \(context.syncMetadata.initialImportRange.rawValue)",
      "Counts describe the last successful sync for this account and server.",
      "Permission-skipped records: \(history.permissionSkipped.map(String.init) ?? "Not recorded")",
      history.resetDescription ?? "",
      "",
      "## Owned Sync Attempts",
      attemptLines(context),
      "",
      "## App Event Log",
      diagnosticLines(context.appDiagnostics),
      "",
      "## iOS Performance Diagnostics",
      nativeDiagnosticLines(context.nativeDiagnostics)
    ]

    return redacted(lines.joined(separator: "\n"))
  }

  @MainActor
  static func build(services: AppServices, generatedAt: Date = Date()) -> String {
    build(
      context: SupportBundleContext(
        bundleInfo: AppBundleInfo(),
        systemVersion: UIDevice.current.systemVersion,
        deviceModel: UIDevice.current.model,
        backendMode: services.backendConfigurationStore.mode.title,
        syncMetadata: services.syncMetadataStore.metadata,
        appDiagnostics: Array(services.diagnosticsLogStore.entries.prefix(50)),
        nativeDiagnostics: Array(services.nativeDiagnosticsStore.entries.prefix(50)),
        syncAttempts: services.syncCoordinator.attemptStore.history,
        activeSyncAttempt: services.syncCoordinator.attemptStore.active,
        sessionProtocolVersion: services.authService.session?.protocolVersion,
        deviceProofKind: services.authService.session?.protocolVersion == 3
          ? (services.backendConfigurationStore.mode == .hosted ? "App Attest" : "Secure Enclave P-256")
          : nil,
        refreshCredentialExpiresAt: services.authService.session?.refreshTokenExpiresAt,
        refreshCredentialAbsoluteExpiresAt: services.authService.session?.refreshTokenAbsoluteExpiresAt
      ),
      generatedAt: generatedAt
    )
  }

  private static func attemptLines(_ context: SupportBundleContext) -> String {
    let attempts = context.activeSyncAttempt.map { [$0] } ?? []
    let entries = attempts + Array(context.syncAttempts.prefix(20))
    return entries.isEmpty ? "No owned sync attempts recorded." : entries.map { "- " + SyncAttemptStore.description($0) }.joined(separator: "\n")
  }

  private static func diagnosticLines(_ entries: [DiagnosticEntry]) -> String {
    guard !entries.isEmpty else {
      return "No app diagnostics recorded."
    }

    return entries.prefix(50).map(DiagnosticPresentation.export).joined(separator: "\n\n")
  }

  private static func nativeDiagnosticLines(_ entries: [NativeDiagnosticEntry]) -> String {
    guard !entries.isEmpty else { return "No native diagnostics recorded." }
    return entries.prefix(50).map(DiagnosticPresentation.export).joined(separator: "\n\n")
  }

  private static func redacted(_ value: String) -> String {
    DiagnosticsLogStore.redacted(value)
  }

  private static func format(_ date: Date?) -> String {
    guard let date else {
      return "Never"
    }

    return ISO8601DateFormatter().string(from: date)
  }
}
