# iOS design review remediation

Source: PumpSync iOS Design Review, 6 November 2026, F01–F17. Baseline frontend: `3a6e72b`.

## Implementation sequence

1. Stage connection changes and explicit credential editing (F01–F04, F15).
2. Reconcile sync history, partial permissions, conversion, and cross-tab status (F07, F11, F12, F15, F17).
3. Add readable diagnostics, scoped exports, and privacy boundaries (F06–F08, F13, F14).
4. Simplify explanations and clarify removal/request effects (F03, F05, F13, F14).
5. Validate accessibility, final-row reachability, and native menus (F09, F10, F14, F16).

## Decisions

- Candidate connection authentication must not mutate the active connection. Activate only after success; retain the existing protocol-3 authentication journal and proof rules.
- Partial Health access remains supported. Only confirmed writes enter the ledger; deferred records retain replay coverage within the upstream history window.
- History means the current account and server, independent of access-token renewal.
- Preserve the two tabs and native controls. Make geometry changes only for reproduced failures.
- Backend fixes belong in the backend, policy in the website, and cross-repository narrative in the wiki.
- Source inspection and simulator fixtures do not establish physical-device, VoiceOver, clinical-domain, deployed-service, or distribution acceptance.

## Closure register

| Finding | Work and required evidence | Status |
| --- | --- | --- |
| F01 | Native prominent Sync/Connect/Save actions, busy/disabled state, neutral subscription management | Implemented; complete simulator suite passes |
| F02 | Saved-account summary; explicit Change, Save and Cancel; credentials preserved until validation succeeds | Implemented; storage and editor regressions pass |
| F03 | Scoped credential-removal confirmation; request-only deletion email; no Apple Health/subscription deletion claim | Implemented; device mail handoff deferred |
| F04 | Keyboard Return dismisses input without authentication; explicit Connect; isolated candidate authentication; durable pointer activation; crash/journal route recovery; late-response fencing | Implemented; eight connection regressions pass; hardware proof deferred |
| F05 | Short task copy; consequences remain visible; conversion mechanics and sync explanation have detail destinations | Implemented |
| F06 | Human summaries and navigable sanitized event/report details; legacy summaries identified | Implemented; discarded legacy payloads cannot be recovered |
| F07 | Exact UTC timestamps, native report windows/units, scoped attempt counts; unavailable values remain unavailable | Implemented; presentation and migration regressions pass |
| F08 | Named category copy, per-entry copy/share, explicit support-bundle scope and copy feedback | Implemented; category copy/clear UI regression passes |
| F09 | Stronger adaptive text/action contrast; full-width privacy text and scalable Health step numerals; native audit, twelve actual text categories and VoiceOver | Automated audit, all twelve text categories and seven simulator VoiceOver flows pass; manual contrast, device VoiceOver, Reduce Motion/Transparency deferred |
| F10 | One global status above TabView leaves native chrome unobscured; explicit keyboard dismissal and bidirectional final-content reachability | Implemented; compact and iPad recovery/navigation checks pass |
| F11 | Existing conversion captured once per operation; backend normalization inspected; historical samples unchanged | **Resolved: U-100 source baseline confirmed by Eric Slutz; existing uniform conversion verified** |
| F12 | Sync, Developer and exports share scoped history; saved counts survive idle/relaunch; latest attempts are separate; reset explanations and coherent fixtures | Implemented; restart, renewal and owner-change regressions pass |
| F13 | Sanitization before persistence/export; protected, backup-excluded native reports; retention and deletion disclosures | Implemented; redaction/migration/category-clear regressions pass |
| F14 | Decorative images hidden from VoiceOver; semantic native actions; full accessible/copyable installation ID | Implemented; spoken/device acceptance deferred |
| F15 | Draft cancel, candidate failure/late callback, busy/retry, cancellation, duplicate and partial-permission handling | Implemented; complete unit/UI suite passes |
| F16 | Native menus preserved; unique accessible action names; cancel/confirm/category isolation | Implemented; native-menu and simulator VoiceOver checks pass |
| F17 | Per-type authorization refresh at entry/foreground; partial import counts and bounded backfill | Implemented; permission-restoration regression passes; physical Health flow deferred |

## Validation results

No finding is closed from screenshots alone. Implementation completion is separate from release acceptance.

- **Toolchain:** Xcode 27.2 (`27B52`), iOS simulator SDK 27.2. Required compact coverage uses an isolated iPhone SE (3rd generation) / iOS 27.0. No iOS 27.2 runtime is installed; the SDK is not runtime acceptance.
- **Complete suite:** **467/467 passed, zero skipped**: 430 unit tests and 37 UI methods, including all seven simulator VoiceOver flows. Result bundle, raw logs, environment and source hashes: `TestResults/cloud-20261107T061025Z/`. Build-tool warnings were rejected, not suppressed.
- **Required local preflight:** the complete suite, standard/maximum-accessibility recovery checks, and final source-hash verification all passed. Original simulator text setting restored. This is local preflight, not hosted Cloud acceptance.
- **Text sizes:** **12/12 actual simulator categories** passed the adaptive keyboard/final-content flow. Original setting restored and source hashes verified: `TestResults/design-type-20261107T061720Z/`. The phone captures below were exported from this final run.
- **Native audit limits:** noncontrast audit checks remain strict. The complete run recorded 37 unresolved contrast observations from inaccessible native nodes; these are retained as manual measurement gaps, not successful contrast measurements. An isolated audit also passed with no unresolved nodes (`/tmp/pumpsync-design-audit-isolated.xcresult`), but this does not erase the complete-run coverage gaps. No contrast-conformance certificate is claimed.
- **iPad stress:** iPad Pro 13-inch (M5) / iOS 27.0, actual maximum accessibility text, dark appearance and Increase Contrast enabled. Recovery from a pushed screen and continued global status visibility passed, including nonintersection with native tabs and Back. Temporary settings restored; `/tmp/pumpsync-design-ipad-status-green.xcresult`.
- **Modern phone:** supported iPhone 17 / iOS 27.0 passed recovery, core screens and adaptive reachability (3/3), with warnings rejected: `/tmp/pumpsync-design-supported-phone.xcresult`. The newer iOS 27.1 iPhone Duo probe encountered SDK accessibility-role mismatches and later reported `Data Migration Failed`; latest-installed-runtime acceptance remains open. Xcode stays at 27.2.
- **Configurations:** Beta and Release simulator builds passed with zero build-tool warnings. These are compilation checks, not signed archives.
- **Backend:** Release build passed without warnings; complete tests **388/388**. The initial run exposed an Azurite readiness race; the test fixture now waits for an actual table operation. `/tmp/pumpsync-design-backend-final.log`.
- **Website:** tests **20/20**, build and HTML validation passed; `/tmp/pumpsync-design-website-final.log`.
- **Hosted validation:** [GitHub iOS CI](https://github.com/eslutz/PumpSync/actions/runs/42372161226) passed all 430 unit and 37 UI tests with Xcode 27.2 (`27B52`) and the strict warning gate. Cloud Validation 52 and Beta 53 each passed all 467 tests on SE (3rd generation) / iOS 27.2; the Beta archive succeeded. Both Cloud runs used implementation commit `8e3ebf17b1fcb16ea940b4a21841d7f128127875`. Backend CI also passed: [run 42372233224](https://github.com/eslutz/PumpSync-Backend/actions/runs/42372233224).

Earlier failed or interrupted runs are retained and are not counted as final passes. Regressions reproduced partial-permission replay loss, quoted-secret leaks, journal/API route restoration, candidate lifecycle races, keyboard Return initiating authentication, fixture metadata mutation, iPad status/navigation overlap, and a 34.5-point recovery hit target. Fixes are covered by the final unit/UI suite. The keyboard-toolbar trial that produced a runtime layout warning was removed; the warning gate was preserved. The ledger retains the intermediate evidence and harness corrections.

## Storage and export boundaries

| Data | Ownership and retention | Removal/export behavior |
| --- | --- | --- |
| Tandem sign-in | Device-only Keychain; not iCloud-synchronized | Explicit credential removal; not server metadata, Health samples, subscription, or ledger removal |
| Backend sessions/proof state | Device-only Keychain; isolated candidate namespaces and durable active pointer | Failed/canceled candidates cannot replace the working connection; abandoned/retired namespaces are cleaned when safe |
| Raw/normalized sync payload | Ephemeral networking without disk URL cache/cookies; attempt memory | Released at attempt completion, failure or cancellation; excluded from diagnostic exports |
| Source inspection | Separate in-memory controller | Cleared on close/background; never writes the real Health ledger |
| Imported-sample ledger | Hashed identifiers/timestamps; pruned on writes after 370 days, normally 5,000 entries (current batch protected) | Separate from credentials and Health; does not coordinate imports across devices |
| Successful-sync metadata | Local current-account/server scope | Token renewal preserves scope; owner changes reset summary with an explanation |
| Owned attempts | At most 20 completed plus active | Times, outcome, counts and correlation; support bundle includes retained attempts |
| App diagnostics | At most 200 sanitized events | Category clear affects only app events; bundle includes newest 50 |
| Device diagnostics | At most 50 allowlisted reports in protected Application Support, excluded from backup | Atomic legacy migration, retry on protected-storage failure; category clear only; bundle includes newest 50 |
| Clipboard/shared exports | Explicit sanitized entry, category or support scope | Clipboard is local-only with a two-minute expiry; destination copies are outside PumpSync control |
| Apple Health | Confirmed imported samples | Credential/log removal and server deletion do not remove these samples |
| Backend metadata | Existing installation-scoped operator workflow and documented shared associations/audit retention | Preparing email is neither sending a request nor completing deletion; self-hosted deletion belongs to that operator |

Native report fidelity means retained allowlisted measurements, windows, numeric exception/frame data and validated units, not arbitrary crash strings or memory. Legacy discarded payloads cannot be reconstructed. No histogram boundary is presented as an average or percentile.

## Decisions and remaining acceptance

- Initially kept the existing development branches and left changes uncommitted for review. Eric subsequently authorized commit/push and hosted validation after confirming F11; the remediation is now published through the existing frontend/website PRs, a scoped backend PR, and the canonical wiki.
- Follow the user's latest-stable-Xcode instruction, minimum 27.2; retain iOS 27.0 compact coverage and add a latest-installed-runtime check. Compact coverage alone would miss newer-runtime behavior.
- Retain only allowlisted native payload fields. This reduces diagnostic fidelity in exchange for excluding arbitrary sensitive content; legacy raw payload recovery is impossible.
- Record unresolved native contrast nodes and obscured/offscreen text as coverage limits, with captures. A native automated pass is not a contrast conformance certificate; unresolved nodes require manual measurements in representative appearances.

Manual and physical-device acceptance checks are explicitly deferred by Eric Slutz. The locked Mac separately prevents browser repair of the existing Internal Beta workflow; API access supports the other hosted steps.

Deferred by Eric Slutz: physical-device Health permission changes/write/deduplication; Secure Enclave/App Attest and StoreKit purchase/restore; actual mail-client handoff/fallback; spoken physical-device VoiceOver and focus; Reduce Motion and Reduce Transparency; physical-device Increase Contrast; remaining manual contrast nodes; human design acceptance. Backend/website production deployment and PR merges are separate from this internal app delivery. Existing multipliers and historical Health samples were not changed.


## Final code-review fixes

One independent read-only review identified eight material issues. The fix pass addressed journal-bound route recovery, atomic configuration/API routing, complete quoted-secret redaction, late purchase-sheet callbacks, cleanup of canceled candidate storage, stale committer failure fences, status visibility on pushed destinations, and initial protected-report migration retry. Covering regressions are in `ConnectionActivationTests`, `DiagnosticsLogStoreTests`, `DiagnosticPresentationTests`, and the pushed-status UI test. There were no deferred minor findings. The reviewer did not re-review the final fixes; validation is recorded by the regression and complete-suite results above.


## F11 source-unit confirmation

Eric Slutz confirmed in this review that all pump algorithms and provided data assume a U-100 baseline, and authorized applying the concentration multiplier uniformly. This is owner-supplied domain confirmation, not independently published clinical validation.

The existing implementation already applies U-100/U-200/U-500 factors of 1/2/5 exactly once to both bolus and normalized basal insulin quantities; carbohydrate grams remain unchanged. ImportPlanTests covers concentration conversion, basal intervals, zero values, and preserved source metadata. The captured setting belongs to each operation; historical Health samples are not rewritten. No multiplier or production algorithm change is needed. F11 is resolved on this confirmed product contract. Manual/physical-device acceptance is explicitly deferred; hosted validation proceeds separately.

## Representative captures

Synthetic fixtures only; these are simulator evidence, not App Store submissions or physical-device acceptance.

- [iPad maximum text, dark, increased contrast: unobscured native navigation](assets/2026-11-06-remediation/ipad-max-status.png)
- [iPad recovery menu and its explicit action](assets/2026-11-06-remediation/ipad-max-recovery-menu.png)

- [iPhone connection draft and explicit actions](assets/2026-11-06-remediation/iphone-draft-connection.png)
- [iPhone privacy final content](assets/2026-11-06-remediation/iphone-privacy-final-content.png)
- [iPhone maximum text: privacy final content](assets/2026-11-06-remediation/iphone-max-privacy-final-content.png)
- [iPhone maximum text: Developer final content](assets/2026-11-06-remediation/iphone-max-developer-final-content.png)

## Publication and internal delivery

The reviewed implementation is committed and pushed. Frontend [PR 5](https://github.com/eslutz/PumpSync/pull/5), backend [PR 8](https://github.com/eslutz/PumpSync-Backend/pull/8), and website [PR 10](https://github.com/eslutz/PumpSync-Website/pull/10) are assigned to Eric Slutz. The canonical wiki is updated. PRs are not merged; backend and website production services were not deployed.

TestFlight build **53** is VALID, assigned to the existing Internal Testers group, and its internal state is **IN_BETA_TESTING**, verified through the API after all hosted gates passed. External testing and App Store submission were not started. Physical-device installation and acceptance remain explicitly deferred.

Cloud Validation, External Beta and App Store Release use Latest Release Xcode (currently 27.2). The existing Internal Beta workflow remains on its old configuration because Apple's API rejected the action/distribution mapping update. Its repair requires browser access to the unlocked Mac. This build used the updated archive workflow with no distribution post-action, followed by an explicit assignment only to Internal Testers. Configuration rollback, invariant checks, test summaries and TestFlight membership/state evidence are retained in `Documentation/app-store/xcode-cloud/`.

The source hashes from local preflight were rechecked before publication (104/104 unchanged). Subsequent evidence updates change documentation only; hosted test receipts identify the tested implementation revision explicitly.
