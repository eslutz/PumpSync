import XCTest
@testable import PumpSync

@MainActor
final class AuthServiceTests: XCTestCase {
  func testLoadsValidCachedSessionWithoutCallingStoreKitOrBackend() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 1_000) })
    let cachedSession = BackendSessionResponse(
      accessToken: "cached-token",
      expiresAt: Date(timeIntervalSince1970: 2_000),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    try sessionStore.save(cachedSession)

    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        XCTFail("StoreKit should not be called when a cached session is valid")
        return "unexpected"
      },
      createSubscriptionSession: { _ in
        XCTFail("Backend should not be called when a cached session is valid")
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in
        XCTFail("Backend should not be called when a cached session is valid")
        throw APIClientError.invalidResponse
      },
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()

    XCTAssertEqual(service.accessToken, "cached-token")
    XCTAssertTrue(service.isSignedIn)
  }

  func testHostedSubscriptionRecoveryAfterAccessDeniedReplacesCachedSession() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 1_000) })
    try sessionStore.save(BackendSessionResponse(
      accessToken: "cached-token",
      expiresAt: Date(timeIntervalSince1970: 2_000),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    ))
    var submittedTransaction: String?
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: { "active-transaction" },
      createSubscriptionSession: { request in
        submittedTransaction = request.signedTransactionInfo
        return BackendSessionResponse(
          accessToken: "replacement-token",
          expiresAt: Date(timeIntervalSince1970: 2_000),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()
    var establishedSessionCallbacks = 0
    service.setHostedSubscriptionSessionEstablishedHandler {
      establishedSessionCallbacks += 1
    }
    let recovered = await service.recoverHostedSubscriptionAfterAccessDenied()

    XCTAssertTrue(recovered)
    XCTAssertEqual(submittedTransaction, "active-transaction")
    XCTAssertEqual(service.accessToken, "replacement-token")
    XCTAssertEqual(establishedSessionCallbacks, 1)
  }

  func testConcurrentSubscriptionRecoveryCoalescesStoreKitAndBackendWork() async {
    var entitlementCalls = 0
    var backendCalls = 0
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: {
        entitlementCalls += 1
        try await Task.sleep(for: .milliseconds(20))
        return "signed-transaction"
      },
      createSubscriptionSession: { _ in
        backendCalls += 1
        try await Task.sleep(for: .milliseconds(20))
        return BackendSessionResponse(
          accessToken: "token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: AcceptingProofProvider()
    )

    async let first: Void = service.recoverSessionIfNeeded()
    async let second: Void = service.recoverSessionIfNeeded()
    _ = await (first, second)

    XCTAssertEqual(entitlementCalls, 1)
    XCTAssertEqual(backendCalls, 1)
    XCTAssertTrue(service.isSignedIn)
  }

  func testExplicitActivationQueuedBehindInFlightSubscriptionOperationEventuallyExecutes() async {
    let diagnostics = makeDiagnostics()
    let firstRequestGate = AsyncGate()
    let firstJWS = "first-explicit-transaction-jws"
    let secondJWS = "second-explicit-transaction-jws"
    var firstRequestStarted = false
    var submittedTransactions: [String] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { request in
        submittedTransactions.append(request.signedTransactionInfo)
        if request.signedTransactionInfo == firstJWS {
          firstRequestStarted = true
          await firstRequestGate.wait()
        }
        return BackendSessionResponse(
          accessToken: "token-\(submittedTransactions.count)",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    let firstActivation = Task {
      await service.activateSubscription(signedTransactionInfo: firstJWS)
    }
    await waitUntil { firstRequestStarted }
    let secondActivation = Task {
      await service.activateSubscription(signedTransactionInfo: secondJWS)
    }
    await waitUntil {
      diagnostics.entries.contains { $0.title == "Subscription operation coalesced" }
    }

    await firstRequestGate.open()
    await firstActivation.value
    await secondActivation.value

    XCTAssertEqual(submittedTransactions, [firstJWS, secondJWS])
    XCTAssertEqual(service.accessToken, "token-2")
  }

  func testExplicitRestoreQueuedBehindInFlightSubscriptionOperationEventuallyExecutes() async {
    let diagnostics = makeDiagnostics()
    let firstRequestGate = AsyncGate()
    let firstJWS = "in-flight-explicit-transaction-jws"
    let restoredJWS = "restored-explicit-transaction-jws"
    var firstRequestStarted = false
    var restoreEntitlementCalls = 0
    var submittedTransactions: [String] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      syncedCurrentEntitlementJWS: {
        restoreEntitlementCalls += 1
        return restoredJWS
      },
      createSubscriptionSession: { request in
        submittedTransactions.append(request.signedTransactionInfo)
        if request.signedTransactionInfo == firstJWS {
          firstRequestStarted = true
          await firstRequestGate.wait()
        }
        return BackendSessionResponse(
          accessToken: "token-\(submittedTransactions.count)",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    let firstActivation = Task {
      await service.activateSubscription(signedTransactionInfo: firstJWS)
    }
    await waitUntil { firstRequestStarted }
    let restore = Task {
      await service.connectUsingCurrentSubscription()
    }
    await waitUntil {
      diagnostics.entries.contains { $0.title == "Subscription operation coalesced" }
    }

    await firstRequestGate.open()
    await firstActivation.value
    await restore.value

    XCTAssertEqual(restoreEntitlementCalls, 1)
    XCTAssertEqual(submittedTransactions, [firstJWS, restoredJWS])
    XCTAssertEqual(service.accessToken, "token-2")
  }

  func testQueuedExplicitActivationDoesNotCrossConnectionGeneration() async {
    let configuration = makeConfigurationStore()
    let diagnostics = makeDiagnostics()
    let firstRequestGate = AsyncGate()
    let firstJWS = "obsolete-in-flight-transaction-jws"
    let queuedJWS = "obsolete-queued-transaction-jws"
    let replacementJWS = "replacement-transaction-jws"
    var firstRequestStarted = false
    var submittedTransactions: [String] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { request in
        submittedTransactions.append(request.signedTransactionInfo)
        if request.signedTransactionInfo == firstJWS {
          firstRequestStarted = true
          await firstRequestGate.wait()
        }
        return BackendSessionResponse(
          accessToken: "token-\(request.signedTransactionInfo)",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    let obsoleteOperation = Task {
      await service.activateSubscription(signedTransactionInfo: firstJWS)
    }
    await waitUntil { firstRequestStarted }
    let obsoleteQueuedActivation = Task {
      await service.activateSubscription(signedTransactionInfo: queuedJWS)
    }
    await waitUntil {
      diagnostics.entries.contains { $0.title == "Subscription operation coalesced" }
    }

    configuration.selfHostedBaseURLString = "https://self-hosted.example/api"
    configuration.mode = .selfHosted
    service.clearSessionForConnectionChange()
    configuration.mode = .hosted
    service.clearSessionForConnectionChange()
    await service.activateSubscription(signedTransactionInfo: replacementJWS)

    await firstRequestGate.open()
    await obsoleteOperation.value
    await obsoleteQueuedActivation.value

    XCTAssertEqual(submittedTransactions, [firstJWS, replacementJWS])
    XCTAssertEqual(service.accessToken, "token-\(replacementJWS)")
  }

  func testCancelledExplicitActivationDoesNotExecuteAfterCoalescedWait() async {
    let diagnostics = makeDiagnostics()
    let firstRequestGate = AsyncGate()
    let firstJWS = "in-flight-before-cancellation-jws"
    let cancelledJWS = "cancelled-queued-transaction-jws"
    var firstRequestStarted = false
    var submittedTransactions: [String] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { request in
        submittedTransactions.append(request.signedTransactionInfo)
        if request.signedTransactionInfo == firstJWS {
          firstRequestStarted = true
          await firstRequestGate.wait()
        }
        return BackendSessionResponse(
          accessToken: "token-\(request.signedTransactionInfo)",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    let firstActivation = Task {
      await service.activateSubscription(signedTransactionInfo: firstJWS)
    }
    await waitUntil { firstRequestStarted }
    let cancelledActivation = Task {
      await service.activateSubscription(signedTransactionInfo: cancelledJWS)
    }
    await waitUntil {
      diagnostics.entries.contains { $0.title == "Subscription operation coalesced" }
    }

    cancelledActivation.cancel()
    await firstRequestGate.open()
    await firstActivation.value
    await cancelledActivation.value

    XCTAssertEqual(submittedTransactions, [firstJWS])
    XCTAssertEqual(service.accessToken, "token-\(firstJWS)")
  }

  func testUncachedSubscriptionSessionTimesOutWithoutDiscardingEntitlementState() async {
    let diagnostics = makeDiagnostics()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { _ in
        try await Task.sleep(for: .seconds(1))
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      subscriptionSessionTimeout: 0.01,
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()

    XCTAssertFalse(service.isConnecting)
    XCTAssertFalse(service.isSignedIn)
    XCTAssertTrue(diagnostics.entries.contains {
      $0.message?.contains("timedOut=true timeoutKind=connectionOperation") == true
    })
  }

  func testNetworkRequestTimeoutIsDistinguishedFromConnectionOperationTimeout() async {
    let diagnostics = makeDiagnostics()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { _ in
        throw URLError(.timedOut)
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()

    XCTAssertTrue(diagnostics.entries.contains {
      $0.message?.contains("timedOut=true timeoutKind=networkRequest") == true
    })
  }

  func testHostedWarmupCompletesBeforeChallengeAndEnrollment() async {
    var events: [String] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { _ in
        events.append("enrollment")
        return BackendSessionResponse(
          accessToken: "token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      warmupHostedService: {
        events.append("warmup")
      },
      proofProvider: AcceptingProofProvider(),
      createSessionChallenge: { _ in
        events.append("challenge")
        return SessionChallengeResponse(
          protocolVersion: 3,
          proofKind: "appAttest",
          challengeToken: "challenge",
          expiresAt: .distantFuture
        )
      }
    )

    await service.recoverSessionIfNeeded()

    XCTAssertEqual(events, ["warmup", "challenge", "enrollment"])
    XCTAssertTrue(service.isSignedIn)
  }

  func testHostedWarmupFailureStopsEnrollmentAndOffersRetry() async {
    let diagnostics = makeDiagnostics()
    var enrollmentCalls = 0
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { _ in
        enrollmentCalls += 1
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      warmupHostedService: {
        throw URLError(.cannotConnectToHost)
      },
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()

    XCTAssertEqual(enrollmentCalls, 0)
    XCTAssertFalse(service.isSignedIn)
    XCTAssertTrue(service.errorMessage?.contains("temporarily unavailable") == true)
    XCTAssertTrue(diagnostics.entries.contains { $0.title == "Hosted service warm-up failed" })
  }

  func testSuccessfulHostedConnectionRecordsSafePhaseDiagnostics() async {
    let diagnostics = makeDiagnostics()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction-secret" },
      createSubscriptionSession: { _ in
        BackendSessionResponse(
          accessToken: "token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      warmupHostedService: {},
      proofProvider: AcceptingProofProvider(),
      createSessionChallenge: { _ in
        SessionChallengeResponse(
          protocolVersion: 3,
          proofKind: "appAttest",
          challengeToken: "challenge-secret",
          expiresAt: .distantFuture
        )
      }
    )

    await service.recoverSessionIfNeeded()

    let warmup = diagnostics.entries.first { $0.title == "Hosted service warm-up completed" }
    let challenge = diagnostics.entries.first { $0.title == "Hosted session challenge received" }
    let proof = diagnostics.entries.first { $0.title == "Hosted device proof prepared" }
    let post = diagnostics.entries.first { $0.title == "Subscription session request completed" }
    XCTAssertTrue(warmup?.message?.contains("elapsedMs=") == true)
    XCTAssertTrue(challenge?.message?.contains("elapsedMs=") == true)
    XCTAssertTrue(challenge?.message?.contains("proofKind=appAttest") == true)
    XCTAssertTrue(proof?.message?.contains("elapsedMs=") == true)
    XCTAssertTrue(proof?.message?.contains("proofKind=attestation") == true)
    XCTAssertTrue(proof?.message?.contains("preparation=generated") == true)
    XCTAssertTrue(post?.message?.contains("elapsedMs=") == true)
    XCTAssertTrue(post?.message?.contains("proofKind=attestation") == true)
    XCTAssertTrue(post?.message?.contains("outcome=success") == true)

    let recorded = diagnostics.entries.compactMap(\.message).joined(separator: " ")
    XCTAssertFalse(recorded.contains("signed-transaction-secret"))
    XCTAssertFalse(recorded.contains("challenge-secret"))
    XCTAssertFalse(recorded.contains("app-attest-key"))
    XCTAssertFalse(recorded.contains("raw-proof-secret"), "diagnostics must not include raw proof material")
  }

  func testDefinitiveDeviceProofRejectionGivesExplicitRetryCleanEnrollmentState() async {
    let appAttest = SequencedAppAttestClient()
    appAttest.attestationResults = [
      .success(Data("attestation-1".utf8)),
      .success(Data("attestation-2".utf8))
    ]
    let proofProvider = DeviceSessionProofProvider(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.rejected-enrollment.\(UUID().uuidString)"),
      now: { Date(timeIntervalSince1970: 1_000) },
      appAttest: appAttest
    )
    var challengeCount = 0
    var requests: [SubscriptionSessionRequest] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { request in
        requests.append(request)
        if requests.count == 1 {
          throw APIClientError.httpStatus(
            401,
            code: "device_proof_rejected",
            message: "The device proof was rejected. Reconnect and try again."
          )
        }
        return BackendSessionResponse(
          accessToken: "token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: proofProvider,
      createSessionChallenge: { _ in
        challengeCount += 1
        return SessionChallengeResponse(
          protocolVersion: 3,
          proofKind: "appAttest",
          challengeToken: "challenge-\(challengeCount)",
          expiresAt: .distantFuture
        )
      }
    )

    await service.connectUsingCurrentSubscription()
    XCTAssertEqual(requests.count, 1, "A rejected initial attestation must not retry automatically")
    XCTAssertEqual(appAttest.generatedKeyCount, 1)
    await service.connectUsingCurrentSubscription()

    XCTAssertEqual(requests.count, 2)
    XCTAssertEqual(requests[0].deviceEnrollment.challengeToken, "challenge-1")
    XCTAssertEqual(requests[1].deviceEnrollment.challengeToken, "challenge-2")
    XCTAssertNotEqual(requests[1].deviceEnrollment.keyId, requests[0].deviceEnrollment.keyId)
    XCTAssertEqual(appAttest.generatedKeyCount, 2)
    XCTAssertTrue(service.isSignedIn)
  }

  func testAmbiguousEnrollmentTransportFailureReconcilesOnNextExplicitConnect() async {
    let appAttest = SequencedAppAttestClient()
    appAttest.attestationResults = [.success(Data("attestation".utf8))]
    appAttest.assertionResults = [.success(Data("assertion".utf8))]
    let proofProvider = DeviceSessionProofProvider(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.ambiguous-enrollment.\(UUID().uuidString)"),
      now: { Date(timeIntervalSince1970: 1_000) },
      appAttest: appAttest
    )
    var backendRegistered = false
    var challengeCount = 0
    var requests: [SubscriptionSessionRequest] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { request in
        requests.append(request)
        if requests.count == 1 {
          backendRegistered = true
          throw URLError(.networkConnectionLost)
        }
        guard backendRegistered, request.deviceEnrollment.proofKind == "assertion" else {
          throw APIClientError.httpStatus(
            401,
            code: "device_proof_rejected",
            message: "The device proof was rejected."
          )
        }
        return BackendSessionResponse(
          accessToken: "token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: proofProvider,
      createSessionChallenge: { _ in
        challengeCount += 1
        return SessionChallengeResponse(
          protocolVersion: 3,
          proofKind: "appAttest",
          challengeToken: "challenge-\(challengeCount)",
          expiresAt: .distantFuture
        )
      }
    )

    await service.connectUsingCurrentSubscription()
    await service.connectUsingCurrentSubscription()

    XCTAssertEqual(requests.map(\.deviceEnrollment.proofKind), ["attestation", "assertion"])
    XCTAssertEqual(requests.map(\.deviceEnrollment.challengeToken), ["challenge-1", "challenge-2"])
    XCTAssertEqual(Set(requests.map(\.deviceEnrollment.requestId)).count, 2)
    XCTAssertEqual(requests.map(\.deviceEnrollment.keyId), ["key-1", "key-1"])
    XCTAssertEqual(requests[1].deviceEnrollment.preparation, .reconciliation)
    XCTAssertEqual(challengeCount, 2)
    XCTAssertEqual(appAttest.generatedKeyCount, 1)
    XCTAssertTrue(service.isSignedIn)
  }

  func testServerFailureBeforeRegistrationRejectsReconciliationAndRetriesFreshAttestation() async {
    let appAttest = SequencedAppAttestClient()
    appAttest.attestationResults = [
      .success(Data("attestation-1".utf8)),
      .success(Data("attestation-2".utf8))
    ]
    appAttest.assertionResults = [.success(Data("assertion".utf8))]
    let proofProvider = DeviceSessionProofProvider(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.ambiguous-server-enrollment.\(UUID().uuidString)"),
      now: { Date(timeIntervalSince1970: 1_000) },
      appAttest: appAttest
    )
    var challengeCount = 0
    var requests: [SubscriptionSessionRequest] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { request in
        requests.append(request)
        if requests.count == 1 {
          throw APIClientError.httpStatus(500, code: "server_error", message: "request failed")
        }
        if request.deviceEnrollment.proofKind == "assertion" {
          throw APIClientError.httpStatus(
            401,
            code: "device_enrollment_required",
            message: "Device enrollment is required."
          )
        }
        return BackendSessionResponse(
          accessToken: "token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: proofProvider,
      createSessionChallenge: { _ in
        challengeCount += 1
        return SessionChallengeResponse(
          protocolVersion: 3,
          proofKind: "appAttest",
          challengeToken: "challenge-\(challengeCount)",
          expiresAt: .distantFuture
        )
      }
    )

    await service.connectUsingCurrentSubscription()
    await service.connectUsingCurrentSubscription()

    XCTAssertEqual(requests.map(\.deviceEnrollment.proofKind), ["attestation", "assertion", "attestation"])
    XCTAssertEqual(requests.map(\.deviceEnrollment.challengeToken), ["challenge-1", "challenge-2", "challenge-3"])
    XCTAssertEqual(Set(requests.map(\.deviceEnrollment.requestId)).count, 3)
    XCTAssertEqual(requests.map(\.deviceEnrollment.keyId), ["key-1", "key-1", "key-2"])
    XCTAssertEqual(requests[1].deviceEnrollment.preparation, .reconciliation)
    XCTAssertEqual(challengeCount, 3)
    XCTAssertEqual(appAttest.generatedKeyCount, 2)
    XCTAssertTrue(service.isSignedIn)
  }

  func testEnrollmentRequiredForReconciliationRetriesOnceWithFreshAttestation() async throws {
    let appAttest = SequencedAppAttestClient()
    appAttest.attestationResults = [
      .success(Data("initial-attestation".utf8)),
      .success(Data("replacement-attestation".utf8))
    ]
    appAttest.assertionResults = [.success(Data("reconciliation-assertion".utf8))]
    let proofProvider = DeviceSessionProofProvider(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.rejected-reconciliation.\(UUID().uuidString)"),
      now: { Date(timeIntervalSince1970: 1_000) },
      appAttest: appAttest
    )
    let configuration = makeConfigurationStore()
    let submitted = try await proofProvider.hostedEnrollment(
      challenge: SessionChallengeResponse(
        protocolVersion: 3,
        proofKind: "appAttest",
        challengeToken: "initial-challenge",
        expiresAt: .distantFuture
      ),
      installationId: configuration.installationId,
      signedTransactionInfo: "signed-transaction"
    )
    XCTAssertTrue(try proofProvider.markHostedEnrollmentSubmissionStarted(
      keyId: submitted.keyId,
      requestId: submitted.requestId
    ))
    XCTAssertTrue(proofProvider.releaseHostedProofOperation(requestId: submitted.requestId))

    var challengeCount = 0
    var requests: [SubscriptionSessionRequest] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { request in
        requests.append(request)
        if requests.count == 1 {
          throw APIClientError.httpStatus(
            401,
            code: "device_enrollment_required",
            message: "Device enrollment is required."
          )
        }
        return BackendSessionResponse(
          accessToken: "token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: proofProvider,
      createSessionChallenge: { _ in
        challengeCount += 1
        return SessionChallengeResponse(
          protocolVersion: 3,
          proofKind: "appAttest",
          challengeToken: "challenge-\(challengeCount)",
          expiresAt: .distantFuture
        )
      }
    )

    await service.connectUsingCurrentSubscription()

    XCTAssertEqual(requests.map(\.deviceEnrollment.proofKind), ["assertion", "attestation"])
    XCTAssertEqual(requests.map(\.deviceEnrollment.keyId), ["key-1", "key-2"])
    XCTAssertEqual(requests.map(\.deviceEnrollment.challengeToken), ["challenge-1", "challenge-2"])
    XCTAssertEqual(Set(requests.map(\.deviceEnrollment.requestId)).count, 2)
    XCTAssertEqual(challengeCount, 2)
    XCTAssertEqual(appAttest.generatedKeyCount, 2)
    XCTAssertTrue(service.isSignedIn)
  }

  func testAssertionSignatureMismatchReattestsWithFreshKey() async throws {
    let appAttest = SequencedAppAttestClient()
    appAttest.attestationResults = [
      .success(Data("initial-attestation".utf8)),
      .success(Data("replacement-attestation".utf8))
    ]
    appAttest.assertionResults = [.success(Data("rejected-registered-assertion".utf8))]
    let proofProvider = DeviceSessionProofProvider(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.rejected-registered-assertion.\(UUID().uuidString)"),
      now: { Date(timeIntervalSince1970: 1_000) },
      appAttest: appAttest
    )
    let configuration = makeConfigurationStore()
    let initial = try await proofProvider.hostedEnrollment(
      challenge: SessionChallengeResponse(
        protocolVersion: 3,
        proofKind: "appAttest",
        challengeToken: "initial-challenge",
        expiresAt: .distantFuture
      ),
      installationId: configuration.installationId,
      signedTransactionInfo: "signed-transaction"
    )
    XCTAssertTrue(try proofProvider.markHostedEnrollmentSubmissionStarted(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))
    XCTAssertTrue(try proofProvider.markHostedEnrollmentRegistered(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))

    var challengeCount = 0
    var requests: [SubscriptionSessionRequest] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { request in
        requests.append(request)
        if requests.count == 1 {
          throw APIClientError.httpStatus(
            401,
            code: "device_key_reenrollment_required",
            message: "The device security key needs to be re-enrolled."
          )
        }
        return BackendSessionResponse(
          accessToken: "token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: proofProvider,
      createSessionChallenge: { _ in
        challengeCount += 1
        return SessionChallengeResponse(
          protocolVersion: 3,
          proofKind: "appAttest",
          challengeToken: "challenge-\(challengeCount)",
          expiresAt: .distantFuture
        )
      }
    )

    await service.connectUsingCurrentSubscription()

    XCTAssertEqual(requests.map(\.deviceEnrollment.proofKind), ["assertion", "attestation"])
    XCTAssertEqual(requests.map(\.deviceEnrollment.keyId), ["key-1", "key-2"])
    XCTAssertEqual(requests.map(\.deviceEnrollment.challengeToken), ["challenge-1", "challenge-2"])
    XCTAssertEqual(Set(requests.map(\.deviceEnrollment.requestId)).count, 2)
    XCTAssertEqual(challengeCount, 2)
    XCTAssertEqual(appAttest.generatedKeyCount, 2)
    XCTAssertTrue(service.isSignedIn)
  }

  func testRejectedRegisteredAssertionRetriesOnlyOnceWhenFreshAssertionIsRejected() async throws {
    let appAttest = SequencedAppAttestClient()
    appAttest.attestationResults = [.success(Data("initial-attestation".utf8))]
    appAttest.assertionResults = [
      .success(Data("rejected-registered-assertion".utf8)),
      .success(Data("second-rejected-registered-assertion".utf8))
    ]
    let proofProvider = DeviceSessionProofProvider(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.rejected-registered-assertion-bound.\(UUID().uuidString)"),
      now: { Date(timeIntervalSince1970: 1_000) },
      appAttest: appAttest
    )
    let configuration = makeConfigurationStore()
    let initial = try await proofProvider.hostedEnrollment(
      challenge: SessionChallengeResponse(
        protocolVersion: 3,
        proofKind: "appAttest",
        challengeToken: "initial-challenge",
        expiresAt: .distantFuture
      ),
      installationId: configuration.installationId,
      signedTransactionInfo: "signed-transaction"
    )
    XCTAssertTrue(try proofProvider.markHostedEnrollmentSubmissionStarted(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))
    XCTAssertTrue(try proofProvider.markHostedEnrollmentRegistered(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))

    var challengeCount = 0
    var requests: [SubscriptionSessionRequest] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { request in
        requests.append(request)
        throw APIClientError.httpStatus(
          401,
          code: "device_proof_rejected",
          message: "The device proof was rejected."
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: proofProvider,
      createSessionChallenge: { _ in
        challengeCount += 1
        return SessionChallengeResponse(
          protocolVersion: 3,
          proofKind: "appAttest",
          challengeToken: "challenge-\(challengeCount)",
          expiresAt: .distantFuture
        )
      }
    )

    await service.connectUsingCurrentSubscription()

    XCTAssertEqual(requests.map(\.deviceEnrollment.proofKind), ["assertion", "assertion"])
    XCTAssertEqual(requests.map(\.deviceEnrollment.keyId), ["key-1", "key-1"])
    XCTAssertEqual(requests.map(\.deviceEnrollment.challengeToken), ["challenge-1", "challenge-2"])
    XCTAssertEqual(Set(requests.map(\.deviceEnrollment.requestId)).count, 2)
    XCTAssertEqual(challengeCount, 2)
    XCTAssertEqual(appAttest.generatedKeyCount, 1)
    XCTAssertFalse(service.isSignedIn)
  }

  func testEnrollmentRequiredRetriesOnlyOnceWhenFreshAttestationIsRejected() async throws {
    let appAttest = SequencedAppAttestClient()
    appAttest.attestationResults = [
      .success(Data("initial-attestation".utf8)),
      .success(Data("replacement-attestation".utf8))
    ]
    appAttest.assertionResults = [.success(Data("registered-assertion".utf8))]
    let proofProvider = DeviceSessionProofProvider(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.enrollment-required-bound.\(UUID().uuidString)"),
      now: { Date(timeIntervalSince1970: 1_000) },
      appAttest: appAttest
    )
    let configuration = makeConfigurationStore()
    let initial = try await proofProvider.hostedEnrollment(
      challenge: SessionChallengeResponse(
        protocolVersion: 3,
        proofKind: "appAttest",
        challengeToken: "initial-challenge",
        expiresAt: .distantFuture
      ),
      installationId: configuration.installationId,
      signedTransactionInfo: "signed-transaction"
    )
    XCTAssertTrue(try proofProvider.markHostedEnrollmentSubmissionStarted(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))
    XCTAssertTrue(try proofProvider.markHostedEnrollmentRegistered(
      keyId: initial.keyId,
      requestId: initial.requestId
    ))

    var challengeCount = 0
    var requests: [SubscriptionSessionRequest] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { request in
        requests.append(request)
        let code = requests.count == 1 ? "device_enrollment_required" : "device_proof_rejected"
        throw APIClientError.httpStatus(401, code: code, message: "The device proof was rejected.")
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: proofProvider,
      createSessionChallenge: { _ in
        challengeCount += 1
        return SessionChallengeResponse(
          protocolVersion: 3,
          proofKind: "appAttest",
          challengeToken: "challenge-\(challengeCount)",
          expiresAt: .distantFuture
        )
      }
    )

    await service.connectUsingCurrentSubscription()

    XCTAssertEqual(requests.map(\.deviceEnrollment.proofKind), ["assertion", "attestation"])
    XCTAssertEqual(requests.map(\.deviceEnrollment.keyId), ["key-1", "key-2"])
    XCTAssertEqual(requests.map(\.deviceEnrollment.challengeToken), ["challenge-1", "challenge-2"])
    XCTAssertEqual(Set(requests.map(\.deviceEnrollment.requestId)).count, 2)
    XCTAssertEqual(challengeCount, 2)
    XCTAssertEqual(appAttest.generatedKeyCount, 2)
    XCTAssertFalse(service.isSignedIn)
  }

  func testSubscriptionSessionTimeoutCancelsTheInFlightBackendOperation() async throws {
    var backendOperationWasCancelled = false
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { _ in
        do {
          try await Task.sleep(for: .seconds(1))
          throw APIClientError.invalidResponse
        } catch is CancellationError {
          backendOperationWasCancelled = true
          throw CancellationError()
        }
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      subscriptionSessionTimeout: 0.01,
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()
    try await Task.sleep(for: .milliseconds(20))

    XCTAssertTrue(backendOperationWasCancelled)
  }

  func testSubscriptionRestoreCreatesBackendSession() async {
    let diagnostics = makeDiagnostics()
    let configuration = makeConfigurationStore()
    let sessionStore = makeSessionStore()
    let session = BackendSessionResponse(
      accessToken: "token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        XCTFail("Silent entitlement reads should not be used for explicit restore")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      syncedCurrentEntitlementJWS: {
        "signed-transaction"
      },
      createSubscriptionSession: { request in
        XCTAssertEqual(request.signedTransactionInfo, "signed-transaction")
        XCTAssertEqual(request.installationId, configuration.installationId)
        return session
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    await service.connectUsingCurrentSubscription()

    XCTAssertTrue(service.isSignedIn)
    XCTAssertFalse(service.isConnecting)
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(service.statusMessage, "PumpSync subscription active")
    XCTAssertEqual(sessionStore.loadValidSession(), session)
    XCTAssertTrue(diagnostics.entries.map(\.title).contains("Subscription session timing"))
    XCTAssertTrue(diagnostics.entries.map(\.title).contains("PumpSync subscription restored"))
  }

  func testSubscriptionPurchaseCompletionCreatesBackendSession() async {
    let diagnostics = makeDiagnostics()
    let configuration = makeConfigurationStore()
    let sessionStore = makeSessionStore()
    let session = BackendSessionResponse(
      accessToken: "token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      syncedCurrentEntitlementJWS: {
        XCTFail("Purchase completion should use the signed transaction returned by StoreKit")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { request in
        XCTAssertEqual(request.signedTransactionInfo, "signed-purchase-transaction")
        XCTAssertEqual(request.installationId, configuration.installationId)
        return session
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    await service.activateSubscription(signedTransactionInfo: "signed-purchase-transaction")

    XCTAssertTrue(service.isSignedIn)
    XCTAssertFalse(service.isConnecting)
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(service.statusMessage, "PumpSync subscription active")
    XCTAssertEqual(sessionStore.loadValidSession(), session)
    XCTAssertTrue(diagnostics.entries.map(\.title).contains("Subscription session timing"))
    XCTAssertTrue(diagnostics.entries.map(\.title).contains("PumpSync subscription purchased"))
  }

  func testAutomaticTransactionUpdateActivatesSubscriptionForUnattemptedJWS() async {
    var submittedTransactions: [String] = []
    var finishCount = 0
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { request in
        submittedTransactions.append(request.signedTransactionInfo)
        return BackendSessionResponse(
          accessToken: "token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: AcceptingProofProvider()
    )

    await service.handleActiveSubscriptionTransactionUpdate(
      signedTransactionInfo: "automatic-transaction-jws",
      diagnosticSummary: "productID=subscription, active=true",
      finish: { finishCount += 1 }
    )

    XCTAssertEqual(finishCount, 1)
    XCTAssertEqual(submittedTransactions, ["automatic-transaction-jws"])
    XCTAssertTrue(service.isSignedIn)
  }

  func testAutomaticTransactionUpdateSkipsSameJWSAfterDefinitiveSessionFailure() async {
    let signedTransactionInfo = "duplicate-transaction-jws-secret"
    let diagnostics = makeDiagnostics()
    let appAttest = SequencedAppAttestClient()
    appAttest.attestationResults = [
      .success(Data("attestation-1".utf8)),
      .success(Data("attestation-2".utf8))
    ]
    let proofProvider = DeviceSessionProofProvider(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.automatic-dedup.\(UUID().uuidString)"),
      now: { Date(timeIntervalSince1970: 1_000) },
      appAttest: appAttest
    )
    var challengeCount = 0
    var backendCalls = 0
    var finishCount = 0
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in
        backendCalls += 1
        throw APIClientError.httpStatus(
          401,
          code: "device_proof_rejected",
          message: "The device proof was rejected. Reconnect and try again."
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: proofProvider,
      createSessionChallenge: { _ in
        challengeCount += 1
        return SessionChallengeResponse(
          protocolVersion: 3,
          proofKind: "appAttest",
          challengeToken: "challenge-\(challengeCount)",
          expiresAt: .distantFuture
        )
      }
    )

    await service.activateSubscription(signedTransactionInfo: signedTransactionInfo)
    await service.handleActiveSubscriptionTransactionUpdate(
      signedTransactionInfo: signedTransactionInfo,
      diagnosticSummary: "productID=subscription, id=…0001, active=true",
      finish: { finishCount += 1 }
    )

    XCTAssertEqual(finishCount, 1)
    XCTAssertEqual(backendCalls, 1, "an automatic replay must not resubmit a definitively failed session")
    XCTAssertEqual(challengeCount, 1, "an automatic replay must not request another challenge")
    XCTAssertEqual(appAttest.generatedKeyCount, 1, "an automatic replay must not generate another App Attest key")
    let skipped = diagnostics.entries.first { $0.title == "PumpSync subscription transaction update skipped" }
    XCTAssertTrue(skipped?.message?.contains("reason=duplicateSessionAttempt") == true)
    XCTAssertFalse(diagnostics.entries.compactMap(\.message).joined(separator: " ").contains(signedTransactionInfo))
  }

  func testAutomaticTransactionUpdateSkipsSameJWSAfterSuccessfulSession() async {
    let signedTransactionInfo = "successful-transaction-jws"
    let diagnostics = makeDiagnostics()
    var backendCalls = 0
    var finishCount = 0
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in
        backendCalls += 1
        return BackendSessionResponse(
          accessToken: "token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    await service.activateSubscription(signedTransactionInfo: signedTransactionInfo)
    await service.handleActiveSubscriptionTransactionUpdate(
      signedTransactionInfo: signedTransactionInfo,
      diagnosticSummary: "productID=subscription, id=…0002, active=true",
      finish: { finishCount += 1 }
    )

    XCTAssertEqual(finishCount, 1)
    XCTAssertEqual(backendCalls, 1)
    XCTAssertTrue(service.isSignedIn)
    XCTAssertTrue(diagnostics.entries.contains {
      $0.title == "PumpSync subscription transaction update skipped"
        && $0.message?.contains("reason=duplicateSessionAttempt") == true
    })
  }

  func testAutomaticTransactionUpdateSkipsSameJWSAfterAmbiguousSessionFailure() async {
    let signedTransactionInfo = "ambiguous-transaction-jws"
    let diagnostics = makeDiagnostics()
    let appAttest = SequencedAppAttestClient()
    appAttest.attestationResults = [.success(Data("attestation".utf8))]
    let proofProvider = DeviceSessionProofProvider(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.automatic-ambiguous-dedup.\(UUID().uuidString)"),
      now: { Date(timeIntervalSince1970: 1_000) },
      appAttest: appAttest
    )
    var challengeCount = 0
    var backendCalls = 0
    var finishCount = 0
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in
        backendCalls += 1
        throw URLError(.networkConnectionLost)
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: proofProvider,
      createSessionChallenge: { _ in
        challengeCount += 1
        return SessionChallengeResponse(
          protocolVersion: 3,
          proofKind: "appAttest",
          challengeToken: "challenge-\(challengeCount)",
          expiresAt: .distantFuture
        )
      }
    )

    await service.activateSubscription(signedTransactionInfo: signedTransactionInfo)
    await service.handleActiveSubscriptionTransactionUpdate(
      signedTransactionInfo: signedTransactionInfo,
      diagnosticSummary: "productID=subscription, id=…0003, active=true",
      finish: { finishCount += 1 }
    )

    XCTAssertEqual(finishCount, 1)
    XCTAssertEqual(backendCalls, 1)
    XCTAssertEqual(challengeCount, 1)
    XCTAssertEqual(appAttest.generatedKeyCount, 1)
    XCTAssertTrue(diagnostics.entries.contains {
      $0.title == "PumpSync subscription transaction update skipped"
        && $0.message?.contains("reason=duplicateSessionAttempt") == true
    })
  }

  func testConfigurationChangeAfterAttestationDiscardsUnsubmittedEnrollmentForExplicitRetry() async {
    let configuration = makeConfigurationStore()
    let diagnostics = makeDiagnostics()
    let attestationGate = AsyncGate()
    var attestationStarted = false
    let appAttest = SequencedAppAttestClient()
    appAttest.attestationResults = [
      .success(Data("attestation-1".utf8)),
      .success(Data("attestation-2".utf8))
    ]
    appAttest.attestationStarted = { attestationStarted = true }
    appAttest.attestationGate = attestationGate
    let proofProvider = DeviceSessionProofProvider(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.mode-change-attestation.\(UUID().uuidString)"),
      now: { Date(timeIntervalSince1970: 1_000) },
      appAttest: appAttest
    )
    var challengeCount = 0
    var backendCalls = 0
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in
        backendCalls += 1
        return BackendSessionResponse(
          accessToken: "retry-token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: proofProvider,
      createSessionChallenge: { _ in
        challengeCount += 1
        return SessionChallengeResponse(
          protocolVersion: 3,
          proofKind: "appAttest",
          challengeToken: "challenge-\(challengeCount)",
          expiresAt: .distantFuture
        )
      }
    )

    let interruptedEnrollment = Task {
      await service.activateSubscription(signedTransactionInfo: "first-transaction-jws")
    }
    await waitUntil { attestationStarted }

    configuration.selfHostedBaseURLString = "https://self-hosted.example/api"
    configuration.mode = .selfHosted
    service.clearSessionForConnectionChange()
    await attestationGate.open()
    await interruptedEnrollment.value

    configuration.mode = .hosted
    service.clearSessionForConnectionChange()
    await service.activateSubscription(signedTransactionInfo: "different-transaction-jws")

    XCTAssertEqual(appAttest.generatedKeyCount, 2)
    XCTAssertEqual(backendCalls, 1)
    XCTAssertEqual(service.accessToken, "retry-token")
    XCTAssertTrue(diagnostics.entries.contains {
      $0.title == "Unsubmitted App Attest enrollment discarded"
        && $0.message == "reason=connectionModeChanged backendSubmitted=false"
    })
    XCTAssertFalse(diagnostics.entries.contains {
      $0.title == "App Attest enrollment requires reconciliation"
    })
  }

  func testAutomaticTransactionUpdateSkipsSameJWSAfterWarmupFailure() async {
    let signedTransactionInfo = "warmup-failure-transaction-jws"
    let diagnostics = makeDiagnostics()
    var warmupCalls = 0
    var backendCalls = 0
    var finishCount = 0
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in
        backendCalls += 1
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      warmupHostedService: {
        warmupCalls += 1
        throw URLError(.cannotConnectToHost)
      },
      proofProvider: AcceptingProofProvider()
    )

    await service.activateSubscription(signedTransactionInfo: signedTransactionInfo)
    await service.handleActiveSubscriptionTransactionUpdate(
      signedTransactionInfo: signedTransactionInfo,
      diagnosticSummary: "productID=subscription, id=…0004, active=true",
      finish: { finishCount += 1 }
    )

    XCTAssertEqual(finishCount, 1)
    XCTAssertEqual(warmupCalls, 1, "the JWS must be recorded before hosted warm-up begins")
    XCTAssertEqual(backendCalls, 0)
    XCTAssertTrue(diagnostics.entries.contains {
      $0.title == "PumpSync subscription transaction update skipped"
        && $0.message?.contains("reason=duplicateSessionAttempt") == true
    })
  }

  func testAutomaticTransactionUpdateActivatesDifferentJWSAfterPriorAttempt() async {
    var submittedTransactions: [String] = []
    var finishCount = 0
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { request in
        submittedTransactions.append(request.signedTransactionInfo)
        if submittedTransactions.count == 1 {
          throw APIClientError.httpStatus(
            401,
            code: "invalid_app_store_transaction",
            message: "The App Store transaction was rejected."
          )
        }
        return BackendSessionResponse(
          accessToken: "token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: AcceptingProofProvider()
    )

    await service.activateSubscription(signedTransactionInfo: "first-transaction-jws")
    await service.handleActiveSubscriptionTransactionUpdate(
      signedTransactionInfo: "different-transaction-jws",
      diagnosticSummary: "productID=subscription, id=…0004, active=true",
      finish: { finishCount += 1 }
    )

    XCTAssertEqual(finishCount, 1)
    XCTAssertEqual(submittedTransactions, ["first-transaction-jws", "different-transaction-jws"])
    XCTAssertTrue(service.isSignedIn)
  }

  func testAutomaticTransactionUpdateQueuesDifferentJWSWhilePriorAttemptIsInFlight() async {
    let diagnostics = makeDiagnostics()
    let firstRequestGate = AsyncGate()
    var submittedTransactions: [String] = []
    var finishCount = 0
    var firstRequestStarted = false
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { request in
        submittedTransactions.append(request.signedTransactionInfo)
        if submittedTransactions.count == 1 {
          firstRequestStarted = true
          await firstRequestGate.wait()
          throw APIClientError.httpStatus(
            401,
            code: "invalid_app_store_transaction",
            message: "The App Store transaction was rejected."
          )
        }
        return BackendSessionResponse(
          accessToken: "token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    let firstAttempt = Task {
      await service.activateSubscription(signedTransactionInfo: "first-transaction-jws")
    }
    await waitUntil { firstRequestStarted }

    let automaticUpdate = Task {
      await service.handleActiveSubscriptionTransactionUpdate(
        signedTransactionInfo: "different-transaction-jws",
        diagnosticSummary: "productID=subscription, id=…0005, active=true",
        finish: { finishCount += 1 }
      )
    }
    await waitUntil {
      finishCount == 1 && diagnostics.entries.contains {
        $0.title == "Subscription operation coalesced"
      }
    }

    await firstRequestGate.open()
    await firstAttempt.value
    await automaticUpdate.value

    XCTAssertEqual(finishCount, 1)
    XCTAssertEqual(submittedTransactions, ["first-transaction-jws", "different-transaction-jws"])
    XCTAssertTrue(service.isSignedIn)
  }

  func testAutomaticTransactionUpdatesQueueEveryDistinctJWSAcrossRepeatedCoalescing() async {
    let diagnostics = makeDiagnostics()
    let firstRequestGate = AsyncGate()
    let secondRequestGate = AsyncGate()
    let firstJWS = "first-transaction-jws"
    let secondJWS = "second-transaction-jws"
    let thirdJWS = "third-transaction-jws"
    var submittedTransactions: [String] = []
    var finishCount = 0
    var firstRequestStarted = false
    var secondRequestStarted = false
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { request in
        submittedTransactions.append(request.signedTransactionInfo)
        if request.signedTransactionInfo == firstJWS {
          firstRequestStarted = true
          await firstRequestGate.wait()
          throw APIClientError.httpStatus(
            401,
            code: "invalid_app_store_transaction",
            message: "The App Store transaction was rejected."
          )
        }
        if submittedTransactions.count == 2 {
          secondRequestStarted = true
          await secondRequestGate.wait()
        }
        return BackendSessionResponse(
          accessToken: "token-\(submittedTransactions.count)",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    let firstAttempt = Task {
      await service.activateSubscription(signedTransactionInfo: firstJWS)
    }
    await waitUntil { firstRequestStarted }

    let secondUpdate = Task {
      await service.handleActiveSubscriptionTransactionUpdate(
        signedTransactionInfo: secondJWS,
        diagnosticSummary: "productID=subscription, id=…0006, active=true",
        finish: { finishCount += 1 }
      )
    }
    let thirdUpdate = Task {
      await service.handleActiveSubscriptionTransactionUpdate(
        signedTransactionInfo: thirdJWS,
        diagnosticSummary: "productID=subscription, id=…0007, active=true",
        finish: { finishCount += 1 }
      )
    }
    await waitUntil {
      diagnostics.entries.filter { $0.title == "Subscription operation coalesced" }.count == 2
    }

    await firstRequestGate.open()
    await firstAttempt.value
    await waitUntil { secondRequestStarted }
    await waitUntil {
      diagnostics.entries.filter { $0.title == "Subscription operation coalesced" }.count == 3
    }
    await secondRequestGate.open()
    await secondUpdate.value
    await thirdUpdate.value

    XCTAssertEqual(finishCount, 2)
    XCTAssertEqual(submittedTransactions.first, firstJWS)
    XCTAssertEqual(Set(submittedTransactions), Set([firstJWS, secondJWS, thirdJWS]))
    XCTAssertEqual(submittedTransactions.count, 3)
  }

  func testConnectionChangeLetsExplicitRestoreBypassObsoleteSubscriptionOperation() async {
    let configuration = makeConfigurationStore()
    let warmupGate = AsyncGate()
    var firstWarmupStarted = false
    var warmupCount = 0
    var restoreEntitlementCalls = 0
    var submittedTransactions: [String] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      syncedCurrentEntitlementJWS: {
        restoreEntitlementCalls += 1
        return "restored-transaction-jws"
      },
      createSubscriptionSession: { request in
        submittedTransactions.append(request.signedTransactionInfo)
        return BackendSessionResponse(
          accessToken: "restored-token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      warmupHostedService: {
        warmupCount += 1
        if warmupCount == 1 {
          firstWarmupStarted = true
          await warmupGate.wait()
        }
      },
      proofProvider: AcceptingProofProvider()
    )

    let obsoleteOperation = Task {
      await service.activateSubscription(signedTransactionInfo: "obsolete-transaction-jws")
    }
    await waitUntil { firstWarmupStarted }

    configuration.selfHostedBaseURLString = "https://self-hosted.example/api"
    configuration.mode = .selfHosted
    service.clearSessionForConnectionChange()
    configuration.mode = .hosted
    service.clearSessionForConnectionChange()

    let restore = Task {
      await service.connectUsingCurrentSubscription()
    }
    await waitUntil { restoreEntitlementCalls == 1 }
    await warmupGate.open()
    await restore.value
    await obsoleteOperation.value

    XCTAssertEqual(restoreEntitlementCalls, 1)
    XCTAssertEqual(submittedTransactions, ["restored-transaction-jws"])
    XCTAssertEqual(service.accessToken, "restored-token")
  }

  func testAutomaticTransactionUpdateDoesNotActivateAfterSwitchingToSelfHostedDuringFinish() async {
    let configuration = makeConfigurationStore()
    let diagnostics = makeDiagnostics()
    let finishGate = AsyncGate()
    let signedTransactionInfo = "hosted-transaction-jws"
    var finishStarted = false
    var submittedTransactions: [String] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { request in
        submittedTransactions.append(request.signedTransactionInfo)
        return BackendSessionResponse(
          accessToken: "unexpected-hosted-token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    let automaticUpdate = Task {
      await service.handleActiveSubscriptionTransactionUpdate(
        signedTransactionInfo: signedTransactionInfo,
        diagnosticSummary: "productID=subscription, id=…0008, active=true",
        finish: {
          finishStarted = true
          await finishGate.wait()
        }
      )
    }
    await waitUntil { finishStarted }

    configuration.selfHostedBaseURLString = "https://self-hosted.example/api"
    configuration.mode = .selfHosted
    service.clearSessionForConnectionChange()
    await finishGate.open()
    await automaticUpdate.value

    XCTAssertTrue(submittedTransactions.isEmpty)
    XCTAssertFalse(service.isSignedIn)
    XCTAssertTrue(diagnostics.entries.contains {
      $0.title == "PumpSync subscription transaction update skipped"
        && $0.message?.contains("reason=connectionModeChanged") == true
    })
  }

  func testAutomaticTransactionUpdateDoesNotActivateAfterSwitchingToSelfHostedDuringCoalescedWait() async {
    let configuration = makeConfigurationStore()
    let diagnostics = makeDiagnostics()
    let firstRequestGate = AsyncGate()
    let firstJWS = "first-transaction-jws"
    let automaticJWS = "automatic-transaction-jws"
    var submittedTransactions: [String] = []
    var firstRequestStarted = false
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { request in
        submittedTransactions.append(request.signedTransactionInfo)
        if request.signedTransactionInfo == firstJWS {
          firstRequestStarted = true
          await firstRequestGate.wait()
          throw APIClientError.httpStatus(
            401,
            code: "invalid_app_store_transaction",
            message: "The App Store transaction was rejected."
          )
        }
        return BackendSessionResponse(
          accessToken: "unexpected-hosted-token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    let firstAttempt = Task {
      await service.activateSubscription(signedTransactionInfo: firstJWS)
    }
    await waitUntil { firstRequestStarted }
    let automaticUpdate = Task {
      await service.handleActiveSubscriptionTransactionUpdate(
        signedTransactionInfo: automaticJWS,
        diagnosticSummary: "productID=subscription, id=…0009, active=true",
        finish: {}
      )
    }
    await waitUntil {
      diagnostics.entries.contains { $0.title == "Subscription operation coalesced" }
    }

    configuration.selfHostedBaseURLString = "https://self-hosted.example/api"
    configuration.mode = .selfHosted
    service.clearSessionForConnectionChange()
    await firstRequestGate.open()
    await firstAttempt.value
    await automaticUpdate.value

    XCTAssertEqual(submittedTransactions, [firstJWS])
    XCTAssertFalse(service.isSignedIn)
    XCTAssertTrue(diagnostics.entries.contains {
      $0.title == "PumpSync subscription transaction update skipped"
        && $0.message?.contains("reason=connectionModeChanged") == true
    })
  }

  func testAutomaticTransactionUpdateStopsEnrollmentAfterSwitchingToSelfHostedDuringWarmup() async {
    let configuration = makeConfigurationStore()
    let diagnostics = makeDiagnostics()
    let warmupGate = AsyncGate()
    var warmupStarted = false
    var challengeCalls = 0
    var backendCalls = 0
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in
        backendCalls += 1
        return BackendSessionResponse(
          accessToken: "unexpected-hosted-token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      warmupHostedService: {
        warmupStarted = true
        await warmupGate.wait()
      },
      proofProvider: AcceptingProofProvider(),
      createSessionChallenge: { _ in
        challengeCalls += 1
        return SessionChallengeResponse(
          protocolVersion: 3,
          proofKind: "appAttest",
          challengeToken: "challenge",
          expiresAt: .distantFuture
        )
      }
    )

    let automaticUpdate = Task {
      await service.handleActiveSubscriptionTransactionUpdate(
        signedTransactionInfo: "warmup-mode-change-jws",
        diagnosticSummary: "productID=subscription, id=…0010, active=true",
        finish: {}
      )
    }
    await waitUntil { warmupStarted }

    configuration.selfHostedBaseURLString = "https://self-hosted.example/api"
    configuration.mode = .selfHosted
    service.clearSessionForConnectionChange()
    await warmupGate.open()
    await automaticUpdate.value

    XCTAssertEqual(challengeCalls, 0)
    XCTAssertEqual(backendCalls, 0)
    XCTAssertFalse(service.isSignedIn)
    XCTAssertTrue(diagnostics.entries.contains {
      $0.title == "PumpSync subscription transaction update skipped"
        && $0.message?.contains("reason=connectionModeChanged") == true
    })
  }

  func testAutomaticTransactionUpdateDoesNotCommitHostedResponseAfterSwitchingToSelfHosted() async {
    let configuration = makeConfigurationStore()
    let diagnostics = makeDiagnostics()
    let backendGate = AsyncGate()
    var backendStarted = false
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in
        backendStarted = true
        await backendGate.wait()
        return BackendSessionResponse(
          accessToken: "stale-hosted-token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    let automaticUpdate = Task {
      await service.handleActiveSubscriptionTransactionUpdate(
        signedTransactionInfo: "backend-mode-change-jws",
        diagnosticSummary: "productID=subscription, id=…0011, active=true",
        finish: {}
      )
    }
    await waitUntil { backendStarted }

    configuration.selfHostedBaseURLString = "https://self-hosted.example/api"
    configuration.mode = .selfHosted
    service.clearSessionForConnectionChange()
    await backendGate.open()
    await automaticUpdate.value

    XCTAssertFalse(service.isSignedIn)
    XCTAssertNil(service.accessToken)
    XCTAssertTrue(diagnostics.entries.contains {
      $0.title == "PumpSync subscription transaction update skipped"
        && $0.message?.contains("reason=connectionModeChanged") == true
    })
  }

  func testSubscriptionRecoveryDoesNotClearSelfHostedReplacementAfterStoreKitSuspends() async {
    let configuration = makeConfigurationStore()
    let diagnostics = makeDiagnostics()
    let entitlementGate = AsyncGate()
    var entitlementStarted = false
    let sessionStore = makeSessionStore()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        entitlementStarted = true
        await entitlementGate.wait()
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in
        BackendSessionResponse(
          accessToken: "self-hosted-token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "selfHosted",
          dataSourceMode: "tandemSource"
        )
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider(),
      createSessionChallenge: { _ in Self.selfHostedChallenge(token: "self-hosted-challenge") }
    )

    let staleRecovery = Task {
      await service.recoverSessionIfNeeded()
    }
    await waitUntil { entitlementStarted }

    configuration.selfHostedBaseURLString = "https://self-hosted.example/api"
    configuration.mode = .selfHosted
    service.clearSessionForConnectionChange()
    await service.connectSelfHosted()
    await entitlementGate.open()
    await staleRecovery.value

    XCTAssertEqual(service.accessToken, "self-hosted-token")
    XCTAssertEqual(sessionStore.loadValidSession()?.accessToken, "self-hosted-token")
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(service.statusMessage, "Connected to self-hosted service")
    XCTAssertTrue(diagnostics.entries.contains {
      $0.title == "Subscription recovery stopped" && $0.message == "reason=connectionModeChanged"
    })
  }

  func testSubscriptionRestoreDoesNotPublishStaleFailureAfterModeChange() async {
    let configuration = makeConfigurationStore()
    let diagnostics = makeDiagnostics()
    let entitlementGate = AsyncGate()
    var entitlementStarted = false
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      syncedCurrentEntitlementJWS: {
        entitlementStarted = true
        await entitlementGate.wait()
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in
        BackendSessionResponse(
          accessToken: "self-hosted-token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "selfHosted",
          dataSourceMode: "tandemSource"
        )
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider(),
      createSessionChallenge: { _ in Self.selfHostedChallenge(token: "self-hosted-challenge") }
    )

    let staleRestore = Task {
      await service.connectUsingCurrentSubscription()
    }
    await waitUntil { entitlementStarted }

    configuration.selfHostedBaseURLString = "https://self-hosted.example/api"
    configuration.mode = .selfHosted
    service.clearSessionForConnectionChange()
    await service.connectSelfHosted()
    await entitlementGate.open()
    await staleRestore.value

    XCTAssertEqual(service.accessToken, "self-hosted-token")
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(service.statusMessage, "Connected to self-hosted service")
    XCTAssertTrue(diagnostics.entries.contains {
      $0.title == "Subscription restore stopped" && $0.message == "reason=connectionModeChanged"
    })
  }

  func testExplicitActivationAllowsSameJWSRetryAfterDefinitiveSessionFailure() async {
    let signedTransactionInfo = "explicit-retry-transaction-jws"
    var submittedTransactions: [String] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { request in
        submittedTransactions.append(request.signedTransactionInfo)
        if submittedTransactions.count == 1 {
          throw APIClientError.httpStatus(
            401,
            code: "invalid_app_store_transaction",
            message: "The App Store transaction was rejected."
          )
        }
        return BackendSessionResponse(
          accessToken: "token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: AcceptingProofProvider()
    )

    await service.activateSubscription(signedTransactionInfo: signedTransactionInfo)
    await service.activateSubscription(signedTransactionInfo: signedTransactionInfo)

    XCTAssertEqual(submittedTransactions, [signedTransactionInfo, signedTransactionInfo])
    XCTAssertTrue(service.isSignedIn)
  }

  func testSubscriptionRestorePublishesUserSafeErrorAndDiagnostics() async {
    let diagnostics = makeDiagnostics()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: {
        "signed-transaction"
      },
      createSubscriptionSession: { _ in
        throw APIClientError.httpStatus(
          401,
          code: "invalid_app_store_transaction",
          message: "Subscription validation failed for user@example.com."
        )
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    await service.connectUsingCurrentSubscription()

    let expectedMessage = "PumpSync could not verify your App Store subscription. Check your Apple Account subscription, then try Restore Subscription again."
    XCTAssertFalse(service.isSignedIn)
    XCTAssertFalse(service.isConnecting)
    XCTAssertEqual(service.statusMessage, expectedMessage)
    XCTAssertEqual(service.errorMessage, expectedMessage)
    XCTAssertEqual(service.connectionRequiredMessage, expectedMessage)
    let failure = diagnostics.entries.first { $0.title == "Subscription session failed" }
    XCTAssertEqual(
      failure?.message,
      "The App Store subscription credential was rejected by PumpSync. backendCode=invalid_app_store_transaction"
    )
  }

  func testSubscriptionRestoreFailurePreservesExistingSession() async throws {
    let diagnostics = makeDiagnostics()
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 1_000) })
    let existingSession = BackendSessionResponse(
      accessToken: "existing-token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    try sessionStore.save(existingSession)
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      syncedCurrentEntitlementJWS: {
        "signed-transaction"
      },
      createSubscriptionSession: { _ in
        throw APIClientError.httpStatus(
          401,
          code: "invalid_app_store_transaction",
          message: "Signed App Store payload validation failed."
        )
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    XCTAssertEqual(service.accessToken, "existing-token")

    await service.connectUsingCurrentSubscription()

    let expectedMessage = "PumpSync could not verify your App Store subscription. Check your Apple Account subscription, then try Restore Subscription again."
    XCTAssertTrue(service.isSignedIn)
    XCTAssertFalse(service.isConnecting)
    XCTAssertEqual(service.accessToken, "existing-token")
    XCTAssertEqual(service.statusMessage, expectedMessage)
    XCTAssertEqual(service.errorMessage, expectedMessage)
    XCTAssertEqual(sessionStore.loadValidSession(), existingSession)
    XCTAssertNotNil(diagnostics.entries.first { $0.title == "Subscription session failed" })
  }

  func testCancelledPurchasePreservesExistingSession() throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 1_000) })
    let existingSession = BackendSessionResponse(
      accessToken: "existing-token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    try sessionStore.save(existingSession)
    let service = makeSubscriptionService(sessionStore: sessionStore)

    service.recordSubscriptionPurchaseCancelled()

    XCTAssertTrue(service.isSignedIn)
    XCTAssertEqual(service.accessToken, "existing-token")
    XCTAssertEqual(sessionStore.loadValidSession(), existingSession)
  }

  func testPendingPurchasePreservesExistingSession() throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 1_000) })
    let existingSession = BackendSessionResponse(
      accessToken: "existing-token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    try sessionStore.save(existingSession)
    let service = makeSubscriptionService(sessionStore: sessionStore)

    service.recordSubscriptionPurchasePending()

    XCTAssertTrue(service.isSignedIn)
    XCTAssertEqual(service.accessToken, "existing-token")
    XCTAssertEqual(sessionStore.loadValidSession(), existingSession)
  }

  func testSilentSubscriptionRecoveryCreatesBackendSessionWhenNoCachedSessionExists() async {
    let configuration = makeConfigurationStore()
    let sessionStore = makeSessionStore()
    let session = BackendSessionResponse(
      accessToken: "recovered-token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        "signed-transaction"
      },
      syncedCurrentEntitlementJWS: {
        XCTFail("Silent recovery should not call AppStore.sync")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { request in
        XCTAssertEqual(request.signedTransactionInfo, "signed-transaction")
        XCTAssertEqual(request.installationId, configuration.installationId)
        return session
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()

    XCTAssertEqual(service.accessToken, "recovered-token")
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(sessionStore.loadValidSession(), session)
  }

  func testForegroundSubscriptionRecoverySyncsAppStoreAfterCachedEntitlementMiss() async {
    let configuration = makeConfigurationStore()
    let sessionStore = makeSessionStore()
    let session = BackendSessionResponse(
      accessToken: "recovered-token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    var syncedEntitlementCalls = 0
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      syncedCurrentEntitlementJWS: {
        syncedEntitlementCalls += 1
        return "synced-transaction"
      },
      createSubscriptionSession: { request in
        XCTAssertEqual(request.signedTransactionInfo, "synced-transaction")
        return session
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded(policy: .foreground)

    XCTAssertEqual(syncedEntitlementCalls, 1)
    XCTAssertEqual(service.accessToken, "recovered-token")
    XCTAssertEqual(sessionStore.loadValidSession(), session)
  }

  func testAccessTokenRecoveryPreservesStaleSessionAfterAmbiguousRefreshFailure() async throws {
    var now = Date(timeIntervalSince1970: 1_000)
    let sessionStore = makeSessionStore(now: { now })
    let staleSession = BackendSessionResponse(
      accessToken: "stale-token",
      expiresAt: Date(timeIntervalSince1970: 2_000),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    try sessionStore.save(staleSession)
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        "signed-transaction"
      },
      syncedCurrentEntitlementJWS: {
        XCTFail("Stale token recovery during sync should not call AppStore.sync")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        XCTFail("An ambiguous refresh failure must not fall back to enrollment")
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      proofProvider: AcceptingProofProvider()
    )

    XCTAssertEqual(service.accessToken, "stale-token")

    now = Date(timeIntervalSince1970: 1_800)
    let accessToken = await service.accessTokenRecoveringIfNeeded()

    XCTAssertNil(accessToken)
    XCTAssertEqual(sessionStore.loadRecoverableSession(), staleSession)
  }

  func testSilentSubscriptionRecoveryDoesNotPublishAlertStyleErrorWhenNoEntitlementExists() async {
    let diagnostics = makeDiagnostics()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      syncedCurrentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        XCTFail("Backend should not be called without StoreKit entitlement")
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()

    XCTAssertFalse(service.isSignedIn)
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(service.statusMessage, "Connect to PumpSync or a self-hosted service")
    XCTAssertEqual(diagnostics.entries.first?.title, "Subscription recovery skipped")
    XCTAssertEqual(diagnostics.entries.first?.message, "No current StoreKit entitlement was available for subscription recovery.")
  }

  func testSelfHostedCreatesBackendSession() async {
    let configuration = makeConfigurationStore()
    configuration.mode = .selfHosted
    configuration.selfHostedBaseURLString = "https://self-host.example/api"
    let sessionStore = makeSessionStore()

    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { request in
        XCTAssertEqual(request.installationId, configuration.installationId)
        return BackendSessionResponse(
          accessToken: "self-hosted-token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "selfHosted",
          dataSourceMode: "tandemSource"
        )
      },
      proofProvider: AcceptingProofProvider()
    )

    await service.connectSelfHosted()

    XCTAssertEqual(service.accessToken, "self-hosted-token")
    XCTAssertEqual(service.statusMessage, "Connected to self-hosted service")
    XCTAssertEqual(sessionStore.loadValidSession()?.accessToken, "self-hosted-token")
  }

  func testSelfHostedConnectionStopsIfTheBaseURLChangesDuringChallenge() async {
    let configuration = makeConfigurationStore()
    configuration.mode = .selfHosted
    configuration.selfHostedBaseURLString = "https://old-self-host.example/api"
    let diagnostics = makeDiagnostics()
    let sessionStore = makeSessionStore()
    let oldChallengeGate = AsyncGate()
    var challengeCount = 0
    var oldChallengeStarted = false
    var submittedChallengeTokens: [String] = []
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { request in
        submittedChallengeTokens.append(request.deviceEnrollment.challengeToken)
        return BackendSessionResponse(
          accessToken: request.deviceEnrollment.challengeToken == "new-challenge" ? "new-token" : "stale-token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "selfHosted",
          dataSourceMode: "tandemSource"
        )
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider(),
      createSessionChallenge: { _ in
        challengeCount += 1
        if challengeCount == 1 {
          oldChallengeStarted = true
          await oldChallengeGate.wait()
          return Self.selfHostedChallenge(token: "old-challenge")
        }
        return Self.selfHostedChallenge(token: "new-challenge")
      }
    )

    let oldConnection = Task {
      await service.connectSelfHosted()
    }
    await waitUntil { oldChallengeStarted }

    configuration.selfHostedBaseURLString = "https://new-self-host.example/api"
    service.clearSessionForConnectionChange()
    await service.connectSelfHosted()

    XCTAssertEqual(service.accessToken, "new-token")
    await oldChallengeGate.open()
    await oldConnection.value

    XCTAssertEqual(submittedChallengeTokens, ["new-challenge"])
    XCTAssertEqual(service.accessToken, "new-token")
    XCTAssertEqual(sessionStore.loadValidSession()?.accessToken, "new-token")
    XCTAssertNotNil(diagnostics.entries.first {
      $0.title == "Self-hosted session stopped" && $0.message == "reason=connectionModeChanged"
    })
  }

  func testSelfHostedRecoveryDoesNotCommitAResponseFromAnOldBaseURL() async {
    let configuration = makeConfigurationStore()
    configuration.mode = .selfHosted
    configuration.selfHostedBaseURLString = "https://old-self-host.example/api"
    let diagnostics = makeDiagnostics()
    let sessionStore = makeSessionStore()
    let staleResponseGate = AsyncGate()
    var challengeCount = 0
    var staleResponseStarted = false
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { request in
        if request.deviceEnrollment.challengeToken == "old-challenge" {
          staleResponseStarted = true
          await staleResponseGate.wait()
          return BackendSessionResponse(
            accessToken: "stale-token",
            expiresAt: Date(timeIntervalSince1970: 1_800),
            serviceMode: "selfHosted",
            dataSourceMode: "tandemSource"
          )
        }
        return BackendSessionResponse(
          accessToken: "new-token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "selfHosted",
          dataSourceMode: "tandemSource"
        )
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider(),
      createSessionChallenge: { _ in
        challengeCount += 1
        return Self.selfHostedChallenge(token: challengeCount == 1 ? "old-challenge" : "new-challenge")
      }
    )

    let oldRecovery = Task {
      await service.recoverSessionIfNeeded()
    }
    await waitUntil { staleResponseStarted }

    configuration.selfHostedBaseURLString = "https://new-self-host.example/api"
    service.clearSessionForConnectionChange()
    await service.connectSelfHosted()

    XCTAssertEqual(service.accessToken, "new-token")
    await staleResponseGate.open()
    await oldRecovery.value

    XCTAssertEqual(service.accessToken, "new-token")
    XCTAssertEqual(sessionStore.loadValidSession()?.accessToken, "new-token")
    XCTAssertNotNil(diagnostics.entries.first {
      $0.title == "Self-hosted session stopped" && $0.message == "reason=connectionModeChanged"
    })
  }

  func testSelfHostedBaseURLRequiresHttpsForNonLoopbackHosts() {
    let configuration = makeConfigurationStore()
    configuration.mode = .selfHosted

    configuration.selfHostedBaseURLString = "http://192.168.1.50:8080"
    XCTAssertNil(configuration.selectedBaseURL, "a plain-HTTP IP-literal self-host URL must be rejected")

    configuration.selfHostedBaseURLString = "http://backend.example.com"
    XCTAssertNil(configuration.selectedBaseURL, "a plain-HTTP hostname self-host URL must be rejected")

    configuration.selfHostedBaseURLString = "https://192.168.1.50:8080"
    XCTAssertNotNil(configuration.selectedBaseURL, "an HTTPS self-host URL must be accepted")
  }

  func testSelfHostedBaseURLAllowsHttpForLoopbackOnly() {
    let configuration = makeConfigurationStore()
    configuration.mode = .selfHosted

    configuration.selfHostedBaseURLString = "http://localhost:8080"
    XCTAssertNotNil(configuration.selectedBaseURL, "plain HTTP to localhost must be allowed for local development")

    configuration.selfHostedBaseURLString = "http://127.0.0.1:8080"
    XCTAssertNotNil(configuration.selectedBaseURL, "plain HTTP to 127.0.0.1 must be allowed for local development")
  }

  func testSelfHostedBaseURLRejectsMalformedOrEmptyInput() {
    let configuration = makeConfigurationStore()
    configuration.mode = .selfHosted

    configuration.selfHostedBaseURLString = ""
    XCTAssertNil(configuration.selectedBaseURL)

    configuration.selfHostedBaseURLString = "not a url"
    XCTAssertNil(configuration.selectedBaseURL)

    configuration.selfHostedBaseURLString = "ftp://backend.example.com"
    XCTAssertNil(configuration.selectedBaseURL, "non-http(s) schemes must be rejected")
  }

  func testConnectionChangeClearsCachedSession() throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 1_000) })
    try sessionStore.save(
      BackendSessionResponse(
        accessToken: "cached-token",
        expiresAt: Date(timeIntervalSince1970: 2_000),
        serviceMode: "hosted",
        dataSourceMode: "tandemSource"
      )
    )
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      proofProvider: AcceptingProofProvider()
    )

    service.clearSessionForConnectionChange()

    XCTAssertNil(sessionStore.loadValidSession())
    XCTAssertFalse(service.isSignedIn)
  }

  func testExpiredCachedSessionIsPreservedAfterAmbiguousRefreshFailure() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    let expiredSession = BackendSessionResponse(
      accessToken: "expired-token",
      expiresAt: Date(timeIntervalSince1970: 1_999),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    try sessionStore.save(expiredSession)
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        "signed-transaction"
      },
      createSubscriptionSession: { _ in
        XCTFail("An ambiguous refresh failure must not fall back to enrollment")
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()

    XCTAssertNil(service.accessToken)
    XCTAssertEqual(sessionStore.loadRecoverableSession(), expiredSession)
  }

  func testBackgroundRecoveryRefreshesRenewableSessionWithoutStoreKit() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    try sessionStore.save(BackendSessionResponse(
      accessToken: "expired-access-token",
      expiresAt: Date(timeIntervalSince1970: 1_999),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource",
      protocolVersion: 3,
      sessionFamilyId: "family-1",
      refreshToken: "refresh-token-1",
      refreshTokenExpiresAt: Date(timeIntervalSince1970: 3_000),
      refreshTokenAbsoluteExpiresAt: Date(timeIntervalSince1970: 4_000)
    ))
    let refreshed = BackendSessionResponse(
      accessToken: "refreshed-access-token",
      expiresAt: Date(timeIntervalSince1970: 3_000),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource",
      protocolVersion: 3,
      sessionFamilyId: "family-2",
      refreshToken: "refresh-token-2",
      refreshTokenExpiresAt: Date(timeIntervalSince1970: 3_500),
      refreshTokenAbsoluteExpiresAt: Date(timeIntervalSince1970: 4_000)
    )
    let responseData = try JSONCodec.encoder.encode(refreshed)
    URLProtocolStub.requestHandler = { request in
      XCTAssertEqual(request.url?.path, "/api/v1/session/refresh")
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, responseData)
    }
    defer { URLProtocolStub.requestHandler = nil }
    let apiClient = PumpSyncAPIClient(
      baseURL: URL(string: "https://example.com/api")!,
      urlSession: URLProtocolStub.makeSession(),
      maxRetryCount: 0
    )
    let proofProvider = AcceptingProofProvider()
    let service = AuthService(
      apiClient: apiClient,
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        XCTFail("Background renewable-session recovery must not call StoreKit")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        XCTFail("Background renewable-session recovery must not create a subscription session")
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: proofProvider
    )

    let token = await service.accessTokenRecoveringIfNeeded(policy: .background)

    XCTAssertEqual(token, "refreshed-access-token")
    XCTAssertEqual(sessionStore.loadValidSession(), refreshed)
    XCTAssertEqual(proofProvider.releasedHostedProofRequestIds, ["request-1"])
  }

  func testConcurrentRenewableRecoveryUsesOneRefreshAndSharesReplacementSession() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    try sessionStore.save(Self.expiredRenewableSession())
    let replacement = BackendSessionResponse(
      accessToken: "replacement-access-token",
      expiresAt: Date(timeIntervalSince1970: 3_000),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource",
      protocolVersion: 3,
      sessionFamilyId: "family-2",
      refreshToken: "refresh-token-2",
      refreshTokenExpiresAt: Date(timeIntervalSince1970: 3_500),
      refreshTokenAbsoluteExpiresAt: Date(timeIntervalSince1970: 4_000)
    )
    let responseData = try JSONCodec.encoder.encode(replacement)
    let requestCount = LockedCounter()
    let refreshStarted = expectation(description: "refresh request started")
    let allowResponse = DispatchSemaphore(value: 0)
    URLProtocolStub.requestHandler = { request in
      requestCount.increment()
      refreshStarted.fulfill()
      allowResponse.wait()
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, responseData)
    }
    defer { URLProtocolStub.requestHandler = nil }
    var proofCount = 0
    let proofProvider = AcceptingProofProvider(refreshRequestHandler: { session, installationId, _ in
      proofCount += 1
      return SessionRefreshRequest(
        installationId: installationId,
        refreshToken: session.refreshToken,
        requestId: "shared-request",
        issuedAt: Date(timeIntervalSince1970: 2_000),
        proof: "proof"
      )
    })
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: proofProvider
    )

    let first = Task { await service.accessTokenRecoveringIfNeeded(policy: .background) }
    let second = Task { await service.accessTokenRecoveringIfNeeded(policy: .background) }
    await fulfillment(of: [refreshStarted], timeout: 1)
    allowResponse.signal()
    allowResponse.signal()
    let tokens = await (first.value, second.value)

    XCTAssertEqual(proofCount, 1)
    XCTAssertEqual(requestCount.value, 1)
    XCTAssertEqual(tokens.0, replacement.accessToken)
    XCTAssertEqual(tokens.1, replacement.accessToken)
    XCTAssertEqual(sessionStore.loadValidSession(), replacement)
  }

  func testConcurrentRenewableRecoverySharesAmbiguousFailureWithoutEnrollment() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    let expired = Self.expiredRenewableSession()
    try sessionStore.save(expired)
    let requestCount = LockedCounter()
    let refreshStarted = expectation(description: "refresh request started")
    let allowFailure = DispatchSemaphore(value: 0)
    URLProtocolStub.requestHandler = { _ in
      requestCount.increment()
      refreshStarted.fulfill()
      allowFailure.wait()
      throw URLError(.timedOut)
    }
    defer { URLProtocolStub.requestHandler = nil }
    var proofCount = 0
    var enrollmentCount = 0
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: { "unused" },
      createSubscriptionSession: { _ in
        enrollmentCount += 1
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: AcceptingProofProvider(refreshRequestHandler: { session, installationId, _ in
        proofCount += 1
        return SessionRefreshRequest(
          installationId: installationId,
          refreshToken: session.refreshToken,
          requestId: "shared-request",
          issuedAt: Date(timeIntervalSince1970: 2_000),
          proof: "proof"
        )
      })
    )

    let first = Task { await service.accessTokenRecoveringIfNeeded(policy: .background) }
    let second = Task { await service.accessTokenRecoveringIfNeeded(policy: .background) }
    await fulfillment(of: [refreshStarted], timeout: 1)
    allowFailure.signal()
    allowFailure.signal()
    let tokens = await (first.value, second.value)

    XCTAssertNil(tokens.0)
    XCTAssertNil(tokens.1)
    XCTAssertEqual(proofCount, 1)
    XCTAssertEqual(requestCount.value, 1)
    XCTAssertEqual(enrollmentCount, 0)
    XCTAssertEqual(sessionStore.loadRecoverableSession(), expired)
  }

  func testRejectedRefreshDoesNotDeleteNewerSameConfigurationSession() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    try sessionStore.save(Self.expiredRenewableSession())
    let replacement = BackendSessionResponse(
      accessToken: "replacement-access-token",
      expiresAt: Date(timeIntervalSince1970: 3_000),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource",
      protocolVersion: 3,
      sessionFamilyId: "family-2",
      refreshToken: "refresh-token-2",
      refreshTokenExpiresAt: Date(timeIntervalSince1970: 3_500),
      refreshTokenAbsoluteExpiresAt: Date(timeIntervalSince1970: 4_000)
    )
    let refreshStarted = expectation(description: "refresh request started")
    let allowRejection = DispatchSemaphore(value: 0)
    URLProtocolStub.requestHandler = { request in
      refreshStarted.fulfill()
      allowRejection.wait()
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 401,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, Data(#"{"code":"invalid_token","message":"Expired"}"#.utf8))
    }
    defer { URLProtocolStub.requestHandler = nil }
    let diagnostics = makeDiagnostics()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { _ in replacement },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    let staleRefresh = Task {
      await service.recoverSessionIfNeeded(policy: .background)
    }
    await fulfillment(of: [refreshStarted], timeout: 1)
    await service.connectUsingCurrentSubscription()
    allowRejection.signal()
    await staleRefresh.value

    XCTAssertEqual(service.accessToken, replacement.accessToken)
    XCTAssertEqual(sessionStore.loadValidSession(), replacement)
    XCTAssertNotNil(diagnostics.entries.first {
      $0.title == "Renewable session refresh stopped" && $0.message == "reason=sessionSuperseded"
    })
  }

  func testPermanentRefreshRejectionClearsCurrentSourceSession() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    try sessionStore.save(Self.expiredRenewableSession())
    URLProtocolStub.requestHandler = { request in
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 401,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, Data(#"{"code":"invalid_token","message":"Expired"}"#.utf8))
    }
    defer { URLProtocolStub.requestHandler = nil }
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: AcceptingProofProvider()
    )

    let token = await service.accessTokenRecoveringIfNeeded(policy: .background)

    XCTAssertNil(token)
    XCTAssertNil(sessionStore.loadRecoverableSession())
  }

  func testHostedRecoveryClassifiesNoActiveEntitlementForSubscriptionAction() async {
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      syncedCurrentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()

    XCTAssertTrue(service.requiresSubscriptionAction)
  }

  func testHostedRenewableRefreshBackendFailureReleasesExactProofRequest() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    try sessionStore.save(Self.expiredRenewableSession())
    URLProtocolStub.requestHandler = { request in
      XCTAssertEqual(request.url?.path, "/api/v1/session/refresh")
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 400,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, Data(#"{"code":"refresh_failed","message":"Refresh failed"}"#.utf8))
    }
    defer { URLProtocolStub.requestHandler = nil }
    let proofProvider = AcceptingProofProvider()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        XCTFail("A renewable-session refresh failure must not fall back to StoreKit")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        XCTFail("A renewable-session refresh failure must not fall back to enrollment")
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: proofProvider
    )

    let token = await service.accessTokenRecoveringIfNeeded(policy: .background)

    XCTAssertNil(token)
    XCTAssertEqual(sessionStore.loadRecoverableSession(), Self.expiredRenewableSession())
    XCTAssertEqual(proofProvider.releasedHostedProofRequestIds, ["request-1"])
  }

  func testBackgroundStaleKeyRefreshReenrollsFromCachedEntitlement() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    try sessionStore.save(Self.expiredRenewableSession())
    let replacement = BackendSessionResponse(
      accessToken: "re-enrolled-access-token",
      expiresAt: Date(timeIntervalSince1970: 3_000),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource",
      protocolVersion: 3,
      sessionFamilyId: "family-2",
      refreshToken: "refresh-token-2",
      refreshTokenExpiresAt: Date(timeIntervalSince1970: 3_500),
      refreshTokenAbsoluteExpiresAt: Date(timeIntervalSince1970: 4_000)
    )
    URLProtocolStub.requestHandler = { request in
      XCTAssertEqual(request.url?.path, "/api/v1/session/refresh")
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 401,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, Data(#"{"code":"device_key_reenrollment_required","message":"Re-enroll"}"#.utf8))
    }
    defer { URLProtocolStub.requestHandler = nil }
    let proofProvider = AcceptingProofProvider()
    let diagnostics = makeDiagnostics()
    var entitlementCalls = 0
    var enrollmentCalls = 0
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        entitlementCalls += 1
        return "cached-entitlement"
      },
      createSubscriptionSession: { request in
        enrollmentCalls += 1
        XCTAssertEqual(request.signedTransactionInfo, "cached-entitlement")
        return replacement
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: proofProvider
    )

    let token = await service.accessTokenRecoveringIfNeeded(policy: .backgroundWithReenrollment)

    XCTAssertEqual(token, replacement.accessToken)
    XCTAssertEqual(sessionStore.loadValidSession(), replacement)
    XCTAssertFalse(sessionStore.isHostedReenrollmentPending())
    XCTAssertEqual(entitlementCalls, 1)
    XCTAssertEqual(enrollmentCalls, 1)
    XCTAssertEqual(proofProvider.discardedRegisteredHostedKeyCount, 1)
    XCTAssertTrue(diagnostics.entries.contains { $0.title == "App Attest key re-enrollment required" })
    XCTAssertTrue(diagnostics.entries.contains { $0.title == "Background App Attest re-enrollment started" })
    XCTAssertTrue(diagnostics.entries.contains { $0.title == "Background App Attest re-enrollment completed" })
  }

  func testBackgroundReenrollmentTransientFailureRetainsPendingMarker() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    try sessionStore.markHostedReenrollmentPending()
    let diagnostics = makeDiagnostics()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: { throw URLError(.timedOut) },
      createSubscriptionSession: { _ in
        XCTFail("Enrollment must not start when entitlement lookup is unavailable")
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    let token = await service.accessTokenRecoveringIfNeeded(policy: .backgroundWithReenrollment)

    XCTAssertNil(token)
    XCTAssertTrue(sessionStore.isHostedReenrollmentPending())
    XCTAssertTrue(diagnostics.entries.contains { $0.title == "Background App Attest re-enrollment deferred" && $0.message?.contains("reason=network") == true })
  }

  func testBackgroundReenrollmentWithoutCachedEntitlementRetainsPendingMarker() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    try sessionStore.markHostedReenrollmentPending()
    let diagnostics = makeDiagnostics()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      syncedCurrentEntitlementJWS: {
        XCTFail("Background recovery must not call AppStore.sync")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        XCTFail("Enrollment must not start without a cached entitlement")
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    let token = await service.accessTokenRecoveringIfNeeded(policy: .backgroundWithReenrollment)

    XCTAssertNil(token)
    XCTAssertTrue(sessionStore.isHostedReenrollmentPending())
    XCTAssertTrue(diagnostics.entries.contains {
      $0.title == "Background App Attest re-enrollment deferred"
        && $0.message == "reason=noCachedEntitlement retry=nextRecovery"
    })
  }

  func testSelfHostedProtocol3RenewableRefreshDoesNotUseHostedProofLease() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    let expired = BackendSessionResponse(
      accessToken: "expired-self-hosted-token",
      expiresAt: Date(timeIntervalSince1970: 1_999),
      serviceMode: "selfHosted",
      dataSourceMode: "tandemSource",
      protocolVersion: 3,
      sessionFamilyId: "self-hosted-family-1",
      refreshToken: "self-hosted-refresh-token-1",
      refreshTokenExpiresAt: Date(timeIntervalSince1970: 3_000),
      refreshTokenAbsoluteExpiresAt: Date(timeIntervalSince1970: 4_000)
    )
    try sessionStore.save(expired)
    let refreshed = BackendSessionResponse(
      accessToken: "refreshed-self-hosted-token",
      expiresAt: Date(timeIntervalSince1970: 3_000),
      serviceMode: "selfHosted",
      dataSourceMode: "tandemSource",
      protocolVersion: 3,
      sessionFamilyId: "self-hosted-family-2",
      refreshToken: "self-hosted-refresh-token-2",
      refreshTokenExpiresAt: Date(timeIntervalSince1970: 3_500),
      refreshTokenAbsoluteExpiresAt: Date(timeIntervalSince1970: 4_000)
    )
    let responseData = try JSONCodec.encoder.encode(refreshed)
    URLProtocolStub.requestHandler = { request in
      XCTAssertEqual(request.url?.host, "self-host.example")
      XCTAssertEqual(request.url?.path, "/api/v1/session/refresh")
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, responseData)
    }
    defer { URLProtocolStub.requestHandler = nil }
    let configuration = makeConfigurationStore()
    configuration.selfHostedBaseURLString = "https://self-host.example/api"
    configuration.mode = .selfHosted
    let proofProvider = AcceptingProofProvider(refreshRequestHandler: { session, installationId, mode in
      XCTAssertEqual(mode, .selfHosted)
      return SessionRefreshRequest(
        installationId: installationId,
        refreshToken: session.refreshToken,
        requestId: "self-hosted-request-1",
        issuedAt: Date(timeIntervalSince1970: 2_000),
        proof: "self-hosted-proof"
      )
    })
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        XCTFail("Self-hosted renewable refresh must not call StoreKit")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in
        XCTFail("A renewable self-hosted session must refresh instead of reenrolling")
        throw APIClientError.invalidResponse
      },
      proofProvider: proofProvider
    )

    let token = await service.accessTokenRecoveringIfNeeded(policy: .background)

    XCTAssertEqual(token, "refreshed-self-hosted-token")
    XCTAssertEqual(sessionStore.loadValidSession(), refreshed)
    XCTAssertTrue(proofProvider.releasedHostedProofRequestIds.isEmpty)
  }

  func testRenewableRefreshStopsBeforeRequestIfConfigurationChangesDuringProof() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    try sessionStore.save(Self.expiredRenewableSession())
    let configuration = makeConfigurationStore()
    let diagnostics = makeDiagnostics()
    let proofGate = AsyncGate()
    var proofStarted = false
    let unexpectedRefreshRequest = expectation(description: "stale refresh request")
    unexpectedRefreshRequest.isInverted = true
    let staleResponseData = try JSONCodec.encoder.encode(BackendSessionResponse(
      accessToken: "stale-refreshed-token",
      expiresAt: Date(timeIntervalSince1970: 3_000),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    ))
    URLProtocolStub.requestHandler = { request in
      unexpectedRefreshRequest.fulfill()
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, staleResponseData)
    }
    defer { URLProtocolStub.requestHandler = nil }
    let proofProvider = AcceptingProofProvider(refreshRequestHandler: { session, installationId, _ in
      proofStarted = true
      await proofGate.wait()
      return SessionRefreshRequest(
        installationId: installationId,
        refreshToken: session.refreshToken,
        requestId: "request-1",
        issuedAt: Date(timeIntervalSince1970: 2_000),
        proof: "proof"
      )
    })
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in
        BackendSessionResponse(
          accessToken: "new-self-hosted-token",
          expiresAt: Date(timeIntervalSince1970: 3_000),
          serviceMode: "selfHosted",
          dataSourceMode: "tandemSource"
        )
      },
      diagnostics: diagnostics,
      proofProvider: proofProvider,
      createSessionChallenge: { _ in Self.selfHostedChallenge(token: "new-challenge") }
    )

    let staleRefresh = Task {
      await service.recoverSessionIfNeeded(policy: .background)
    }
    await waitUntil { proofStarted }

    configuration.selfHostedBaseURLString = "https://new-self-host.example/api"
    configuration.mode = .selfHosted
    service.clearSessionForConnectionChange()
    await service.connectSelfHosted()
    await proofGate.open()
    await staleRefresh.value

    await fulfillment(of: [unexpectedRefreshRequest], timeout: 0.1)
    XCTAssertEqual(service.accessToken, "new-self-hosted-token")
    XCTAssertEqual(sessionStore.loadValidSession()?.accessToken, "new-self-hosted-token")
    XCTAssertEqual(proofProvider.releasedHostedProofRequestIds, ["request-1"])
    XCTAssertNotNil(diagnostics.entries.first {
      $0.title == "Renewable session refresh stopped" && $0.message == "reason=connectionModeChanged"
    })
  }

  func testRenewableRefreshFailureDoesNotClearAReplacementConnection() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    try sessionStore.save(Self.expiredRenewableSession())
    let configuration = makeConfigurationStore()
    let diagnostics = makeDiagnostics()
    let refreshStarted = expectation(description: "refresh request started")
    let allowRefreshToFail = DispatchSemaphore(value: 0)
    URLProtocolStub.requestHandler = { request in
      refreshStarted.fulfill()
      allowRefreshToFail.wait()
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 401,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, Data(#"{"code":"invalid_token","message":"Expired"}"#.utf8))
    }
    defer { URLProtocolStub.requestHandler = nil }
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in
        BackendSessionResponse(
          accessToken: "new-self-hosted-token",
          expiresAt: Date(timeIntervalSince1970: 3_000),
          serviceMode: "selfHosted",
          dataSourceMode: "tandemSource"
        )
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider(),
      createSessionChallenge: { _ in Self.selfHostedChallenge(token: "new-challenge") }
    )

    let staleRefresh = Task {
      await service.recoverSessionIfNeeded(policy: .background)
    }
    await fulfillment(of: [refreshStarted], timeout: 1)

    configuration.selfHostedBaseURLString = "https://new-self-host.example/api"
    configuration.mode = .selfHosted
    service.clearSessionForConnectionChange()
    await service.connectSelfHosted()
    allowRefreshToFail.signal()
    await staleRefresh.value

    XCTAssertEqual(service.accessToken, "new-self-hosted-token")
    XCTAssertEqual(sessionStore.loadValidSession()?.accessToken, "new-self-hosted-token")
    XCTAssertNotNil(diagnostics.entries.first {
      $0.title == "Renewable session refresh stopped" && $0.message == "reason=connectionModeChanged"
    })
  }

  func testSubscriptionConnectionRequiredMessageUsesSubscriptionTerminology() {
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      proofProvider: AcceptingProofProvider()
    )

    let expected = "No PumpSync service was found. Please subscribe to PumpSync or set up your own self-hosted PumpSync service."
    XCTAssertEqual(service.connectionRequiredMessage, expected)
    XCTAssertEqual(StoreKitSubscriptionError.noActiveSubscription.errorDescription, expected)
  }

  private func makeAPIClient() -> PumpSyncAPIClient {
    PumpSyncAPIClient(
      baseURL: URL(string: "https://example.com/api")!,
      urlSession: URLProtocolStub.makeSession(),
      maxRetryCount: 0
    )
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

  private func makeConfigurationStore() -> BackendConfigurationStore {
    let defaults = UserDefaults(suiteName: "AuthServiceTests-\(UUID().uuidString)")!
    return BackendConfigurationStore(defaults: defaults)
  }

  private func makeSubscriptionService(sessionStore: BackendSessionStore) -> AuthService {
    AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: AcceptingProofProvider()
    )
  }

  private func makeSessionStore(now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }) -> BackendSessionStore {
    BackendSessionStore(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)"),
      now: now
    )
  }

  private func makeDiagnostics() -> DiagnosticsLogStore {
    DiagnosticsLogStore(defaults: UserDefaults(suiteName: "AuthServiceTests-\(UUID().uuidString)")!)
  }

  private static func selfHostedChallenge(token: String) -> SessionChallengeResponse {
    SessionChallengeResponse(
      protocolVersion: 3,
      proofKind: "secureEnclaveP256",
      challengeToken: token,
      expiresAt: .distantFuture
    )
  }

  private static func expiredRenewableSession() -> BackendSessionResponse {
    BackendSessionResponse(
      accessToken: "expired-access-token",
      expiresAt: Date(timeIntervalSince1970: 1_999),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource",
      protocolVersion: 3,
      sessionFamilyId: "family-1",
      refreshToken: "refresh-token-1",
      refreshTokenExpiresAt: Date(timeIntervalSince1970: 3_000),
      refreshTokenAbsoluteExpiresAt: Date(timeIntervalSince1970: 4_000)
    )
  }

  private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
      guard !isOpen else {
        return
      }

      await withCheckedContinuation { continuation in
        waiters.append(continuation)
      }
    }

    func open() {
      isOpen = true
      let currentWaiters = waiters
      waiters.removeAll()
      currentWaiters.forEach { $0.resume() }
    }
  }

  private final class AcceptingProofProvider: DeviceSessionProofProviding {
    private(set) var releasedHostedProofRequestIds: [String] = []
    private(set) var discardedRegisteredHostedKeyCount = 0
    private let refreshRequestHandler: (@MainActor (
      BackendSessionResponse,
      String,
      BackendAccessMode
    ) async throws -> SessionRefreshRequest)?

    init(refreshRequestHandler: (@MainActor (
      BackendSessionResponse,
      String,
      BackendAccessMode
    ) async throws -> SessionRefreshRequest)? = nil) {
      self.refreshRequestHandler = refreshRequestHandler
    }

    func hostedEnrollment(
      challenge: SessionChallengeResponse,
      installationId: String,
      signedTransactionInfo: String
    ) async throws -> HostedDeviceEnrollment {
      HostedDeviceEnrollment(
        requestId: "request-1",
        issuedAt: Date(timeIntervalSince1970: 2_000),
        challengeToken: challenge.challengeToken,
        keyId: "app-attest-key",
        proofKind: "attestation",
        proof: "raw-proof-secret"
      )
    }

    func markHostedEnrollmentSubmissionStarted(keyId: String, requestId: String) throws -> Bool { true }
    func markHostedEnrollmentRegistered(keyId: String, requestId: String) throws -> Bool { true }
    func resolveRejectedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardUnsubmittedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardDefinitivelyFailedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardRegisteredHostedKey() throws -> Bool {
      discardedRegisteredHostedKeyCount += 1
      return true
    }
    func releaseHostedProofOperation(requestId: String) -> Bool {
      releasedHostedProofRequestIds.append(requestId)
      return true
    }

    func selfHostedEnrollment(
      challenge: SessionChallengeResponse,
      installationId: String
    ) throws -> SelfHostedDeviceEnrollment {
      SelfHostedDeviceEnrollment(
        requestId: "request-1",
        issuedAt: Date(timeIntervalSince1970: 2_000),
        challengeToken: challenge.challengeToken,
        publicKey: "public-key",
        signature: "signature"
      )
    }

    func refreshRequest(
      session: BackendSessionResponse,
      installationId: String,
      mode: BackendAccessMode
    ) async throws -> SessionRefreshRequest {
      if let refreshRequestHandler {
        return try await refreshRequestHandler(session, installationId, mode)
      }

      return SessionRefreshRequest(
        installationId: installationId,
        refreshToken: session.refreshToken,
        requestId: "request-1",
        issuedAt: Date(timeIntervalSince1970: 2_000),
        proof: "proof"
      )
    }
  }

  private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
      lock.withLock { count }
    }

    func increment() {
      lock.withLock { count += 1 }
    }
  }

  private final class SequencedAppAttestClient: AppAttestClient {
    var isSupported = true
    var generatedKeyCount = 0
    var attestationResults: [Result<Data, Error>] = []
    var assertionResults: [Result<Data, Error>] = []
    var attestationStarted: (() -> Void)?
    var attestationGate: AsyncGate?

    func generateKey() async throws -> String {
      generatedKeyCount += 1
      return "key-\(generatedKeyCount)"
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
      attestationStarted?()
      if let attestationGate {
        await attestationGate.wait()
      }
      return try attestationResults.removeFirst().get()
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
      try assertionResults.removeFirst().get()
    }
  }
}
