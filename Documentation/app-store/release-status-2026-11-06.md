# Invite-only external beta continuation — November 6, 2026

This record supersedes conflicting scope and readiness wording in the November 5 chronology. External TestFlight is not submitted or distributed. Production deployment and App Store release are a later phase.

## Authorized scope

- Keep support-operated email deletion. Do not add an in-app deletion API or UI in this phase. Apple's account-rule applicability to the installation-bound identity remains unconfirmed; do not describe it as a conclusively required new feature.
- A request identified by installation ID covers that installation only. Preserve entitlements used by other installations.
- Completed deletion audits retain only completion time, outcome, counts, and a keyed installation hash for 30 days. Remove transaction IDs and recovery details on completion; pending recovery records must not expire automatically.
- Eric handles agreement acceptance. After his fresh sign-in, App Store Connect showed the Free Apps agreement Active and the Paid Apps agreement Active (New Agreement Available), with View and Agree to Terms still offered. Paid agreement acceptance remains open.
- Eric authorized sending the existing reviewer-access inquiry to Apple and implementing only the arrangement Apple accepts. A materially different arrangement requires his decision.
- Use the existing invite-only external group. Keep the public link disabled and add no further testers without Eric's approval.
- Coordinate a non-destructive session on Eric's existing iPhone after backend gates pass. No reinstall, reset, credential removal, or deletion of Health samples; test backend deletion only with synthetic fixtures.

## Integrated source

| Component | Integration | Verified revision |
| --- | --- | --- |
| Frontend routing and light-mode store assets | PR #4 merged after hosted checks passed | `c323dbec5f164272d750d8abd46494d7b1c2792d` |
| Backend bootstrap and pre-publication readiness guard | PR #5 merged after hosted checks passed | `5dcf77e6712633156807736653f9d5778364eb40` |
| Website markdown parser security update | PR #11 merged; local suite previously passed | `d2968d4689eca87ac449bd121206b99c8f82825a` |
| Wiki beta/review guidance | Signed commits published to wiki master | `b176720` |

Frontend evidence remains the pinned 445-test pass plus both actual text-size recovery checks and source-hash verification in `TestResults/cloud-20261105T215225Z/`; the merged code also passed hosted CI. No candidate Cloud workflow was started. Native light-mode store media was processed and verified, and the nine superseded dark iPhone screenshots were permanently deleted with Eric's confirmation.

## Deletion work in progress

Backend PR #6 remains a draft. Signed commit `36e5e18` adds persisted pre-deletion inventories for SQLite and Azure Table Storage, recovery after link removal, shared-entitlement inventory exclusion, atomic completion/audit replacement, removal of transaction identifiers from new completion audits, and hourly expiry of completion audits at 30 days. Hosted backend CI passed for `36e5e18`. The full Release suite passed 365 tests with zero failures/skips; the local container build passed and version/revision labels were verified. Synthetic tests cover interruption stages, audit failure, restart, competing initial snapshots, idempotent completion, size limits, and pending-record preservation. Azure Table transaction tests use an in-memory SDK test double rather than a live Azure service.

This is not a complete concurrent-deletion solution. The scoped, cross-process write barrier, generation-aware reconnect/retry behavior, pending-operation monitoring, full concurrent-enrollment tests, and real Azure service acceptance remain outstanding. Do not merge or deploy PR #6 until those gates pass. Website privacy PR #10 remains unpublished pending reconciliation with final backend behavior.

## External blockers and next gates

Apple's contact service initially redirected to maintenance. After Eric restored sign-in, the authorized inquiry was submitted through App Review → Other App Review questions → Email on November 6. Apple confirmed case **30000007388462**. The request covers the isolated demonstration proposal, initial external TestFlight review, and the first App Store submission. Receipt is not approval; wait for the written decision before implementing the replacement demonstration or submitting review.

After deletion acceptance: merge/deploy the reviewed sandbox revision, verify immutable source/image lineage, readiness, protected-route rejection, App Attest and strict Sandbox verification, configure the actual sandbox notification output, and verify notification delivery/signatures/idempotency/isolation. Then coordinate iPhone acceptance and verify agreement acceptance. Freeze and validate the candidate before starting External Beta Cloud; inspect its external eligibility, submit Beta App Review only with verified access, and invite the existing group member only after approval.
