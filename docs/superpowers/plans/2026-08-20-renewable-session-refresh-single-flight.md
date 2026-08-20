# Renewable Session Refresh Single-Flight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure every `AuthService` performs at most one renewable-session rotation for a given credential and cannot let a stale refresh result overwrite or delete a newer session.

**Architecture:** Add a MainActor-owned single-flight refresh operation keyed by connection configuration revision, backend mode, and session family. All concurrent recovery callers await the same task. Keep the backend's rotating-token reuse detection unchanged, and add client-side source-session guards so a late success or failure can mutate state only when the session it refreshed is still current.

**Tech Stack:** Swift 6, Swift concurrency/MainActor, XCTest, existing `AuthService`, `BackendSessionStore`, `DeviceSessionProofProviding`, and `PumpSyncAPIClient` abstractions.

**Spec:** `docs/superpowers/plans/2026-08-20-renewable-session-refresh-single-flight.md#root-cause-and-required-behavior`

## Global Constraints

- Self-hosted authentication must remain independent of Apple App Attest; the same single-flight mechanism covers both modes without adding Apple dependencies to self-hosted mode.
- Never retry `/v1/session/refresh` automatically because delivery may be ambiguous and the credential rotates on success.
- Never log refresh credentials, session-family identifiers, assertion bytes, installation identifiers, or access tokens.
- Preserve the backend's credential-reuse revocation policy and optimistic-concurrency checks.
- Preserve configuration-revision isolation: stale hosted or self-hosted work cannot commit after a mode or base-URL change.
- Keep marketing version `1.0.0`; increment `CFBundleVersion` only when publishing the completed implementation.

---

## Root Cause and Required Behavior

`AuthService` is isolated to `MainActor`, but `recoverSessionIfNeeded` is reentrant at each `await`. Two callers can therefore load the same expired `BackendSessionResponse`, independently create proofs over the same refresh token, and submit two `/v1/session/refresh` requests.

The backend intentionally rotates the credential using an optimistic `TryReplaceAsync` operation. One request wins. The other receives an authentication failure. Today, the losing client's `refreshRenewableSession` catch block treats that response as permanent and deletes `session` and `BackendSessionStore`, even if the winning request already saved the replacement. A later sequential use of the old credential can also trigger the backend's intentional family-reuse revocation.

Required behavior:

1. Concurrent recovery callers for the same configuration and session family share one proof generation and one network request.
2. Every waiter observes the shared result and the same final session.
3. A stale refresh completion may not overwrite or delete a newer same-configuration session.
4. Configuration changes still stop stale work.
5. Ambiguous failures retain the renewable credential and do not start enrollment.
6. Permanent rejection clears only the exact credential that was rejected.
7. Backend rotation and credential-reuse behavior remain unchanged.

---

### Task 1: Reproduce Concurrent Rotation and Stale-Failure State Loss

**Files:**
- Modify: `PumpSyncTests/AuthServiceTests.swift`

**Interfaces:**
- Consumes: `AuthService.accessTokenRecoveringIfNeeded(allowInteractiveRecovery:)`, `AsyncGate`, `AcceptingProofProvider`, `BackendSessionStore`.
- Produces: deterministic regression tests defining single-flight and stale-result behavior.

- [ ] **Step 1: Add a concurrent-success regression test**

Add `testConcurrentRenewableRecoveryUsesOneRefreshAndSharesReplacementSession`. Save `expiredRenewableSession()`, gate the refresh response, start two tasks, and count proof/request calls:

```swift
var proofCount = 0
var requestCount = 0
let requestCountLock = NSLock()
let refreshStarted = expectation(description: "refresh request started")
let allowRefreshResponse = DispatchSemaphore(value: 0)

let proofProvider = AcceptingProofProvider(refreshRequestHandler: { session, installationId, _ in
  proofCount += 1
  return SessionRefreshRequest(
    installationId: installationId,
    refreshToken: session.refreshToken,
    requestId: "shared-refresh-request",
    issuedAt: Date(timeIntervalSince1970: 2_000),
    proof: "proof"
  )
})

URLProtocolStub.requestHandler = { request in
  requestCountLock.withLock { requestCount += 1 }
  refreshStarted.fulfill()
  allowRefreshResponse.wait()
  let response = HTTPURLResponse(
    url: request.url!,
    statusCode: 200,
    httpVersion: nil,
    headerFields: ["Content-Type": "application/json"]
  )!
  return (response, try JSONCodec.encoder.encode(replacementSession))
}

async let first = service.accessTokenRecoveringIfNeeded(allowInteractiveRecovery: false)
async let second = service.accessTokenRecoveringIfNeeded(allowInteractiveRecovery: false)
await fulfillment(of: [refreshStarted], timeout: 1)
allowRefreshResponse.signal()
allowRefreshResponse.signal() // prevents the RED implementation's second request from hanging
let tokens = await (first, second)

XCTAssertEqual(proofCount, 1)
XCTAssertEqual(requestCountLock.withLock { requestCount }, 1)
XCTAssertEqual(tokens.0, replacementSession.accessToken)
XCTAssertEqual(tokens.1, replacementSession.accessToken)
XCTAssertEqual(sessionStore.loadValidSession(), replacementSession)
```

- [ ] **Step 2: Add a shared-failure regression test**

Add `testConcurrentRenewableRecoverySharesAmbiguousFailureWithoutEnrollment`. Return `URLError(.timedOut)` from the single refresh request, invoke two recovery callers, and assert one proof, one request, no subscription enrollment, and the original recoverable session remains stored.

- [ ] **Step 3: Add a stale-permanent-failure regression test**

Add `testRejectedRefreshDoesNotDeleteNewerSameConfigurationSession`. Gate a refresh using the expired credential, establish a replacement hosted session through the existing explicit subscription test seam without changing configuration, then release a 401 `invalid_token` response. Assert the replacement remains in memory and Keychain and that diagnostics record `reason=sessionSuperseded`.

- [ ] **Step 4: Run the three tests and capture RED**

Run:

```bash
xcodebuild test \
  -project PumpSync.xcodeproj \
  -scheme PumpSync \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:PumpSyncTests/AuthServiceTests/testConcurrentRenewableRecoveryUsesOneRefreshAndSharesReplacementSession \
  -only-testing:PumpSyncTests/AuthServiceTests/testConcurrentRenewableRecoverySharesAmbiguousFailureWithoutEnrollment \
  -only-testing:PumpSyncTests/AuthServiceTests/testRejectedRefreshDoesNotDeleteNewerSameConfigurationSession
```

Expected: the concurrent tests observe two proof/network attempts, and the stale 401 deletes the newer session.

- [ ] **Step 5: Commit the failing tests**

```bash
git add PumpSyncTests/AuthServiceTests.swift
git commit -m "test: reproduce concurrent session refresh"
```

---

### Task 2: Add MainActor Single-Flight Refresh Ownership

**Files:**
- Modify: `PumpSync/Sources/Auth/AuthService.swift`
- Modify: `PumpSyncTests/AuthServiceTests.swift`

**Interfaces:**
- Consumes: `BackendConfigurationStore.revision`, `BackendAccessMode`, `BackendSessionResponse.sessionFamilyId`, existing configuration guards.
- Produces: `RenewableRefreshOperationKey`, `runCoalescedRenewableRefresh(_:) async -> Bool`, and categorical coalescing diagnostics.

- [ ] **Step 1: Define the operation identity and state**

Add private MainActor-owned state beside the subscription-operation state:

```swift
private struct RenewableRefreshOperationKey: Equatable {
  let configurationRevision: Int
  let mode: BackendAccessMode
  let sessionFamilyId: String
}

private var renewableRefreshTask: Task<Bool, Never>?
private var renewableRefreshOperationID: UUID?
private var renewableRefreshOperationKey: RenewableRefreshOperationKey?
```

The key uses the non-secret family identifier already present in the session model, but diagnostics must never print it.

- [ ] **Step 2: Implement the single-flight helper**

Add:

```swift
private func runCoalescedRenewableRefresh(_ source: BackendSessionResponse) async -> Bool {
  let key = RenewableRefreshOperationKey(
    configurationRevision: configurationStore.revision,
    mode: configurationStore.mode,
    sessionFamilyId: source.sessionFamilyId
  )

  if let task = renewableRefreshTask,
     renewableRefreshOperationKey == key {
    diagnostics?.record(
      source: .auth,
      title: "Renewable session refresh coalesced",
      message: "coalesced=true"
    )
    return await task.value
  }

  if let task = renewableRefreshTask {
    _ = await task.value
    if let valid = session, sessionStore?.isValid(valid) == true {
      return true
    }
  }

  let operationID = UUID()
  let task = Task { @MainActor [weak self] in
    guard let self else { return false }
    let result = await self.refreshRenewableSession(source)
    if self.renewableRefreshOperationID == operationID {
      self.renewableRefreshTask = nil
      self.renewableRefreshOperationID = nil
      self.renewableRefreshOperationKey = nil
    }
    return result
  }
  renewableRefreshOperationID = operationID
  renewableRefreshOperationKey = key
  renewableRefreshTask = task
  return await task.value
}
```

During implementation, keep cleanup in a `defer`-equivalent helper or an explicit path that executes for success, failure, and cancellation. Do not allow an old task to clear a newer task's fields; retain the `operationID` equality check.

- [ ] **Step 3: Route recovery through the helper**

Replace:

```swift
if await refreshRenewableSession(recoverableSession) {
```

with:

```swift
if await runCoalescedRenewableRefresh(recoverableSession) {
```

- [ ] **Step 4: Invalidate operation ownership on connection changes**

In `clearSessionForConnectionChange`, clear the operation ID, key, and task reference. Do not interpret cancellation as proof that the backend did not receive a request; existing configuration-generation guards remain authoritative for preventing stale commits.

- [ ] **Step 5: Run the concurrent tests and capture GREEN**

Run the Task 1 command. Expected: one proof, one network request, shared success/failure, and no enrollment fallback.

- [ ] **Step 6: Run existing configuration-isolation tests**

Run:

```bash
xcodebuild test \
  -project PumpSync.xcodeproj \
  -scheme PumpSync \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:PumpSyncTests/AuthServiceTests/testRenewableRefreshStopsBeforeRequestIfConfigurationChangesDuringProof \
  -only-testing:PumpSyncTests/AuthServiceTests/testRenewableRefreshFailureDoesNotClearAReplacementConnection
```

Expected: both tests pass without weakening mode/base-URL isolation.

- [ ] **Step 7: Commit single-flight behavior**

```bash
git add PumpSync/Sources/Auth/AuthService.swift PumpSyncTests/AuthServiceTests.swift
git commit -m "fix: coalesce renewable session refresh"
```

---

### Task 3: Guard Session Commits by Source Credential

**Files:**
- Modify: `PumpSync/Sources/Auth/AuthService.swift`
- Modify: `PumpSyncTests/AuthServiceTests.swift`

**Interfaces:**
- Consumes: the `BackendSessionResponse` passed into `refreshRenewableSession` and the current in-memory session.
- Produces: `isCurrentRefreshSource(_:)` and safe `sessionSuperseded` handling.

- [ ] **Step 1: Add an exact source-session predicate**

Add:

```swift
private func isCurrentRefreshSource(_ source: BackendSessionResponse) -> Bool {
  guard let current = session else { return false }
  return current.protocolVersion == source.protocolVersion
    && current.serviceMode == source.serviceMode
    && current.sessionFamilyId == source.sessionFamilyId
    && current.refreshToken == source.refreshToken
}
```

This comparison remains in memory and must not be included in diagnostic text.

- [ ] **Step 2: Guard the success commit**

After validating the refreshed response but before assigning `session` or saving Keychain state:

```swift
guard isCurrentRefreshSource(currentSession) else {
  diagnostics?.record(
    source: .auth,
    title: "Renewable session refresh stopped",
    message: "reason=sessionSuperseded"
  )
  return isSignedIn
}
```

- [ ] **Step 3: Guard failure mutation**

In the catch block, after the configuration checks and before clearing or restoring state, apply the same source predicate. A stale failure returns the current sign-in state and does not modify `session`, `sessionStore`, `errorMessage`, or `statusMessage`.

- [ ] **Step 4: Verify permanent rejection still clears the exact rejected session**

Add `testPermanentRefreshRejectionClearsCurrentSourceSession`. Return a 401 while no replacement is installed and assert in-memory and persisted session state are cleared.

- [ ] **Step 5: Run source-guard tests**

Run:

```bash
xcodebuild test \
  -project PumpSync.xcodeproj \
  -scheme PumpSync \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:PumpSyncTests/AuthServiceTests/testRejectedRefreshDoesNotDeleteNewerSameConfigurationSession \
  -only-testing:PumpSyncTests/AuthServiceTests/testPermanentRefreshRejectionClearsCurrentSourceSession
```

Expected: stale rejection preserves the replacement; current-source rejection clears only the rejected credential.

- [ ] **Step 6: Commit source-session guards**

```bash
git add PumpSync/Sources/Auth/AuthService.swift PumpSyncTests/AuthServiceTests.swift
git commit -m "fix: ignore stale refresh results"
```

---

### Task 4: Verify Security, Diagnostics, and Full Regression Coverage

**Files:**
- Modify only if a failing test exposes a defect: `PumpSync/Sources/Auth/AuthService.swift`
- Modify only if coverage needs correction: `PumpSyncTests/AuthServiceTests.swift`

**Interfaces:**
- Consumes: completed single-flight and source-session guards.
- Produces: release evidence and a clean frontend worktree.

- [ ] **Step 1: Run all authentication tests**

```bash
xcodebuild test \
  -project PumpSync.xcodeproj \
  -scheme PumpSync \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:PumpSyncTests/AuthServiceTests \
  -only-testing:PumpSyncTests/DeviceSessionProofProviderTests \
  -only-testing:PumpSyncTests/PumpSyncAPIClientTests \
  -only-testing:PumpSyncTests/JSONCodecTests
```

Expected: all affected tests pass.

- [ ] **Step 2: Verify no credential material was added to diagnostics**

```bash
git diff -- PumpSync/Sources/Auth/AuthService.swift | rg -n 'refreshToken|sessionFamilyId|accessToken|diagnostics'
```

Review each match. Expected: identifiers appear only in comparisons/operation keys; diagnostic messages contain categorical fields such as `coalesced=true` and `reason=sessionSuperseded`.

- [ ] **Step 3: Run the complete iOS suite**

```bash
xcodebuild test \
  -project PumpSync.xcodeproj \
  -scheme PumpSync \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
```

Expected: unit and UI suites pass with zero failures.

- [ ] **Step 4: Run final repository checks**

```bash
git diff --check
git status --short
git rev-list --left-right --count HEAD...@{upstream}
```

Expected: no whitespace errors; only intended plan/implementation files differ; branch state is explicitly recorded before publication.

- [ ] **Step 5: Commit any test-driven corrections**

If Step 1 or Step 3 required a scoped correction:

```bash
git add PumpSync/Sources/Auth/AuthService.swift PumpSyncTests/AuthServiceTests.swift
git commit -m "test: harden renewable refresh concurrency"
```

If no correction was required, do not create an empty commit.

---

## Deliberate Non-Changes

- Do not make `/v1/session/refresh` retryable.
- Do not weaken backend credential-reuse revocation.
- Do not persist refresh-operation state across launches; a process death during delivery remains an ambiguous outcome and the existing credential-preservation behavior applies.
- Do not add a general-purpose task queue or refactor subscription enrollment coalescing.
- Do not change backend wire contracts, database schema, App Attest payloads, privacy disclosures, or self-hosted cryptography.

## Acceptance Criteria

- Two simultaneous recovery calls produce exactly one proof and one HTTP refresh request.
- Both callers receive the same replacement access token after success.
- An ambiguous shared failure preserves the original renewable session and does not enroll.
- A stale success or failure cannot mutate a newer session, even within the same configuration revision.
- A permanent rejection still clears the exact current source credential.
- Configuration-change tests, authentication tests, and the complete iOS suite remain green.
- Diagnostics prove coalescing/supersession categorically without credential material.
