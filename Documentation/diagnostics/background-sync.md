# Background sync interruption diagnostics

## Local investigation, November 7, 2026

The supplied build 51 bundle and correlated backend traces distinguish three
background downloads on November 5–6: one interrupted client attempt during
`updatingHealth`, followed by two completed client imports. The morning November 6
attempt recovered from a backend expired-entitlement rejection before completing.
No raw bundle, health readings, account identifiers, or credentials are retained here.

The interruption record is reconstructed when an unfinished owned attempt is loaded.
It does not establish a crash, OS termination, expiration, or time spent executing.
Xcode's crash-reporting connector returned `Product not found` for this app; no
crash/termination cause has been verified. App Store Connect API readback subsequently confirmed build 51 from
`e5398dbc9c8f111b97ac3f02721203c24da52645`, which includes the November 4
cancellation fix `07473b9`. This does not prove that fix caused or prevented the
observed interruption. Repository and API evidence separately record build 53 from `8e3ebf17b1fcb16ea940b4a21841d7f128127875`; these changes
require a subsequent build.

## New support-bundle fields

Owned attempts retain the last import checkpoint across process restarts:

- `healthSaveStarted`: entered the Health writer; submission/callback is not yet confirmed.
- `healthSaveCompleted`: writer returned successfully; imported/permission-skipped counts are recorded.
- `ledgerCommitStarted`: confirmed writes are about to enter the deduplication ledger.
- `ledgerCommitCompleted`: ledger returned successfully.
- `metadataCommitted`: success metadata and watermark were updated.

`lastObservedAt` timestamps the last recorded stage/checkpoint.
`protectedDataAvailable` captures UIKit protected-data availability at the import
checkpoint; it is context, not proof of HealthKit availability or a failure cause.
Interrupted attempts use `durationSeconds=unknown`, no `completedAt`, and a separate
`interruptionDetectedAt` restart timestamp. Existing historical records are not
retroactively corrected. Old records decode without the new fields.

Checkpoints use the existing bounded UserDefaults attempt journal and event log;
an abrupt termination can precede disk flushing. A missing checkpoint is not proof
that an operation never happened. No synchronous disk-flush guarantee is claimed.

## Verification and device acceptance

Local coverage exercises restart reconciliation at each checkpoint, legacy decoding,
confirmed writes after cancellation, ledger failure without watermark advancement,
execution-lease expiration, and cancellation/timeout races. A replay after a canceled
save must filter already-ledgered samples and complete normally. Simulator tests
cannot establish actual OS task delivery or physical HealthKit persistence.

For device acceptance, install a build containing these changes, keep the test
subscription active, and observe normal use for 48–72 hours. Retain a support bundle
and UTC event time after a suspected interruption. Correlate the owned operation and
request links with backend traces before inferring a download failure. Obtain device
crash/jetsam diagnostics if interruption recurs. Verify Health records are not
duplicated when a write succeeded before ledger persistence, and that later syncs
catch up. The writer uses stable HealthKit sync identifiers/version, but this replay
boundary still needs physical-device verification.

A pending BGTask request establishes submission, not guaranteed delivery at its
earliest start. Keep scheduling gaps separate from attempts that launched and failed.

### Validation results

- Final focused run: 112 tests passed, no build-tool warnings, on iPhone 17 /
  iOS 27.2 with Xcode 27.2. Includes the added canceled-save replay assertion.
  Raw log: `/private/tmp/pumpsync-sync-diagnostics-final-sequential.log`.
- Broader run: all 431 unit tests passed before UI execution. The UI accessibility
  audit reported undersized hit areas at `PumpSyncUITests.swift:748`; the broader
  run was stopped afterward. This is not a full-suite pass or a compact-device
  Cloud preflight. Raw log: `/private/tmp/pumpsync-sync-diagnostics-full.log`.
- An overlapping focused launch terminated before establishing its test connection
  during shutdown of the broader run. It ran no tests; the final focused run above
  was sequential after shutdown. Its log is retained at
  `/private/tmp/pumpsync-sync-diagnostics-final.log`.
- `git diff --check` passed. No TestFlight upload or device installation performed.

## Published policy and release verification

The published policy at <https://pumpsync.ericslutz.dev/privacy/> was fetched on
November 7, 2026. It is older than the repository policy and lacks the newer explicit
local-diagnostic retention/export paragraph. It describes minimal on-device sync
metadata and technical telemetry. These additions record categorical execution
checkpoints, operation timestamps, counts, and protected-data availability locally;
they add no automatic transmission, raw health samples, credentials, or account
identifiers. No contradictory published claim was identified for these changes.
The published policy and repository copy should be reconciled in website work.

The combined source includes design remediation `8e3ebf1` and current `origin/main`
(`c323dbe`) as ancestors. Live Cloud workflow readback selects Latest Release Xcode
27.2 (`27B52`) and iPhone SE (3rd generation) / iOS 27.2. The local compact preflight
uses iOS 27.0, as required by the repository guide. Distribution is scoped to the
existing Internal Testers group through the tested Beta archive workflow.

### Release preflight

`bash Scripts/ios/validate-cloud-tests.sh` passed on November 7 with Xcode 27.2:
431 unit tests and 37 UI tests on iPhone SE (3rd generation) / iOS 27.0, followed
by passing connection-recovery runs at standard and maximum accessibility sizes.
The script restored the original text size and verified source hashes. No
build-tool warnings were reported. Evidence remains in ignored
`TestResults/cloud-20261107T212011Z/` (full/recovery result bundles and summaries).
This is separate from the earlier iPhone 17 / iOS 27.2 accessibility failure.
