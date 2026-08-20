import XCTest
@testable import PumpSync

@MainActor
final class DeviceSessionProofProviderTests: XCTestCase {
  func testRefreshPayloadMatchesProtocol3Vector() {
    let payload = DeviceProofPayload.refresh(
      installationId: "installation-1",
      requestId: "request-1",
      issuedAt: Date(timeIntervalSince1970: 1_786_795_200),
      refreshToken: "refresh-token",
      keyId: "key-1"
    )

    XCTAssertEqual(
      payload.encoded.base64EncodedString(),
      "AAAAGVB1bXBTeW5jLkRldmljZVNlc3Npb24udjMAAAAHcmVmcmVzaAAAABcvYXBpL3YxL3Nlc3Npb24vcmVmcmVzaAAAAA5pbnN0YWxsYXRpb24tMQAAAAlyZXF1ZXN0LTEAAAAKMTc4Njc5NTIwMAAAACAOsXZD1OkmEWN4OkIIWcksfSEvqWJBBqErUQr77CZhIAAAAAVrZXktMQ=="
    )
  }

  func testHostedEnrollmentPayloadMatchesProtocol3Vector() {
    let payload = DeviceProofPayload.hostedEnrollment(
      installationId: "installation-1",
      requestId: "request-1",
      issuedAt: Date(timeIntervalSince1970: 1_786_795_200),
      challengeToken: "challenge-token",
      keyId: "key-1",
      signedTransactionInfo: "signed-transaction"
    )

    XCTAssertEqual(
      payload.encoded.base64EncodedString(),
      "AAAAGVB1bXBTeW5jLkRldmljZVNlc3Npb24udjMAAAAGZW5yb2xsAAAAHC9hcGkvdjEvc3Vic2NyaXB0aW9uL3Nlc3Npb24AAAAOaW5zdGFsbGF0aW9uLTEAAAAJcmVxdWVzdC0xAAAACjE3ODY3OTUyMDAAAAAgb85YyKrMO8G2InGlv3NTwTfdwWb1UhKkQSj7nK68dXUAAAAFa2V5LTEAAAAglKdP/T9InyAIoLNmJnuH2HPJhk6Iwo/9Zs8gDoUNnIc="
    )
  }

  func testServerUnavailableRetriesAttestationWithSameKey() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [
      .failure(AppAttestClientError.serverUnavailable),
      .success(Data("attestation".utf8))
    ]

    do {
      _ = try await fixture.provider.hostedEnrollment(
        challenge: challenge("challenge-1"), installationId: "installation-1",
        signedTransactionInfo: "transaction", existingSession: nil
      )
      XCTFail("Expected server unavailable")
    } catch AppAttestClientError.serverUnavailable {}

    let enrollment = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction", existingSession: nil
    )
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
    XCTAssertEqual(fixture.client.attestedKeyIds, ["key-1", "key-1"])
    XCTAssertEqual(enrollment.proofKind, "attestation")
  }

  func testRegisteredKeyIsReusedWithoutCachedSession() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("attestation".utf8))]
    let first = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction", existingSession: nil
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentRegistered(
      keyId: first.keyId,
      requestId: first.requestId
    ))
    fixture.client.assertionResults = [.success(Data("assertion".utf8))]

    let recovered = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction", existingSession: nil
    )
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
    XCTAssertEqual(recovered.proofKind, "assertion")
    XCTAssertEqual(recovered.keyId, first.keyId)
  }

  func testPendingEnrollmentDoesNotReplaceANewChallenge() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [
      .success(Data("attestation-1".utf8)),
      .success(Data("attestation-2".utf8))
    ]

    let first = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction", existingSession: nil
    )
    let second = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction", existingSession: nil
    )

    XCTAssertEqual(first.challengeToken, "challenge-1")
    XCTAssertEqual(second.challengeToken, "challenge-2")
    XCTAssertNotEqual(second.keyId, first.keyId)
    XCTAssertEqual(fixture.client.generatedKeyCount, 2)
  }

  func testPendingEnrollmentForSameChallengeReportsProofReuse() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("attestation".utf8))]
    let challenge = challenge("challenge-1")

    let generated = try await fixture.provider.hostedEnrollment(
      challenge: challenge, installationId: "installation-1",
      signedTransactionInfo: "transaction", existingSession: nil
    )
    let reused = try await fixture.provider.hostedEnrollment(
      challenge: challenge, installationId: "installation-1",
      signedTransactionInfo: "transaction", existingSession: nil
    )

    XCTAssertEqual(generated.preparation, .generated)
    XCTAssertEqual(reused.preparation, .reused)
    XCTAssertEqual(reused.keyId, generated.keyId)
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
  }

  func testSupersededAttestationCannotOverwriteOrDiscardReplacementEnrollment() async throws {
    let fixture = makeFixture()
    let staleGate = ProofAsyncGate()
    let replacementGate = ProofAsyncGate()
    fixture.client.attestationResults = [
      .success(Data("stale-attestation".utf8)),
      .success(Data("replacement-attestation".utf8)),
      .success(Data("unexpected-attestation".utf8))
    ]
    fixture.client.attestationGates = [staleGate, replacementGate]

    let staleAttempt = Task { () -> Result<HostedDeviceEnrollment, Error> in
      do {
        return .success(try await fixture.provider.hostedEnrollment(
          challenge: challenge("challenge-1"), installationId: "installation-1",
          signedTransactionInfo: "stale-transaction", existingSession: nil
        ))
      } catch {
        return .failure(error)
      }
    }
    await waitUntil { fixture.client.attestedKeyIds.count == 1 }

    let replacementAttempt = Task {
      try await fixture.provider.hostedEnrollment(
        challenge: challenge("challenge-2"), installationId: "installation-1",
        signedTransactionInfo: "replacement-transaction", existingSession: nil
      )
    }
    await waitUntil { fixture.client.attestedKeyIds.count == 2 }
    await replacementGate.open()
    let replacement = try await replacementAttempt.value
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentRegistered(
      keyId: replacement.keyId,
      requestId: replacement.requestId
    ))

    await staleGate.open()
    let staleResult = await staleAttempt.value
    if case let .success(staleEnrollment) = staleResult {
      _ = try fixture.provider.discardUnsubmittedHostedEnrollment(
        keyId: staleEnrollment.keyId,
        requestId: staleEnrollment.requestId
      )
    }

    fixture.client.assertionResults = [.success(Data("assertion".utf8))]
    let recovered = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-3"), installationId: "installation-1",
      signedTransactionInfo: "replacement-transaction", existingSession: nil
    )

    XCTAssertEqual(replacement.keyId, "key-2")
    if case .success = staleResult {
      XCTFail("Expected the stale enrollment preparation to be superseded")
    }
    XCTAssertEqual(recovered.proofKind, "assertion")
    XCTAssertEqual(recovered.keyId, replacement.keyId)
    XCTAssertEqual(fixture.client.generatedKeyCount, 2)
    XCTAssertEqual(fixture.client.attestedKeyIds, ["key-1", "key-2"])
  }

  func testSubmittedEnrollmentBlocksReplacementUntilItsBackendOutcomeIsRegistered() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("attestation".utf8))]
    let submitted = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "submitted-transaction", existingSession: nil
    )

    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: submitted.keyId,
      requestId: submitted.requestId
    ))

    do {
      _ = try await fixture.provider.hostedEnrollment(
        challenge: challenge("challenge-2"), installationId: "installation-1",
        signedTransactionInfo: "replacement-transaction", existingSession: nil
      )
      XCTFail("Expected a submitted enrollment to remain authoritative")
    } catch DeviceSessionProofError.enrollmentOutcomeAmbiguous {
      // Expected: the backend outcome owns this enrollment until reconciled.
    }
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)

    XCTAssertTrue(try fixture.provider.markHostedEnrollmentRegistered(
      keyId: submitted.keyId,
      requestId: submitted.requestId
    ))
    fixture.client.assertionResults = [.success(Data("assertion".utf8))]
    let recovered = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-3"), installationId: "installation-1",
      signedTransactionInfo: "submitted-transaction", existingSession: nil
    )
    XCTAssertEqual(recovered.proofKind, "assertion")
    XCTAssertEqual(recovered.keyId, submitted.keyId)
  }

  func testLegacyPendingEnrollmentWithoutSubmissionMarkerIsConservativelyAmbiguous() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [
      .success(Data("attestation-1".utf8)),
      .success(Data("attestation-2".utf8))
    ]
    _ = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "legacy-transaction", existingSession: nil
    )

    let account = "device-proof.app-attest-state.v3"
    let encodedState = try XCTUnwrap(try fixture.keychain.readData(account: account))
    var legacyState = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encodedState) as? [String: Any]
    )
    var pendingEnrollment = try XCTUnwrap(
      legacyState["pendingEnrollment"] as? [String: Any]
    )
    pendingEnrollment.removeValue(forKey: "backendSubmissionStarted")
    legacyState["pendingEnrollment"] = pendingEnrollment
    try fixture.keychain.writeData(
      JSONSerialization.data(withJSONObject: legacyState),
      account: account
    )

    let recreated = DeviceSessionProofProvider(
      keychain: fixture.keychain,
      now: { Date(timeIntervalSince1970: 1_786_795_200) },
      appAttest: fixture.client
    )
    do {
      _ = try await recreated.hostedEnrollment(
        challenge: challenge("challenge-2"), installationId: "installation-1",
        signedTransactionInfo: "replacement-transaction", existingSession: nil
      )
      XCTFail("Expected a legacy pending enrollment to require reconciliation")
    } catch DeviceSessionProofError.enrollmentOutcomeAmbiguous {
      // Expected: a missing marker cannot prove that the enrollment was unsubmitted.
    }
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
  }

  func testDefinitivelyFailedSubmittedEnrollmentCanBeRetried() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [
      .success(Data("attestation-1".utf8)),
      .success(Data("attestation-2".utf8))
    ]
    let failed = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "failed-transaction", existingSession: nil
    )

    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: failed.keyId,
      requestId: failed.requestId
    ))
    XCTAssertTrue(try fixture.provider.discardDefinitivelyFailedHostedEnrollment(
      keyId: failed.keyId,
      requestId: failed.requestId
    ))

    let retried = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "retried-transaction", existingSession: nil
    )
    XCTAssertEqual(retried.keyId, "key-2")
    XCTAssertEqual(fixture.client.generatedKeyCount, 2)
  }

  func testInvalidAssertionKeyIsDiscarded() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [
      .success(Data("attestation-1".utf8)),
      .success(Data("attestation-2".utf8))
    ]
    let first = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction", existingSession: nil
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentRegistered(
      keyId: first.keyId,
      requestId: first.requestId
    ))
    fixture.client.assertionResults = [.failure(AppAttestClientError.invalidKey)]
    do {
      _ = try await fixture.provider.hostedEnrollment(
        challenge: challenge("challenge-2"), installationId: "installation-1",
        signedTransactionInfo: "transaction", existingSession: nil
      )
      XCTFail("Expected invalid key")
    } catch AppAttestClientError.invalidKey {}

    let replacement = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-3"), installationId: "installation-1",
      signedTransactionInfo: "transaction", existingSession: nil
    )
    XCTAssertEqual(replacement.keyId, "key-2")
  }

  func testAmbiguousPendingEnrollmentSurvivesProviderRecreation() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("attestation".utf8))]
    let first = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction", existingSession: nil
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentResponseAmbiguous(
      keyId: first.keyId,
      requestId: first.requestId
    ))
    let recreated = DeviceSessionProofProvider(keychain: fixture.keychain, appAttest: fixture.client)

    do {
      _ = try await recreated.hostedEnrollment(
        challenge: challenge("challenge-2"), installationId: "installation-1",
        signedTransactionInfo: "transaction", existingSession: nil
      )
      XCTFail("Expected an ambiguous enrollment to require reconciliation")
    } catch DeviceSessionProofError.enrollmentOutcomeAmbiguous {
      // Expected: do not automatically replay a non-idempotent enrollment.
    }
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
  }

  private func makeFixture() -> (provider: DeviceSessionProofProvider, client: FakeAppAttestClient, keychain: SecureKeychainStore) {
    let client = FakeAppAttestClient()
    let keychain = SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.appattest.\(UUID().uuidString)")
    return (
      DeviceSessionProofProvider(
        keychain: keychain,
        now: { Date(timeIntervalSince1970: 1_786_795_200) },
        appAttest: client
      ),
      client,
      keychain
    )
  }

  private func challenge(_ token: String) -> SessionChallengeResponse {
    SessionChallengeResponse(protocolVersion: 3, proofKind: "appAttest", challengeToken: token, expiresAt: .distantFuture)
  }

  private func waitUntil(
    timeout: TimeInterval = 2,
    condition: @escaping @MainActor () -> Bool
  ) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
      await Task.yield()
    }
    XCTAssertTrue(condition(), "condition was not met before timeout")
  }
}

private actor ProofAsyncGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func open() {
    isOpen = true
    let pending = waiters
    waiters.removeAll()
    pending.forEach { $0.resume() }
  }
}

@MainActor
private final class FakeAppAttestClient: AppAttestClient {
  var isSupported = true
  var generatedKeyCount = 0
  var attestedKeyIds: [String] = []
  var attestationResults: [Result<Data, Error>] = []
  var attestationGates: [ProofAsyncGate] = []
  var assertionResults: [Result<Data, Error>] = []

  func generateKey() async throws -> String {
    generatedKeyCount += 1
    return "key-\(generatedKeyCount)"
  }

  func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
    attestedKeyIds.append(keyId)
    let result = attestationResults.removeFirst()
    if !attestationGates.isEmpty {
      await attestationGates.removeFirst().wait()
    }
    return try result.get()
  }

  func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
    try assertionResults.removeFirst().get()
  }
}
