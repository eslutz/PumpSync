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
        signedTransactionInfo: "transaction"
      )
      XCTFail("Expected server unavailable")
    } catch AppAttestClientError.serverUnavailable {}

    let enrollment = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
    XCTAssertEqual(fixture.client.attestedKeyIds, ["key-1", "key-1"])
    XCTAssertEqual(enrollment.proofKind, "attestation")
  }

  func testCurrentProviderIgnoresAndPreservesObsoleteAppAttestState() async throws {
    let fixture = makeFixture()
    let obsoleteAccount = ["device-proof", "app-attest-state", "v3"].joined(separator: ".")
    let obsoleteState = Data(#"{"keyId":"obsolete-key","phase":"registered","pendingEnrollment":null}"#.utf8)
    try fixture.keychain.writeData(obsoleteState, account: obsoleteAccount)
    fixture.client.attestationResults = [.success(Data("fresh-attestation".utf8))]

    let enrollment = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )

    XCTAssertEqual(enrollment.proofKind, "attestation")
    XCTAssertEqual(enrollment.keyId, "key-1")
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
    XCTAssertEqual(try fixture.keychain.readData(account: obsoleteAccount), obsoleteState)
  }

  func testRegisteredKeyIsReusedWithoutCachedSession() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("attestation".utf8))]
    let first = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: first.keyId,
      requestId: first.requestId
    ))
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentRegistered(
      keyId: first.keyId,
      requestId: first.requestId
    ))
    fixture.client.assertionResults = [.success(Data("assertion".utf8))]

    let recovered = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
    XCTAssertEqual(recovered.proofKind, "assertion")
    XCTAssertEqual(recovered.keyId, first.keyId)
  }

  func testDiscardRegisteredKeyForcesFreshAttestation() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [
      .success(Data("initial-attestation".utf8)),
      .success(Data("replacement-attestation".utf8))
    ]
    let initial = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentRegistered(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))

    XCTAssertTrue(try fixture.provider.discardRegisteredHostedKey())
    let replacement = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )

    XCTAssertEqual(replacement.proofKind, "attestation")
    XCTAssertNotEqual(replacement.keyId, initial.keyId)
    XCTAssertEqual(fixture.client.generatedKeyCount, 2)
  }

  func testRejectedSubmittedAssertionRestoresRegisteredKeyForFreshAssertion() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("initial-attestation".utf8))]
    let initial = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentRegistered(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))

    fixture.client.assertionResults = [
      .success(Data("rejected-assertion".utf8)),
      .success(Data("replacement-assertion".utf8))
    ]
    let rejected = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: rejected.keyId,
      requestId: rejected.requestId
    ))
    let discarded = try fixture.provider.resolveRejectedHostedEnrollment(
      keyId: rejected.keyId,
      requestId: rejected.requestId
    )
    XCTAssertTrue(discarded)
    guard discarded else { return }

    let replacement = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-3"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertEqual(replacement.proofKind, "assertion")
    XCTAssertEqual(replacement.keyId, initial.keyId)
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
  }

  func testEnrollmentRequiredForSubmittedAssertionClearsKeyForFreshAttestation() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [
      .success(Data("initial-attestation".utf8)),
      .success(Data("replacement-attestation".utf8))
    ]
    let initial = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentRegistered(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))

    fixture.client.assertionResults = [.success(Data("rejected-assertion".utf8))]
    let rejected = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: rejected.keyId,
      requestId: rejected.requestId
    ))
    XCTAssertTrue(try fixture.provider.discardDefinitivelyFailedHostedEnrollment(
      keyId: rejected.keyId,
      requestId: rejected.requestId
    ))

    let replacement = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-3"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertEqual(replacement.proofKind, "attestation")
    XCTAssertNotEqual(replacement.keyId, initial.keyId)
    XCTAssertEqual(fixture.client.generatedKeyCount, 2)
  }

  func testDiscardingUnsubmittedAssertionRestoresRegisteredKey() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("attestation".utf8))]
    let initial = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentRegistered(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))

    fixture.client.assertionResults = [
      .success(Data("unsubmitted-assertion".utf8)),
      .success(Data("next-assertion".utf8))
    ]
    let unsubmitted = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )

    XCTAssertTrue(try fixture.provider.discardUnsubmittedHostedEnrollment(
      keyId: unsubmitted.keyId,
      requestId: unsubmitted.requestId
    ))
    let next = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-3"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertEqual(next.proofKind, "assertion")
    XCTAssertEqual(next.keyId, initial.keyId)
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
  }

  func testRecreatedProviderReusesOnlyExactPreparedRegisteredAssertion() async throws {
    let fixture = try await registeredFixture()
    fixture.client.assertionResults = [.success(Data("prepared-assertion".utf8))]
    let challenge = challenge("challenge-2")
    let prepared = try await fixture.provider.hostedEnrollment(
      challenge: challenge, installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    let recreated = DeviceSessionProofProvider(
      keychain: fixture.keychain,
      now: { Date(timeIntervalSince1970: 1_786_795_200) },
      appAttest: fixture.client
    )

    let reused = try await recreated.hostedEnrollment(
      challenge: challenge, installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )

    XCTAssertEqual(reused.requestId, prepared.requestId)
    XCTAssertEqual(reused.proof, prepared.proof)
    XCTAssertEqual(reused.keyId, prepared.keyId)
    XCTAssertEqual(reused.preparation, .reused)
    XCTAssertTrue(fixture.client.assertionResults.isEmpty)
  }

  func testRecreatedProviderDoesNotReplaySubmittedRegisteredAssertion() async throws {
    let fixture = try await registeredFixture()
    fixture.client.assertionResults = [
      .success(Data("submitted-assertion".utf8)),
      .success(Data("fresh-assertion".utf8))
    ]
    let challenge = challenge("challenge-2")
    let submitted = try await fixture.provider.hostedEnrollment(
      challenge: challenge, installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: submitted.keyId,
      requestId: submitted.requestId
    ))
    let recreated = DeviceSessionProofProvider(
      keychain: fixture.keychain,
      now: { Date(timeIntervalSince1970: 1_786_795_200) },
      appAttest: fixture.client
    )

    let fresh = try await recreated.hostedEnrollment(
      challenge: challenge, installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )

    XCTAssertEqual(fresh.proofKind, "assertion")
    XCTAssertEqual(fresh.keyId, submitted.keyId)
    XCTAssertNotEqual(fresh.requestId, submitted.requestId)
    XCTAssertNotEqual(fresh.proof, submitted.proof)
    XCTAssertEqual(fresh.preparation, .generated)
    XCTAssertTrue(fixture.client.assertionResults.isEmpty)
  }

  func testPendingEnrollmentDoesNotReplaceANewChallenge() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [
      .success(Data("attestation-1".utf8)),
      .success(Data("attestation-2".utf8))
    ]

    let first = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    let recreated = DeviceSessionProofProvider(
      keychain: fixture.keychain,
      now: { Date(timeIntervalSince1970: 1_786_795_200) },
      appAttest: fixture.client
    )
    let second = try await recreated.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
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
      signedTransactionInfo: "transaction"
    )
    let recreated = DeviceSessionProofProvider(
      keychain: fixture.keychain,
      now: { Date(timeIntervalSince1970: 1_786_795_200) },
      appAttest: fixture.client
    )
    let reused = try await recreated.hostedEnrollment(
      challenge: challenge, installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )

    XCTAssertEqual(generated.preparation, .generated)
    XCTAssertEqual(reused.preparation, .reused)
    XCTAssertEqual(reused.keyId, generated.keyId)
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
  }

  func testInFlightAttestationBlocksConcurrentEnrollment() async throws {
    let fixture = makeFixture()
    let attestationGate = ProofAsyncGate()
    fixture.client.attestationResults = [.success(Data("attestation".utf8))]
    fixture.client.attestationGates = [attestationGate]

    let firstAttempt = Task {
      try await fixture.provider.hostedEnrollment(
        challenge: challenge("challenge-1"), installationId: "installation-1",
        signedTransactionInfo: "transaction"
      )
    }
    await waitUntil { fixture.client.attestedKeyIds.count == 1 }

    do {
      _ = try await fixture.provider.hostedEnrollment(
        challenge: challenge("challenge-2"), installationId: "installation-1",
        signedTransactionInfo: "transaction"
      )
      XCTFail("Expected the in-flight attestation to block another enrollment proof")
    } catch DeviceSessionProofError.hostedProofOperationInProgress {
    }
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
    XCTAssertEqual(fixture.client.attestedKeyIds, ["key-1"])

    await attestationGate.open()
    let enrollment = try await firstAttempt.value
    XCTAssertEqual(enrollment.keyId, "key-1")
    XCTAssertEqual(enrollment.proofKind, "attestation")
  }

  func testSubmittedEnrollmentReconcilesWithFreshAssertionAfterProviderRecreation() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("attestation".utf8))]
    let submitted = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "submitted-transaction"
    )

    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: submitted.keyId,
      requestId: submitted.requestId
    ))

    let recreated = DeviceSessionProofProvider(
      keychain: fixture.keychain,
      now: { Date(timeIntervalSince1970: 1_786_795_200) },
      appAttest: fixture.client
    )
    fixture.client.assertionResults = [.success(Data("assertion".utf8))]
    let reconciliation = try await recreated.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "submitted-transaction"
    )

    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
    XCTAssertEqual(reconciliation.proofKind, "assertion")
    XCTAssertEqual(reconciliation.preparation, .reconciliation)
    XCTAssertEqual(reconciliation.keyId, submitted.keyId)
    XCTAssertTrue(try recreated.markHostedEnrollmentSubmissionStarted(
      keyId: reconciliation.keyId,
      requestId: reconciliation.requestId
    ))
    XCTAssertTrue(try recreated.markHostedEnrollmentRegistered(
      keyId: reconciliation.keyId,
      requestId: reconciliation.requestId
    ))

    fixture.client.assertionResults = [.success(Data("registered-assertion".utf8))]
    let recovered = try await recreated.hostedEnrollment(
      challenge: challenge("challenge-3"), installationId: "installation-1",
      signedTransactionInfo: "submitted-transaction"
    )
    XCTAssertEqual(recovered.proofKind, "assertion")
    XCTAssertEqual(recovered.keyId, submitted.keyId)
  }

  func testSubmittedEnrollmentCannotBeDiscardedAsUnsubmitted() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("attestation".utf8))]
    let submitted = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "submitted-transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: submitted.keyId,
      requestId: submitted.requestId
    ))

    XCTAssertFalse(try fixture.provider.discardUnsubmittedHostedEnrollment(
      keyId: submitted.keyId,
      requestId: submitted.requestId
    ))
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
  }

  func testRejectedReconciliationRestoresRegisteredKeyForFreshAssertion() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("attestation-1".utf8))]
    let submitted = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: submitted.keyId,
      requestId: submitted.requestId
    ))
    XCTAssertTrue(fixture.provider.releaseHostedProofOperation(requestId: submitted.requestId))

    fixture.client.assertionResults = [
      .success(Data("rejected-reconciliation".utf8)),
      .success(Data("replacement-assertion".utf8))
    ]
    let reconciliation = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: reconciliation.keyId,
      requestId: reconciliation.requestId
    ))
    XCTAssertTrue(try fixture.provider.resolveRejectedHostedEnrollment(
      keyId: reconciliation.keyId,
      requestId: reconciliation.requestId
    ))

    let replacement = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-3"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertEqual(replacement.proofKind, "assertion")
    XCTAssertEqual(replacement.keyId, submitted.keyId)
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
  }

  func testPreparedRegisteredAssertionCannotCreateRefreshProof() async throws {
    let fixture = try await registeredFixture()
    fixture.client.assertionResults = [
      .success(Data("prepared-session-assertion".utf8)),
      .success(Data("unexpected-refresh-assertion".utf8))
    ]
    _ = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    let recreated = DeviceSessionProofProvider(keychain: fixture.keychain, appAttest: fixture.client)

    do {
      _ = try await recreated.refreshRequest(
        session: renewableSession(), installationId: "installation-1", mode: .hosted
      )
      XCTFail("Expected a prepared enrollment assertion to block refresh proof generation")
    } catch DeviceSessionProofError.appAttestUnavailable {}
    XCTAssertEqual(fixture.client.assertionResults.count, 1)
  }

  func testSubmittedRegisteredAssertionCannotCreateRefreshProof() async throws {
    let fixture = try await registeredFixture()
    fixture.client.assertionResults = [
      .success(Data("submitted-session-assertion".utf8)),
      .success(Data("unexpected-refresh-assertion".utf8))
    ]
    let submitted = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: submitted.keyId,
      requestId: submitted.requestId
    ))
    let recreated = DeviceSessionProofProvider(keychain: fixture.keychain, appAttest: fixture.client)

    do {
      _ = try await recreated.refreshRequest(
        session: renewableSession(), installationId: "installation-1", mode: .hosted
      )
      XCTFail("Expected a submitted enrollment assertion to block refresh proof generation")
    } catch DeviceSessionProofError.appAttestUnavailable {}
    XCTAssertEqual(fixture.client.assertionResults.count, 1)
  }

  func testGeneratingRegisteredAssertionCannotCreateConcurrentRefreshProof() async throws {
    let fixture = try await registeredFixture()
    let assertionGate = ProofAsyncGate()
    fixture.client.assertionResults = [
      .success(Data("session-assertion".utf8)),
      .success(Data("unexpected-refresh-assertion".utf8))
    ]
    fixture.client.assertionGates = [assertionGate]
    let enrollmentTask = Task {
      try await fixture.provider.hostedEnrollment(
        challenge: challenge("challenge-2"), installationId: "installation-1",
        signedTransactionInfo: "transaction"
      )
    }
    await waitUntil { fixture.client.assertedKeyIds.count == 1 }

    do {
      _ = try await fixture.provider.refreshRequest(
        session: renewableSession(), installationId: "installation-1", mode: .hosted
      )
      XCTFail("Expected in-flight enrollment assertion generation to block refresh proof generation")
    } catch DeviceSessionProofError.hostedProofOperationInProgress {}
    XCTAssertEqual(fixture.client.assertionResults.count, 1)

    await assertionGate.open()
    _ = try await enrollmentTask.value
  }

  func testPreparedRefreshBlocksEnrollmentUntilExactRequestIsReleased() async throws {
    let fixture = try await registeredFixture()
    fixture.client.assertionResults = [
      .success(Data("refresh-assertion".utf8)),
      .success(Data("enrollment-assertion".utf8))
    ]
    let refresh = try await fixture.provider.refreshRequest(
      session: renewableSession(), installationId: "installation-1", mode: .hosted
    )

    do {
      _ = try await fixture.provider.hostedEnrollment(
        challenge: challenge("challenge-2"), installationId: "installation-1",
        signedTransactionInfo: "transaction"
      )
      XCTFail("Expected the prepared refresh proof to block enrollment proof generation")
    } catch DeviceSessionProofError.hostedProofOperationInProgress {}
    XCTAssertFalse(fixture.provider.releaseHostedProofOperation(requestId: "different-request"))
    XCTAssertTrue(fixture.provider.releaseHostedProofOperation(requestId: refresh.requestId))

    let enrollment = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertEqual(enrollment.proofKind, "assertion")
    XCTAssertEqual(enrollment.keyId, "key-1")
    XCTAssertTrue(fixture.client.assertionResults.isEmpty)
  }

  func testPreparedRefreshBlocksSecondRefreshUntilReleased() async throws {
    let fixture = try await registeredFixture()
    fixture.client.assertionResults = [
      .success(Data("first-refresh-assertion".utf8)),
      .success(Data("second-refresh-assertion".utf8))
    ]
    let first = try await fixture.provider.refreshRequest(
      session: renewableSession(), installationId: "installation-1", mode: .hosted
    )

    do {
      _ = try await fixture.provider.refreshRequest(
        session: renewableSession(), installationId: "installation-1", mode: .hosted
      )
      XCTFail("Expected the prepared refresh proof to block another refresh proof")
    } catch DeviceSessionProofError.hostedProofOperationInProgress {}
    XCTAssertTrue(fixture.provider.releaseHostedProofOperation(requestId: first.requestId))

    let second = try await fixture.provider.refreshRequest(
      session: renewableSession(), installationId: "installation-1", mode: .hosted
    )
    XCTAssertNotEqual(second.requestId, first.requestId)
    XCTAssertTrue(fixture.client.assertionResults.isEmpty)
  }

  func testHostedProofLeaseIsNotPersistedAcrossProviderRecreation() async throws {
    let fixture = try await registeredFixture()
    fixture.client.assertionResults = [
      .success(Data("refresh-assertion".utf8)),
      .success(Data("enrollment-assertion".utf8))
    ]
    _ = try await fixture.provider.refreshRequest(
      session: renewableSession(), installationId: "installation-1", mode: .hosted
    )
    let recreated = DeviceSessionProofProvider(keychain: fixture.keychain, appAttest: fixture.client)

    let enrollment = try await recreated.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )

    XCTAssertEqual(enrollment.proofKind, "assertion")
    XCTAssertEqual(enrollment.keyId, "key-1")
    XCTAssertTrue(fixture.client.assertionResults.isEmpty)
  }

  func testPreparedAttestationCannotCreateRefreshProof() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("prepared-attestation".utf8))]
    fixture.client.assertionResults = [.success(Data("unexpected-refresh-assertion".utf8))]
    _ = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    let recreated = DeviceSessionProofProvider(keychain: fixture.keychain, appAttest: fixture.client)

    do {
      _ = try await recreated.refreshRequest(
        session: renewableSession(), installationId: "installation-1", mode: .hosted
      )
      XCTFail("Expected a prepared attestation to block refresh proof generation")
    } catch DeviceSessionProofError.appAttestUnavailable {}
    XCTAssertEqual(fixture.client.assertionResults.count, 1)
  }

  func testRegistrationUnknownCannotCreateRefreshProof() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("submitted-attestation".utf8))]
    fixture.client.assertionResults = [.success(Data("unexpected-refresh-assertion".utf8))]
    let submitted = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: submitted.keyId,
      requestId: submitted.requestId
    ))
    let recreated = DeviceSessionProofProvider(keychain: fixture.keychain, appAttest: fixture.client)

    do {
      _ = try await recreated.refreshRequest(
        session: renewableSession(), installationId: "installation-1", mode: .hosted
      )
      XCTFail("Expected unknown registration state to block refresh proof generation")
    } catch DeviceSessionProofError.appAttestUnavailable {}
    XCTAssertEqual(fixture.client.assertionResults.count, 1)
  }

  func testPreparedReconciliationCannotCreateRefreshProof() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("submitted-attestation".utf8))]
    let submitted = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: submitted.keyId,
      requestId: submitted.requestId
    ))
    XCTAssertTrue(fixture.provider.releaseHostedProofOperation(requestId: submitted.requestId))
    fixture.client.assertionResults = [
      .success(Data("prepared-reconciliation".utf8)),
      .success(Data("unexpected-refresh-assertion".utf8))
    ]
    _ = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    let recreated = DeviceSessionProofProvider(keychain: fixture.keychain, appAttest: fixture.client)

    do {
      _ = try await recreated.refreshRequest(
        session: renewableSession(), installationId: "installation-1", mode: .hosted
      )
      XCTFail("Expected a prepared reconciliation to block refresh proof generation")
    } catch DeviceSessionProofError.appAttestUnavailable {}
    XCTAssertEqual(fixture.client.assertionResults.count, 1)
  }

  func testDefinitivelyFailedSubmittedEnrollmentCanBeRetried() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [
      .success(Data("attestation-1".utf8)),
      .success(Data("attestation-2".utf8))
    ]
    let failed = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "failed-transaction"
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
      signedTransactionInfo: "retried-transaction"
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
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: first.keyId,
      requestId: first.requestId
    ))
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentRegistered(
      keyId: first.keyId,
      requestId: first.requestId
    ))
    fixture.client.assertionResults = [.failure(AppAttestClientError.invalidKey)]
    do {
      _ = try await fixture.provider.hostedEnrollment(
        challenge: challenge("challenge-2"), installationId: "installation-1",
        signedTransactionInfo: "transaction"
      )
      XCTFail("Expected invalid key")
    } catch AppAttestClientError.invalidKey {}

    let replacement = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-3"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertEqual(replacement.keyId, "key-2")
  }

  func testAmbiguousSubmittedEnrollmentUsesReconciliationAfterProviderRecreation() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("attestation".utf8))]
    let first = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: first.keyId,
      requestId: first.requestId
    ))
    let recreated = DeviceSessionProofProvider(keychain: fixture.keychain, appAttest: fixture.client)
    fixture.client.assertionResults = [.success(Data("assertion".utf8))]

    let reconciliation = try await recreated.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertEqual(reconciliation.proofKind, "assertion")
    XCTAssertEqual(reconciliation.preparation, .reconciliation)
    XCTAssertEqual(reconciliation.keyId, first.keyId)
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
  }

  func testDiscardingUnsubmittedReconciliationRestoresUnknownRegistrationForFreshAssertion() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("attestation".utf8))]
    let submitted = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: submitted.keyId,
      requestId: submitted.requestId
    ))
    XCTAssertTrue(fixture.provider.releaseHostedProofOperation(requestId: submitted.requestId))

    fixture.client.assertionResults = [
      .success(Data("discarded-assertion".utf8)),
      .success(Data("replacement-assertion".utf8))
    ]
    let discarded = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertEqual(discarded.preparation, .reconciliation)
    XCTAssertTrue(try fixture.provider.discardUnsubmittedHostedEnrollment(
      keyId: discarded.keyId,
      requestId: discarded.requestId
    ))

    let replacement = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-3"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertEqual(replacement.proofKind, "assertion")
    XCTAssertEqual(replacement.preparation, .reconciliation)
    XCTAssertEqual(replacement.keyId, submitted.keyId)
    XCTAssertNotEqual(replacement.requestId, discarded.requestId)
    XCTAssertEqual(replacement.challengeToken, "challenge-3")
    XCTAssertEqual(fixture.client.generatedKeyCount, 1)
  }

  func testRecreatedProviderReusesOnlyTheExactPreparedReconciliationRequest() async throws {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("attestation".utf8))]
    let submitted = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: submitted.keyId,
      requestId: submitted.requestId
    ))
    XCTAssertTrue(fixture.provider.releaseHostedProofOperation(requestId: submitted.requestId))

    fixture.client.assertionResults = [
      .success(Data("prepared-assertion".utf8)),
      .success(Data("fresh-assertion".utf8))
    ]
    let prepared = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    let recreated = DeviceSessionProofProvider(
      keychain: fixture.keychain,
      now: { Date(timeIntervalSince1970: 1_786_795_200) },
      appAttest: fixture.client
    )
    let reused = try await recreated.hostedEnrollment(
      challenge: challenge("challenge-2"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertEqual(reused.requestId, prepared.requestId)
    XCTAssertEqual(reused.proof, prepared.proof)
    XCTAssertEqual(reused.preparation, .reconciliation)
    XCTAssertTrue(recreated.releaseHostedProofOperation(requestId: reused.requestId))

    let fresh = try await recreated.hostedEnrollment(
      challenge: challenge("challenge-3"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertEqual(fresh.proofKind, "assertion")
    XCTAssertEqual(fresh.preparation, .reconciliation)
    XCTAssertEqual(fresh.keyId, submitted.keyId)
    XCTAssertNotEqual(fresh.requestId, prepared.requestId)
    XCTAssertFalse(try recreated.markHostedEnrollmentSubmissionStarted(
      keyId: prepared.keyId,
      requestId: prepared.requestId
    ))
    XCTAssertTrue(try recreated.markHostedEnrollmentSubmissionStarted(
      keyId: fresh.keyId,
      requestId: fresh.requestId
    ))
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

  private func registeredFixture() async throws -> (
    provider: DeviceSessionProofProvider,
    client: FakeAppAttestClient,
    keychain: SecureKeychainStore
  ) {
    let fixture = makeFixture()
    fixture.client.attestationResults = [.success(Data("attestation".utf8))]
    let initial = try await fixture.provider.hostedEnrollment(
      challenge: challenge("challenge-1"), installationId: "installation-1",
      signedTransactionInfo: "transaction"
    )
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentSubmissionStarted(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))
    XCTAssertTrue(try fixture.provider.markHostedEnrollmentRegistered(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))
    return fixture
  }

  private func renewableSession() -> BackendSessionResponse {
    BackendSessionResponse(
      accessToken: "access-token",
      expiresAt: .distantFuture,
      serviceMode: "hosted",
      dataSourceMode: "tandemSource",
      protocolVersion: 3,
      sessionFamilyId: "session-family",
      refreshToken: "refresh-token",
      refreshTokenExpiresAt: .distantFuture,
      refreshTokenAbsoluteExpiresAt: .distantFuture
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
  var assertionGates: [ProofAsyncGate] = []
  var assertedKeyIds: [String] = []

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
    assertedKeyIds.append(keyId)
    let result = assertionResults.removeFirst()
    if !assertionGates.isEmpty {
      await assertionGates.removeFirst().wait()
    }
    return try result.get()
  }
}
