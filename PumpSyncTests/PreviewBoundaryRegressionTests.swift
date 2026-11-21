import XCTest
@testable import PumpSync

@MainActor
final class PreviewBoundaryRegressionTests: XCTestCase {
  func testInspectionUsesOnlyCurrentAccountCursorAndLeavesHistoryUntouched() async throws {
    let keychain = SecureKeychainStore(service: "Preview.\(UUID())")
    defer { try? keychain.deleteAll() }
    let credentials = TandemCredentialStore(keychain: keychain)
    try credentials.saveValidated(.init(username: "fixture", password: "fixture", region: "us"))
    let account = try XCTUnwrap(credentials.accountId)
    let defaults = UserDefaults(suiteName: "Preview.\(UUID())")!
    let metadata = SyncMetadataStore(defaults: defaults)
    let cursor = Date().addingTimeInterval(-600)
    let source = DirectImportTestSource(.success(.init(samples: [], effectiveMinDate: cursor, effectiveMaxDate: Date(), dataSourceMode: .tandemSource)))
    let preview = RealImportPreviewSession(dataSource: source, credentialStore: credentials, metadataStore: metadata, concentrationStore: .init(defaults: defaults))
    for sameAccount in [false, true] {
      metadata.recordSuccess(sampleCount: 1, importedCount: 1, completedAt: Date(), watermark: cursor, owner: .init(accountId: sameAccount ? account : UUID()))
      let before = metadata.metadata
      await preview.load()
      let lastRequest = await source.requests.last
      XCTAssertEqual(lastRequest?.minDate, sameAccount ? cursor : before.initialImportRange.minimumDate(relativeTo: Date()))
      XCTAssertEqual(metadata.metadata, before)
      guard case .ready = preview.controller.state else { return XCTFail("Expected read-only inspection") }
    }
    try credentials.delete()
    preview.controller.validateSnapshot()
    guard case .failed = preview.controller.state else { return XCTFail("Removed account retained its snapshot") }
  }

  func testStaleCompletionCannotRepublishClosedPreview() async throws {
    let context = ImportSessionSnapshot(accountId: UUID(), credentialRevision: 1)
    let source = DirectImportTestSource(.success(.init(samples: [], effectiveMinDate: Date(), effectiveMaxDate: Date(), dataSourceMode: .tandemSource)), held: true)
    let controller = ImportPreviewController(dataSource: source, currentContext: { context })
    let request = TandemSyncRequest(tandem: .init(username: "fixture", password: "fixture", region: "us"), minDate: nil, maxDate: nil, timeZoneIdentifier: "UTC")
    let task = Task { await controller.load(request: request, context: context, concentration: .u100) }
    for _ in 0..<500 {
      if await source.callCount > 0 { break }
      try await Task.sleep(for: .milliseconds(2))
    }
    let calls = await source.callCount
    XCTAssertEqual(calls, 1)
    controller.cancel()
    await source.release()
    await task.value
    guard case .idle = controller.state else { return XCTFail("A late response restored a canceled preview") }
  }
}
