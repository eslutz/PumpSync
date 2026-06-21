import XCTest
@testable import PumpSync

final class SupportBundleBuilderTests: XCTestCase {
  func testSupportBundleIncludesExpectedMetadataAndRedactsSensitiveValues() {
    let context = SupportBundleContext(
      bundleInfo: AppBundleInfo(bundleIdentifier: "dev.ericslutz.PumpSync", version: "1.0", build: "42"),
      systemVersion: "26.0",
      deviceModel: "iPhone",
      backendMode: "PumpSync",
      connectionHost: "api.example.com",
      syncMetadata: SyncMetadata(
        lastAttemptAt: Date(timeIntervalSince1970: 10),
        lastSuccessfulSyncAt: Date(timeIntervalSince1970: 20),
        lastSampleCount: 12,
        lastImportedCount: 10,
        lastErrorMessage: "Failure for user@example.com with Bearer eyJhbGciOi.fake-token-value-1234567890.",
        initialImportRange: .pastWeek
      ),
      appDiagnostics: [
        DiagnosticEntry(
          timestamp: Date(timeIntervalSince1970: 30),
          source: .sync,
          severity: .error,
          title: "Sync failed",
          message: "JWS eyJaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbb.cccccccccccccccccccc"
        )
      ],
      nativeDiagnostics: [
        NativeDiagnosticEntry(
          timestamp: Date(timeIntervalSince1970: 40),
          kind: .performance,
          title: "Performance metrics",
          summary: "cumulativeHangTime: 0 ms",
          appVersion: "1.0",
          buildNumber: "42"
        )
      ]
    )

    let bundle = SupportBundleBuilder.build(context: context, generatedAt: Date(timeIntervalSince1970: 50))

    XCTAssertTrue(bundle.contains("App Version: 1.0 (42)"))
    XCTAssertTrue(bundle.contains("Bundle Identifier: dev.ericslutz.PumpSync"))
    XCTAssertTrue(bundle.contains("Connection Host: api.example.com"))
    XCTAssertTrue(bundle.contains("Last Returned Count: 12"))
    XCTAssertTrue(bundle.contains("Performance metrics"))
    XCTAssertFalse(bundle.contains("user@example.com"))
    XCTAssertFalse(bundle.contains("fake-token-value"))
    XCTAssertFalse(bundle.contains("eyJaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
    XCTAssertTrue(bundle.contains("[redacted email]"))
    XCTAssertTrue(bundle.contains("[redacted token]"))
  }
}
