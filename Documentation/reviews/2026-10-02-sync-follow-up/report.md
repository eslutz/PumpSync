# Sync notification and Tandem failure follow-up

## Notification change

The running banner now uses a 44-point X dismissal control with an accessible label. Dismissal updates only notification visibility, preserving the running operation, its task and Sync button animation. Hidden progress remains hidden between phases and across tabs. A completion/failure or a new operation is a new notification; existing actionable recovery buttons and the eight-second success timeout remain.

Tests cover an actually suspended download and Health writer: dismissal keeps the operation running through download/save, allows confirmed success and metadata updates, and preserves the result after its notification is dismissed. A simulator UI regression checks the X, removal of View, disabled Syncing button and cross-tab persistence. Existing screenshot fixtures were reused; no new shipping fixture hook was introduced. The full iOS warning gate passed 291 unit tests and 15 UI tests with zero failures or warning matches. Raw log: /private/tmp/pumpsync-banner-dismiss-full.log. [Inspected running banner](01-running-banner-dismiss-control.jpg) shows the X and active Syncing icon using the pre-existing Debug simulator screenshot fixture; displayed records/status are fixture data, not physical Health or authentication evidence. Runtime accessibility snapshots returned no targets, so dismissal behavior is established by the passing XCUI regression rather than a manual runtime tap.

## Reported real sync failure

The supplied support bundle identifies app 1.0.0 (33), successful App Attest/session acquisition, repeated manual/app-open sync rejection on 2026-10-02, and last successful sync at 2026-09-28T18:43:53Z. Returned/imported counts (250/43) are prior-success metadata, not proof of a successful current request. Background scheduling messages do not establish background task execution.

Read-only Azure inspection on 2026-10-02 found the nonproduction API latest ready revision 0000046 tagged with backend commit d4fa7cbeba8df6dda6444e2f3dc016429c176ed3; ingress routes 100 percent to the latest revision. That commit classifies Tandem rejection and adds safe diagnostics. The change is deployed, but it does not repair the underlying upstream rejection.

Allowlisted AppTraces fields between 09:38 and 09:44 UTC show seven first-attempt failures at bff_pump_logs, HTTP 400, JSON response, ErrorCategory=unclassified. The final trace at 09:43:02 UTC matches the supplied final error time. No credentials, raw response, request URL, device identifier or Health reading were retrieved by these queries. Authentication/session issuance succeeded; the rejected step is pump-log retrieval. The exact upstream reason remains unresolved. No source change is claimed to fix it and no backend deployment was performed.

The earlier user-confirmed four-point real-data pass is retained as a reported observation, but this newer failure evidence prevents treating it as current successful sync or acceptance of the uninstalled local preview candidate. Candidate-specific authenticated device acceptance remains pending.

## Next diagnostic gate

Determine the upstream pump-log request rejection from safe request-shape metadata and an allowlisted error classification, comparing the implemented request with the current Tandem contract. Do not infer a root cause from HTTP 400 alone or collect raw private account/pump payloads. Any private-account reproduction, device candidate installation or real Health import requires the separate authorization already identified in the access plan.

## Root-cause update — 2026-10-02

The user confirms direct Tandem Source login and current reports succeed. The original `eslutz/tconnectsync` fork points to `jwoglom/tconnectsync`; upstream [issue 163](https://github.com/jwoglom/tconnectsync/issues/163) and [fix 7c42ed3](https://github.com/jwoglom/tconnectsync/commit/7c42ed35959a4095324bf20af65e4e46cf6e5d58) identify the October 1 rename of `eventIds` to `eventCodes`. PumpSync still sent the rejected key. This identifies the request-contract root cause and supersedes the earlier unresolved diagnosis above. It does not establish deployed recovery.

The outgoing key is corrected locally, with a regression that reproduced HTTP 400 before the fix. Current candidate Release build passes with zero warnings/errors; all 302 tests pass. A separate patch/image based on the deployed backend excludes all pending preview work and passes 268 tests plus startup/access smoke. Backend-owned evidence and the scoped release plan are in [Tandem compatibility](../../../../PumpSync.backend/docs/tandem-source-compatibility.md). Publishing/deploying the isolated hotfix and confirming one legitimate device sync remain pending authorization and execution. No new iOS build, credential reset or Health cleanup is needed for the backend request correction.
