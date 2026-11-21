import Foundation
@testable import PumpSync

/// Deterministic provider boundary. Tests can change accounts or expire a task
/// while the provider holds its result and then deliver that result anyway.
actor DirectImportTestSource: TandemDataSource {
  private(set) var requests: [TandemSyncRequest] = []
  private var result: Result<TandemSyncResponse, DirectTandemError>
  private var held: Bool
  private var waiters: [CheckedContinuation<Void, Never>] = []
  var callCount: Int { requests.count }

  init(_ result: Result<TandemSyncResponse, DirectTandemError>, held: Bool = false) {
    self.result = result
    self.held = held
  }

  func load(_ request: TandemSyncRequest) async throws -> TandemSyncResponse {
    requests.append(request)
    if held { await withCheckedContinuation { waiters.append($0) } }
    return try result.get()
  }

  func setResult(_ result: Result<TandemSyncResponse, DirectTandemError>) {
    self.result = result
  }

  func release() {
    held = false
    for waiter in waiters { waiter.resume() }
    waiters.removeAll()
  }
}
