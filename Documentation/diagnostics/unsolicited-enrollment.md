# Unsolicited subscription enrollment lifecycle

## November 8, 2026

Investigation of build 54 found an independent subscription enrollment alongside a
successful background import. The backend established a session, while the client
later reported a connection-operation timeout on foreground resume. StoreKit update
handling was the likely initiator, but old logs lacked an origin field. OS suspension
was consistent with the delayed report, not directly proven. `backendMs` measured
client wall time, not server processing time.

## Behavior

Verified active StoreKit updates are still finished promptly. Unsolicited enrollment
is deferred if the existing session is usable or no active foreground scene owns it.
Deferral does not mark the transaction as an attempted enrollment. Foreground bootstrap
and bounded sync recovery obtain current StoreKit entitlement when access is needed;
no raw transaction is persisted as a deferred queue. Explicit purchase/restore and
revocation handling retain their existing behavior.

An unsolicited request that is needed in the foreground has a process-local UUID and
an owned task. Leaving the active scene cancels its waiter. The existing coalescing
rules preserve a shared request when another caller still owns it. A canceled submitted
request retains existing ambiguous-outcome reconciliation; a late confirmed response
can still be securely committed. Task cancellation cannot recall an already-sent request.

Session usability is rechecked after queued subscription work, renewable refresh, and
acquiring the auth mutation lease, before generating/submitting another proof. A
successful refresh therefore avoids redundant unsolicited enrollment.

## Diagnostics

New categorical events identify `origin=storeKitUpdate`, owner start/end, foreground
state, and deferral reason (`usableSession`, `notForeground`, `foregroundEnded`, or
usability restored while waiting). Cancellation is informational, not a connection
failure warning. Subscription start/timing events identify the origin and owner.
Request diagnostics record the expected deadline and, on timeout, observation time
and overdue milliseconds. `clientElapsedMs` replaces `backendMs` in subscription-session
timing and includes any time the process was suspended; it is not server latency.
Other connection flows use `origin=connectionRecovery`; this does not distinguish
purchase/restore from sync recovery. No transaction, token, health reading, or account
identifier is added to these fields. Existing bounded local diagnostic retention and
user-controlled support export remain in use.

## Tests and acceptance

Regression tests cover background deferral without consuming the update, preserving
a usable session, canceling an in-flight unsolicited request when foreground ownership
ends without publishing a connection error, preserving another waiting owner's request,
and stopping redundant queued updates after another update creates a usable session.
Existing tests retain purchase/restore, revocation, proof serialization, ambiguous
outcome reconciliation, foreground recovery, and background sync coverage.

The first two regression tests failed against the old behavior. The initial focused
run exposed two sync fixtures without explicit foreground ownership; those fixtures
now supply the same lifecycle state as the app. A shared-owner test initially expected
one request, but explicit Restore intentionally queues its own operation after joining;
that expectation was corrected without changing Restore behavior.

Physical-device acceptance still requires normal background use and support-bundle
correlation. Scheduling gaps alone are not classified as failures. The existing
12-hour check-ins continue to the original 72-hour endpoint and should distinguish
observations from build 54 and the subsequent lifecycle-fix build.

## Local validation and release hold

- Four targeted lifecycle regressions passed (`/private/tmp/pumpsync-enrollment-regressions.log`).
- The final auth source passed 435 unit tests in both full compact-device preflights.
- First full preflight: native accessibility audit timed out (`Code=-56`) on Data Handling.
  Preserved in `TestResults/cloud-20261108T121829Z/`.
- After a scoped restart of the isolated validation simulator, the next preflight
  reported contrast on the existing Remove Credentials control. Preserved in
  `TestResults/cloud-20261108T122446Z/`.
- A temporary darker destructive tint cleared that contrast finding, but the focused
  native audit then reported seven hit-region failures on generic SwiftUI accessibility
  nodes. All seven failure screenshots show Developer; no individual element or frame
  was supplied. The screenshots alone do not establish which controls are undersized.
  Result: `/private/tmp/pumpsync-enrollment-contrast-fix.xcresult`; exported evidence:
  `/private/tmp/pumpsync-enrollment-hit-evidence/`.
- The temporary tint adjustment was reverted to keep this change scoped to enrollment.
  No accessibility issues were suppressed, tests relaxed, or unchanged runs retried
  until success. The required release preflight has not passed, so no new build is
  authorized by its gates. No commit, push, or Cloud deployment was performed.

The repaired Internal Beta workflow was verified live on Latest Release Xcode 27.2
(`27B52`), iPhone SE / Latest from Selected Xcode (currently iOS 27.2), with an
`INTERNAL_ONLY` archive. It remains available after the local gate is resolved.
Existing 12-hour build-54 monitoring continues unchanged to its original endpoint.

## Subsequent UI-audit waiver and baseline comparison

The user subsequently waived the all-checks-pass requirement for UI issues already
present in build 54, while deferring separate UI work. UI views, styles, UI tests,
and project configuration are byte-for-byte unchanged from build 54 (`cb989f7`).
No temporary contrast adjustment is included. Recorded hit-area audit failures from
November 7 predate this enrollment fix (`/private/tmp/pumpsync-sync-diagnostics-full.log`).

An exact build-54 source snapshot was tested once in the same compact simulator;
its native accessibility audit passed on this run. Evidence:
`/private/tmp/pumpsync-build54-baseline-audit.xcresult`. This does not reproduce every
finding or prove every root cause is pre-existing. The audit results vary between
runs; that uncertainty is explicitly retained. The waiver is applied only to the
recorded native accessibility-audit class, not new auth/sync failures or other UI
regressions. Tests and workflow requirements have not been edited or suppressed.

Current-source foreground recovery, inline sync/tab navigation, and sync status on
pushed settings destinations all passed (3 UI tests). Result bundle:
`/private/tmp/pumpsync-enrollment-lifecycle-ui.xcresult`; raw log:
`/private/tmp/pumpsync-enrollment-lifecycle-ui.log`. All 435 unit tests passed on the
final auth source. `git diff --check` passed. The internal Cloud workflow will still
run its complete test suite and archive; distribution evidence will distinguish a
clean hosted result from any audit finding covered by this waiver.

## Hosted build 55 and pending distribution decision

Lifecycle implementation `ca307c415c33586f3f185705fc48ec16aa7573d6` was committed
and pushed. Internal Beta run 55 (`fdbcaa73-d214-4bcb-b91e-69bddd03869c`) archived
successfully and processed build `2f114a33-ae00-48aa-9d3f-1b107e029a3d` as VALID.
Hosted results: 471/472 tests passed; the sole failure was
`PumpSyncUITests.testVoiceOverDiagnosticsAndSourceData`: "VoiceOver could not reach
Clear Logs". The native core-screen accessibility audit passed in this hosted run.
Automatic Internal TestFlight distribution was skipped because the test action failed.
No manual distribution was performed.

The exact build-54 source passed the VoiceOver test in a single local baseline run
(`/private/tmp/pumpsync-build54-voiceover-baseline.xcresult`). This baseline used
SE / iOS 27.0, while Cloud used SE / iOS 27.2. The UI views/styles/tests/configuration
are unchanged, but these results cannot establish that the hosted failure is
pre-existing or exclude interaction with new lifecycle logging. No unchanged runs
were repeated to obtain a pass. The user was asked whether to extend the conditional
waiver to this specific unattributed UI failure. Build 55 is held for that decision.
Current-source unit tests and all other hosted tests passed; release notes are saved.
The existing 12-hour monitoring continues on the last confirmed installed build 54.
