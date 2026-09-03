# Subscription Renewal Resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve a valid renewable device credential when hosted sync is denied only because the subscription entitlement is inactive, allowing later background attempts to resume automatically after renewal while the backend continues to deny data access until entitlement is active.

**Architecture:** Keep authentication validity and subscription authorization as separate states. The iOS app retains the protocol 3 renewable session for `active_subscription_required`, records that subscription attention is required, and retries during later iOS-granted background opportunities. The backend remains the enforcement authority: every protected request rechecks stored entitlement, and App Store Server Notifications can reactivate it without minting a new device credential.

**Tech Stack:** Swift 6, SwiftUI, StoreKit 2, XCTest, .NET 10, xUnit, Azure Table Storage

**Spec:** `docs/superpowers/plans/2026-09-03-subscription-renewal-resilience.md#behavioral-contract`

## Global Constraints

- Do not weaken or bypass the backend subscription check.
- Preserve renewable credentials only for `401 active_subscription_required`; generic `401`/`403`, revoked sessions, invalid tokens, and device-proof failures retain their existing clearing or re-enrollment behavior.
- Background recovery must not call `AppStore.sync()` or present interactive StoreKit UI.
- Foreground purchase and restore remain the interactive repair paths when no active StoreKit entitlement exists.
- Subscription and generic warning banners retain the same dismissal action and close-button location.
- Do not schedule work around a StoreKit expiration date; it is a renewal boundary, not necessarily cancellation.
- Keep `project.yml` as the Xcode source of truth; do not edit the generated project manually.

## Behavioral contract

1. `active_subscription_required` marks hosted subscription access unavailable but preserves the access token, refresh credential, App Attest registration, and Keychain session.
2. The current sync fails with the existing dismissible “Subscription required” banner and “View Subscription” action.
3. Later foreground or iOS-granted background attempts may reuse or refresh the retained renewable session, but the backend continues rejecting sync while entitlement is inactive.
4. If App Store Server Notifications restore backend entitlement, the next protected request can succeed without foreground StoreKit interaction.
5. If StoreKit exposes a renewed current entitlement, foreground recovery may establish a replacement subscription session and retry once.
6. Generic authentication failures continue clearing invalid sessions; unrelated failure behavior remains unchanged.
7. Diagnostics distinguish “subscription access unavailable; credential retained” from “authentication session expired.”

## File map

- Modify `PumpSync/Sources/Auth/AuthService.swift`: preserve renewable state during access-denied recovery and expose subscription-attention state separately.
- Modify `PumpSync/Sources/Sync/SyncCoordinator.swift`: classify subscription authorization separately and record retry diagnostics.
- Modify `PumpSyncTests/AuthServiceTests.swift`: cover retained credentials, foreground repair, and genuine authentication rejection.
- Modify `PumpSyncTests/SyncCoordinatorTests.swift`: cover repeated background attempts and server-side renewal.
- Modify `../PumpSync.backend/tests/PumpSync.Tests/BackendAccessGuardTests.cs`: prove retained credentials cannot bypass entitlement enforcement.
- Modify `../PumpSync.backend/tests/PumpSync.Tests/HandleAppStoreNotificationUseCaseTests.cs`: prove renewal notifications reactivate entitlement state.
- Modify `../PumpSync.wiki/Features-and-Modes.md`: document authentication versus authorization.
- Modify `docs/app-store/release-preparation.md`: add a physical-device verification sequence.

---

### Task 1: Preserve renewable authentication during subscription denial

**Files:**
- Modify: `PumpSync/Sources/Auth/AuthService.swift`
- Test: `PumpSyncTests/AuthServiceTests.swift`

**Interfaces:**
- Consumes: `APIClientError.isActiveSubscriptionRequired`, `BackendSessionStore.isRenewable(_:)`, and `recoveryRequiresActiveSubscription`.
- Produces: `recoverHostedSubscriptionAfterAccessDenied(policy:) -> Bool` that preserves a renewable session when entitlement is missing and returns `true` only after access is restored.

- [ ] **Step 1: Add failing preservation tests**

Seed a hosted `BackendSessionResponse` with a nonexpired refresh credential, make entitlement lookup throw `StoreKitSubscriptionError.noActiveSubscription`, invoke access-denied recovery, and assert:

```swift
XCTAssertFalse(recovered)
XCTAssertTrue(service.isSignedIn)
XCTAssertTrue(service.requiresSubscriptionAction)
let saved = try XCTUnwrap(store.loadRecoverableSession())
XCTAssertEqual(saved.refreshToken, original.refreshToken)
```

Add companion tests proving an already nonrenewable session is not falsely retained and generic authentication rejection still deletes the invalid session.

- [ ] **Step 2: Run the focused tests and confirm the current deletion behavior fails them**

```bash
xcodebuild test -project PumpSync.xcodeproj -scheme PumpSync \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:PumpSyncTests/AuthServiceTests
```

Expected: the preservation test fails because the missing-entitlement catch currently deletes the Keychain session.

- [ ] **Step 3: Add an explicit preservation policy**

Introduce a private disposition rather than inferring behavior from foreground/background alone:

```swift
private enum MissingEntitlementDisposition {
  case clearUnusableSession
  case preserveRenewableSession
}
```

Pass `.preserveRenewableSession` only from `recoverHostedSubscriptionAfterAccessDenied(policy:)`. In the `noActiveSubscription` catch, retain the in-memory and stored session only when `sessionStore.isRenewable(_:)` is true; set `recoveryRequiresActiveSubscription = true` in both branches. Do not treat the retained token as proof of subscription access.

- [ ] **Step 4: Add precise diagnostics**

Record a warning with categorical fields and no credential data:

```swift
diagnostics?.record(
  source: .auth,
  severity: .warning,
  title: "Subscription access unavailable",
  message: "credentialRetained=\(credentialRetained) policy=\(policy.diagnosticName) retry=nextGrantedTask"
)
```

Ensure successful subscription-session establishment clears `recoveryRequiresActiveSubscription` and retains the existing success event.

- [ ] **Step 5: Run AuthService tests**

Run the focused command from Step 2. Expected: PASS, including existing single-flight, re-enrollment, and configuration-change cases.

- [ ] **Step 6: Commit the authentication-state change**

```bash
git add PumpSync/Sources/Auth/AuthService.swift PumpSyncTests/AuthServiceTests.swift
git commit -m "fix: preserve renewable session during subscription lapse"
```

---

### Task 2: Retry safely from later background opportunities

**Files:**
- Modify: `PumpSync/Sources/Sync/SyncCoordinator.swift`
- Test: `PumpSyncTests/SyncCoordinatorTests.swift`

**Interfaces:**
- Consumes: `AuthService.recoverHostedSubscriptionAfterAccessDenied(policy:)`, `AuthService.requiresSubscriptionAction`, and `APIClientError.isActiveSubscriptionRequired`.
- Produces: repeated BGTask attempts that remain backend-gated and automatically succeed after entitlement renewal.

- [ ] **Step 1: Replace the stale clearing expectation**

Rename `testHostedSyncWithExpiredSubscriptionClearsSessionAndOffersSubscription` to describe retention. Seed a genuinely renewable stored session and assert the sync fails with `.openSubscription` while the session remains recoverable.

- [ ] **Step 2: Add a failing two-opportunity background test**

Model two iOS-granted attempts. Return `active_subscription_required` first, then a successful sync response representing backend entitlement restored by an App Store notification:

```swift
XCTAssertFalse(firstResult)
XCTAssertTrue(authService.requiresSubscriptionAction)
XCTAssertTrue(secondResult)
XCTAssertFalse(authService.requiresSubscriptionAction)
XCTAssertEqual(syncRequestCount.value, 2)
XCTAssertEqual(subscriptionSessionRequestCount.value, 0)
```

Use `.background` and prove the recovery path does not invoke interactive StoreKit lookup or enrollment.

- [ ] **Step 3: Keep the current user-facing warning behavior**

On `active_subscription_required`, use access-denied recovery and never call `clearSessionForAuthenticationFailure()`. Retain:

```swift
SyncFailure(
  message: "Your PumpSync subscription isn’t active. Subscribe or renew to resume syncing.",
  recovery: .openSubscription
)
```

Do not alter `SyncStatusBanner`; its shared trailing dismiss button and `dismissResult()` action already cover subscription and generic warnings.

- [ ] **Step 4: Confirm retry and failure boundaries**

Add or retain tests proving `invalid_token` clears the session, subscription denial preserves it, foreground recovery retries once, background recovery does not invoke `AppStore.sync()`, and later success clears the stale warning.

- [ ] **Step 5: Run coordinator and banner tests**

```bash
xcodebuild test -project PumpSync.xcodeproj -scheme PumpSync \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:PumpSyncTests/SyncCoordinatorTests \
  -only-testing:PumpSyncTests/SyncViewTests
```

Expected: PASS.

- [ ] **Step 6: Commit the retry behavior**

```bash
git add PumpSync/Sources/Sync/SyncCoordinator.swift PumpSyncTests/SyncCoordinatorTests.swift
git commit -m "fix: retry sync after subscription renewal"
```

---

### Task 3: Lock down backend enforcement and renewal transitions

**Files:**
- Test: `../PumpSync.backend/tests/PumpSync.Tests/BackendAccessGuardTests.cs`
- Test: `../PumpSync.backend/tests/PumpSync.Tests/HandleAppStoreNotificationUseCaseTests.cs`

**Interfaces:**
- Consumes: `BackendAccessGuard.EnsureAccessAsync(...)`, `HandleAppStoreNotificationUseCase.ExecuteAsync(...)`, and `IBillingEntitlementRepository`.
- Produces: regression proof that credential retention cannot bypass an inactive entitlement and a verified renewal can restore access for the same subject.

- [ ] **Step 1: Add the enforcement regression test**

Create an active renewable device session and authenticated user but return no active billing entitlement:

```csharp
await Assert.ThrowsAsync<ActiveSubscriptionRequiredException>(
    () => guard.EnsureAccessAsync(user, CancellationToken.None));
```

Name the test to state that an active session does not bypass an expired subscription.

- [ ] **Step 2: Add the renewal-notification transition test**

Queue an expired transaction followed by a newer active transaction for the same original transaction ID. Execute both verified notifications and assert the repository returns the newer active entitlement. Retain idempotency coverage for duplicate notification UUIDs.

- [ ] **Step 3: Run focused backend tests**

```bash
dotnet test PumpSync.Backend.slnx --configuration Release \
  --filter "FullyQualifiedName~BackendAccessGuardTests|FullyQualifiedName~HandleAppStoreNotificationUseCaseTests"
```

Expected: PASS without backend production-code changes. If this exposes an actual notification-ordering defect, stop and revise the design before altering persistence logic.

- [ ] **Step 4: Commit backend contract tests separately**

```bash
git add tests/PumpSync.Tests/BackendAccessGuardTests.cs tests/PumpSync.Tests/HandleAppStoreNotificationUseCaseTests.cs
git commit -m "test: lock subscription renewal enforcement"
```

---

### Task 4: Document behavior and release proof

**Files:**
- Modify: `../PumpSync.wiki/Features-and-Modes.md`
- Modify: `docs/app-store/release-preparation.md`

**Interfaces:**
- Consumes: completed frontend behavior and unchanged backend enforcement.
- Produces: an operator-readable explanation and repeatable TestFlight validation.

- [ ] **Step 1: Update the authentication narrative**

Document that a renewable session authenticates the installation but does not authorize subscription-backed access by itself. State that subscription denial preserves the credential, protected endpoints continue checking entitlement, and later BGTasks can resume after verified renewal.

- [ ] **Step 2: Add the TestFlight checklist**

Require this evidence:

1. Successful foreground sync establishes the baseline.
2. Sandbox expiration produces `active_subscription_required` without “Connection session expired.”
3. The bundle still reports protocol 3/App Attest and finite refresh expiries after denial.
4. A later granted task reaches session refresh or Tandem sync rather than stopping with `renewableCredential=false`.
5. Azure returns `401` while entitlement remains inactive.
6. After verified renewal, a later attempt succeeds with a matching durable `SyncAttempts` record.

- [ ] **Step 3: Commit documentation in each owning repository**

```bash
git add docs/app-store/release-preparation.md
git commit -m "docs: add subscription renewal resilience checks"
```

```bash
git add Features-and-Modes.md
git commit -m "docs: explain subscription renewal recovery"
```

---

### Task 5: Full validation and release handoff

**Files:**
- Verify: `project.yml`
- Regenerate: `PumpSync.xcodeproj/` only through XcodeGen if configuration changed

**Interfaces:**
- Consumes: all completed tasks.
- Produces: locally validated commits ready for a separately authorized push and deployment.

- [ ] **Step 1: Regenerate and inspect the Xcode project**

```bash
xcodegen generate
xcodebuild -list -project PumpSync.xcodeproj
```

Do not increment the build number unless a TestFlight build is requested. If incremented, update `project.yml`, regenerate, and confirm generated `CURRENT_PROJECT_VERSION` matches.

- [ ] **Step 2: Run the complete frontend test suite**

```bash
xcodebuild test -project PumpSync.xcodeproj -scheme PumpSync \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
git diff --check
```

Expected: all tests pass and no whitespace errors are reported.

- [ ] **Step 3: Run the complete backend suite**

From `../PumpSync.backend`:

```bash
dotnet build PumpSync.Backend.slnx --configuration Release
dotnet test PumpSync.Backend.slnx --configuration Release
git diff --check
```

Expected: build and tests pass with warnings treated as errors.

- [ ] **Step 4: Review repository boundaries**

Confirm frontend changes exist only in `PumpSync.frontend`, backend tests only in `PumpSync.backend`, and narrative documentation only in `PumpSync.wiki`. Record each repository’s branch, commit SHA, and ahead/behind state separately.

- [ ] **Step 5: Perform physical-device validation before claiming completion**

Use a TestFlight sandbox subscription cycle and report build identity, iOS BGTask lifecycle, Application Insights requests, and durable `SyncAttempts` separately. Simulator tests or backend requests alone do not prove automatic background resumption.

## Out of scope

- Predictive “subscription expires soon” notifications.
- Forced background execution at the StoreKit renewal boundary.
- Extending or bypassing inactive subscription access.
- App Store pricing, renewal duration, grace-period, or billing-retry changes.
- Push, backend deployment, or TestFlight deployment without separate execution authorization.
