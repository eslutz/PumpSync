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
  var sessionProtocolVersion: Int? = nil
  var deviceProofKind: String? = nil
  var refreshCredentialExpiresAt: Date? = nil
  var refreshCredentialAbsoluteExpiresAt: Date? = nil
}

enum SupportBundleBuilder {
  static func build(context: SupportBundleContext, generatedAt: Date = Date()) -> String {
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
      "## Sync",
      "Last Attempt: \(format(context.syncMetadata.lastAttemptAt))",
      "Last Success: \(format(context.syncMetadata.lastSuccessfulSyncAt))",
      "Last Returned Count: \(context.syncMetadata.lastSampleCount)",
      "Last Imported Count: \(context.syncMetadata.lastImportedCount)",
      "Last Error: \(redacted(context.syncMetadata.lastErrorMessage ?? "None"))",
      "Initial Import Range: \(context.syncMetadata.initialImportRange.rawValue)",
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
        sessionProtocolVersion: services.authService.session?.protocolVersion,
        deviceProofKind: services.authService.session?.protocolVersion == 2
          ? (services.backendConfigurationStore.mode == .hosted ? "App Attest" : "Secure Enclave P-256")
          : nil,
        refreshCredentialExpiresAt: services.authService.session?.refreshTokenExpiresAt,
        refreshCredentialAbsoluteExpiresAt: services.authService.session?.refreshTokenAbsoluteExpiresAt
      ),
      generatedAt: generatedAt
    )
  }

  private static func diagnosticLines(_ entries: [DiagnosticEntry]) -> String {
    guard !entries.isEmpty else {
      return "No app diagnostics recorded."
    }

    return entries
      .prefix(50)
      .map { entry in
        [
          "- \(format(entry.timestamp))",
          entry.source.rawValue,
          entry.severity.rawValue,
          entry.title,
          entry.message ?? ""
        ]
        .filter { !$0.isEmpty }
        .map(redacted)
        .joined(separator: " | ")
      }
      .joined(separator: "\n")
  }

  private static func nativeDiagnosticLines(_ entries: [NativeDiagnosticEntry]) -> String {
    guard !entries.isEmpty else {
      return "No native diagnostics recorded."
    }

    return entries
      .prefix(50)
      .map { entry in
        [
          "- \(format(entry.timestamp))",
          entry.kind.rawValue,
          entry.title,
          "App \(entry.appVersion) (\(entry.buildNumber))",
          entry.summary.replacingOccurrences(of: "\n", with: " ; ")
        ]
        .map(redacted)
        .joined(separator: " | ")
      }
      .joined(separator: "\n")
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
