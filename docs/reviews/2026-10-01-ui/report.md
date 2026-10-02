# PumpSync iOS UI review — 2026-10-01

**Follow-up:** implementation remediation is documented in the [remediation section](#remediation-follow-up--2026-10-01); the original review below remains the baseline.

**Verdict: important accessibility and reliability issues need fixes.** Six findings: two High and four Medium. The largest Dynamic Type size visibly breaks setup layout, and invalid self-hosted connection attempts give no local error feedback. Source review also identified an in-flight concentration-setting risk, credential-validation lifetime risk, Reduce Motion gap, and inaccurate data-handling copy. Successful authenticated sync and actual VoiceOver operation remain unverified; this report does not establish release readiness.

Report completed before implementation. App code, project configuration, and existing tests were not changed. A disposable copy hosted the audit harness. Existing working changes were retained.

## Baseline and method

Reviewed working checkout at `f1539c716b760a9c2a4f359ed37b23a2aace392f`, including pre-existing edits, rather than pristine HEAD. PumpSync 1.0.0 (33), Debug, scheme PumpSync; Xcode 27.0 (27A266a), SDK 27.0, minimum iOS 26.0. Runtime: isolated iPhone 17 simulator, iOS 26.5. [Baseline and file hashes](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/baseline.json).

Inspected actual screenshots and accessibility metadata, then traced SwiftUI and service paths. Tested standard Large text in light and dark mode, plus system AX5 (largest accessibility text) with Increase Contrast. Restored simulator text/contrast/appearance settings afterward. No supplied account, purchase, successful server connection, or health data was available. Apple Account prompt was canceled. Opened the Health authorization sheet without proving grant or denial. No successful sync or Health write occurred.

The original project built successfully without observed warnings: [build log](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/build.log). A temporary UI harness completed one AX5 run and one dark-mode run; these passes establish navigation/capture execution, not defect-free accessibility. [Harness](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/temporary-audit-harness.swift.txt), [AX5 log](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/audit-ax5.log), [dark log](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/audit-dark.log). The owning full test suite was not run for this report-only task.

## Numbered primary flows and health

| Step | Flow and observed result | Health |
|---|---|---|
| 1 | Fresh Sync: disconnected status, Past 7 days selector, disabled Sync, subscription recovery actions visible. | Checked; authenticated completion blocked |
| 2 | Hosted Settings: account/subscription and setup destinations present; subscription verification could not complete without account. | Partial; activation blocked |
| 3 | Self-hosted Settings: selected mode, entered invalid URL, tapped Connect; no inline error appeared. | Failed — UI-03 |
| 4 | Tandem setup: empty username/password/region form and disabled Save shown; AX5 region overlaps Save. | Failed — UI-01; real validation blocked |
| 5 | Apple Health: Not Set statuses, explanation and request action; actual permission sheet opened. | Checked entry; grant/deny recovery not checked |
| 6 | Insulin concentration: U100 and explanatory copy visible; AX5 Change label wraps into a vertical string. | Failed — UI-01; in-flight mutation risk UI-02 |
| 7 | First import and subsequent Sync: traced download, conversion, persistence, progress and failure paths. | Runtime blocked; source reviewed |
| 8 | Data Handling: screen readable at ordinary text; credential-transmission claim contradicts validation path. | Failed copy review — UI-06 |
| 9 | About and Developer: light screens inspected; dark About inspected; Developer dark capture rejected during transition. | Checked light; dark Developer not checked |
| 10 | Navigation and recovery: back navigation through six child screens exercised; keyboard-up tab recovery was not successfully established. | Partial; validation lifetime risk UI-04 |

## Representative inspected screenshots

Screens appear in flow order. Images capture the real app, with no screenshot fixtures used to claim functional completion.

![Step 1 — fresh disconnected Sync](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/01-fresh-sync.png)

![Step 2 — hosted Settings](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/02-settings.jpg)

![Step 3 — invalid self-hosted connection, keyboard open, no local error](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/dark-system-invalid-connect.png)

![Step 4 — Tandem credential form at ordinary text size](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/03-tandem.jpg)

![Step 4 — AX5 region picker overlaps Save](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/ax5-tandem.png)

![Step 5 — Health status and permission explanation](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/04-health.jpg)

![Step 5 — actual system Health authorization sheet](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/05-health-request.jpg)

![Step 6 — AX5 concentration Change label fails to reflow](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/ax5-concentration.png)

![Step 8 — Data Handling copy](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/light-privacy.png)

![Step 9 — About](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/light-about.png)

![Step 9 — Developer in light mode](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/light-developer.png)

![Step 1 — actual dark-mode Sync](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/dark-system-01-sync.png)

## High findings

### UI-01 — Accessibility text breaks setup layout

**Classification: verified defect.** Steps 4 and 6; also shared settings/status rows. iPhone 17, iOS 26.5, AX5 and Increase Contrast enabled. Sources: [TandemCredentialForm.swift:67](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/Tandem/TandemCredentialForm.swift:67) (region HStack), [GlassUI.swift:74](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/UI/GlassUI.swift:74) (fixed icon frame), [SettingsView.swift:385](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/UI/SettingsView.swift:385) (concentration menu).

Expected: controls reflow without obscuring neighboring controls. Observed: United States stacks vertically outside its row, overlaps Save, and makes the form difficult to read and operate. The region accessibility frame extended from y476.3 for 377.3 points; Save began at y637.7, producing about 216 points of vertical intersection. Concentration Change becomes letter-per-line. Scalable title-sized icons also collide with adjacent text inside fixed 28-point columns. This is one shared reflow problem, not separate cosmetic findings.

**Reproduction ran:** set system text to AX5, enable Increase Contrast, open Settings → Tandem; then inspect Insulin Concentration. Evidence: screenshots above and `ax5-tandem-tree.txt`/`ax5-concentration-tree.txt` in evidence.

**Fix:** switch constrained horizontal rows to vertical arrangements at accessibility sizes; put the region picker below its label, move Change below the value, and allow icon columns to scale or omit decorative icons. Avoid limiting the user's font size. Vertical layout costs height but preserves scrollable readable content.

**Acceptance:** ordinary text through AX5 remain readable with no overlapping frames; every region, Save, concentration, and history action remains reachable with keyboard and scrolling. Repeat in light/dark, Increase Contrast, and actual VoiceOver.

### UI-02 — Concentration can change an import already in flight

**Classification: source-supported risk; runtime reproduction not performed.** Steps 6–7, all devices. Sources: [SettingsView.swift:388](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/UI/SettingsView.swift:388) (immediate preference write), [SyncCoordinator.swift:393](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/Sync/SyncCoordinator.swift:393) (await download before save), [HealthKitService.swift:298](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/Health/HealthKitService.swift:298) (reads current concentration during conversion).

Expected: an import uses a consistent, deliberate concentration choice. Observed source path: navigation remains available while a sync downloads; Settings can change the preference immediately; conversion subsequently reads the live preference. A U100→U500 change while download is pending can therefore alter that operation's conversion factor. This is a data-integrity concern; no incorrect Health sample was observed or written during the audit.

**Reproduce next:** use a delayed local/stub download with known insulin records, start sync under U100, change to U500 before resolving the response, inspect the conversion factor used without writing real Health data.

**Fix:** snapshot concentration into immutable operation input before the first await and carry it through conversion, or disable concentration changes during import. Snapshotting preserves Settings access; disabling is simpler but restricts interaction. Explain that changes apply to future imports and do not rewrite previously imported data.

**Acceptance:** every sample in an operation uses its captured setting; the following operation uses the new setting. Verify cancellation/retry and multiple overlapping sync callers.

## Medium findings

### UI-03 — Self-hosted Connect failures have no local feedback

**Classification: verified defect.** Step 3; ordinary dark mode and AX5 light mode. Sources: [SettingsView.swift:70](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/UI/SettingsView.swift:70) (Connect task), [SettingsView.swift:86](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/UI/SettingsView.swift:86) (status shown only while connecting), [AuthService.swift:574](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/Auth/AuthService.swift:574) (invalid URL error).

Expected: invalid input produces an actionable error beside Connect. Observed: entering an invalid URL and tapping Connect leaves the form unchanged with no error. AuthService sets errorMessage, but this Settings section does not render it after connecting stops. Sync's disconnected error presentation is a possible source-level workaround; keyboard-up tab switching was not verified.

**Reproduction ran:** Settings → Self-hosted → invalid URL → Connect. Evidence: `dark-system-invalid-connect.png`, `ax5-invalid-connect.png` and matching trees.

**Fix:** show inline validation/network errors and connected state in this section; preserve the draft, explain the expected base API URL, and announce outcome accessibly. Inline messages occupy space but remove reliance on another tab.

**Acceptance:** malformed URL, unreachable endpoint, and successful local connection each produce distinct feedback; errors can be corrected without losing the draft; VoiceOver receives outcome once without disruptive focus jumps.

### UI-04 — Credential validation is not tied to form/configuration lifetime

**Classification: source-supported risk; account-backed reproduction blocked.** Steps 4 and 10. Source: [TandemCredentialForm.swift:97](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/Tandem/TandemCredentialForm.swift:97) (untracked Task), [TandemCredentialForm.swift:255](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/Tandem/TandemCredentialForm.swift:255) (`validateAndSave`, awaits validation then saves).

Expected: stale validation cannot silently save credentials after the user leaves or changes configuration. Source: input values are captured before an await, fields/navigation remain editable, and the completion saves without a cancellation/configuration-generation check. A late completion can persist earlier credentials or update offscreen state; the region baseline also uses the live region after validation rather than consistently using captured inputs.

**Reproduce next:** delayed fake validation; submit, navigate away or change region/server configuration, then resolve. Inspect persistence and alert state. No real validation was performed here.

**Fix:** own validation in a tracked form model/task, capture all inputs together, and check operation identity/configuration revision before committing. Disable fields during validation or provide explicit cancellation; cancellation should prevent local persistence even if a server request has completed.

**Acceptance:** abandoned/stale completions never persist; a current successful result saves exactly the validated snapshot; editing afterward yields correct dirty-state detection and retry behavior.

### UI-05 — Custom sync rotation ignores Reduce Motion

**Classification: source-supported risk; running-sync motion not observed.** Step 7. Source: [SyncView.swift:257](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/UI/SyncView.swift:257) (`SyncButtonLabel` animation TimelineView and rotation).

Expected: Reduce Motion avoids the custom continuous rotation while retaining clear progress text. Source: timeline is paused only when not syncing; computed rotation continues without reading accessibilityReduceMotion. Disabling transaction animation in a screen wrapper does not stop explicit timeline-driven angle updates.

**Reproduce next:** delayed running sync, toggle system Reduce Motion on/off and observe the main Sync label. No fabricated fixture was used as real sync evidence.

**Fix:** pause this timeline under Reduce Motion and use a static icon with textual phase. This reduces visual activity while preserving progress information. See Apple's [accessibilityReduceMotion environment documentation](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion).

**Acceptance:** no custom continuous rotation with Reduce Motion on; phase/status remain understandable without motion or color; ordinary mode retains intended animation. Check the global progress banner separately.

### UI-06 — Data Handling understates credential transmission

**Classification: verified copy/source contradiction; transmission not observed at runtime.** Step 8. Sources: [PrivacyView.swift:20](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/UI/PrivacyView.swift:20) and [TandemCredentialForm.swift:284](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/Tandem/TandemCredentialForm.swift:284).

Expected: copy includes all credential-transmission triggers. Observed screen says credentials are sent “only while syncing”; the validation/save path also submits them for account validation outside a sync. This weakens informed understanding of setup. It is not evidence of unauthorized storage or a backend security defect.

**Reproduction:** Data Handling screen inspected; validation call traced in current source. Actual request not executed without an account.

**Fix:** describe transmission when validating the account or syncing, with wording consistent with canonical public policy. Avoid new server-retention claims without evidence. More exact language is preferable to removing the explanation.

**Acceptance:** observed validation/sync request paths match the screen and public policy; test with synthetic credentials and request capture, excluding secrets from logs.

## SwiftUI architecture assessment

The composition is sound overall: App owns observable AppServices, dependencies are assembled explicitly, and each tab has its own NavigationStack. This supports stable tab identity and local navigation. Foreground recovery is scene-aware and cancellable; AuthService uses configuration revisions/operation identities to guard service-level session writes. SyncCoordinator coalesces callers into a shared operation, checks cancellation around download/write boundaries, and tracks imported samples independently from the success watermark. These strengths argue for focused repairs rather than a wholesale rewrite.

The main ownership gap is view-created credential validation (UI-04), which does not inherit those service-level stale-operation protections. The main state-consistency gap is mutable concentration read after suspension (UI-02). Broad main-actor orchestration and large service types deserve profiling if large imports are slow, but no measured performance defect was established. Modern Tab/Observation usage is compatible with the stated deployment target; the observed build emitted no deprecation warnings. Cold-launch navigation restoration, deep links, and App Shortcuts were not runtime reviewed.

## Accessibility evidence and coverage

Apple's [XCTest accessibility audit API](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/performaccessibilityaudit%28for%3A_%3A%29) was invoked for contrast, hit regions, sufficient descriptions, clipped text, and traits on sampled initial screen viewports. The issue handler logged and accepted issues so the harness could continue. **A passing harness is not a clean audit.** AX5 logged 10 contrast failures; dark mode logged 41 failures and one nearly-passed contrast result. Several involved disabled/offscreen/footer-under-glass elements. These are unresolved signals, not calibrated contrast-ratio findings. No selected non-contrast issues were emitted, yet the audit missed visible AX5 overlap. Manual inspection remains necessary.

Early launch-override attempts did not actually establish dark/large system settings, and initial self-host selection failed due to harness scrolling. Those runs are recorded in [first-run log](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/audit-first-run.log) and rejected captures; they do not establish those coverage conditions. The final dark Developer image was captured during navigation transition and was rejected. Keyboard recovery images still show Settings and must not be interpreted as successful Sync navigation.

| Area | Coverage | Result/limit |
|---|---|---|
| Empty/disconnected state | Checked | Clear setup prerequisites; real account recovery blocked |
| Standard light layout | Checked | Representative screens readable; no general visual redesign recommended |
| Dark mode | Checked, partial | Native colors adapt on accepted screens; Developer settled capture not checked |
| Dynamic Type AX5 | Failed | UI-01 overlap and letter-per-line controls |
| Increase Contrast | Checked, partial | Enabled with AX5; independent ordinary-text contrast not checked |
| Contrast ratios | Not checked conclusively | Automated signals require calibrated/manual follow-up |
| Accessibility metadata | Checked, partial | Sampled labels/traits present; initial viewport audit only |
| Actual VoiceOver order/focus/actions | Blocked | No device/manual session; metadata is not VoiceOver proof |
| Reduce Motion | Source checked; runtime blocked | UI-05; no running sync |
| Differentiate Without Color | Not checked runtime | Text/icons exist; no end-to-end setting validation |
| Health authorization entry | Checked | System sheet opened |
| Health grant/deny/re-enable | Not checked | No authorized import or actual recovery verification |
| Tandem validation/save/remove | Blocked | No usable account; empty form inspected |
| Hosted entitlement/purchase recovery | Blocked | Apple Account unavailable; no transaction performed |
| Valid self-host connection | Blocked | No test endpoint supplied |
| Invalid self-host connection | Failed | UI-03 |
| Sync progress/success/error/retry | Blocked runtime | Source paths reviewed only |
| Background execution | Blocked | Scheduling/source does not prove execution |
| Back navigation | Checked | Six child screens exercised |
| Keyboard and tab recovery | Not checked successfully | Captures remained in Settings |
| iPad, small iPhone, landscape/rotation | Not checked | iPhone 17 portrait only |
| Localization/long translations | Not checked | English only |
| Deep links/App Shortcuts/cold restoration | Not checked | No runtime exercise |
| Send mail/share/delete/purchase | Not applicable to performed audit | No external submission or destructive action |

## Priorities and remaining acceptance

1. Fix UI-01 reflow and UI-02 operation input consistency first.
2. Fix inline connection feedback and validation lifetime before account-backed retests.
3. Honor Reduce Motion and correct data-handling copy.
4. Retest with a controlled account/server: permission grant/deny/recovery, validation failures and cancellation, first and repeat import, progress/error/retry, and real background execution. Capture data without secrets.
5. Perform actual VoiceOver, keyboard recovery, calibrated contrast, small-screen/iPad/landscape, and localization checks. Re-run focused tests for fixes, then owning full suite.

No readiness approval is supported while the core authenticated import path and manual accessibility checks remain unverified. [Evidence directory](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence) contains screenshots, trees, logs, and baseline hashes; rejected captures are retained separately. This is an iOS UI/architecture/accessibility report, not a backend security or clinical validation.

## Remediation follow-up — 2026-10-01

All six findings now have focused implementation changes. This section describes the working checkout after remediation; the original findings, source line references, screenshots, and coverage above remain the historical review baseline. No commit, push, deployment, purchase, real credentials, or real Health write was performed. No new test-only authentication behavior, entitlement bypass, simulator fallback, or shipped fixture hook was added. Regression fakes remain in test targets; the runtime recheck harness is an external disposable copy.

| ID | Implemented repair | Verification and remaining limits |
|---|---|---|
| UI-01 | Accessibility-size region, concentration, and history controls reflow vertically. Region uses an explicit Menu label so native Picker sizing cannot truncate/overflow it. Shared icons use intrinsic widths rather than fixed 28-point columns. | Real disconnected app rechecked at system AX5 + Increase Contrast on iPhone 17/iOS 26.5. Region ends at y615; Save starts at y651, with no intersection. Inspected screenshots show readable Region/United States and a full-word Change label. Region/Save frame assertion passed. Actual VoiceOver, keyboard/scroll reachability of every action, other sizes/devices, and localization remain pending. |
| UI-02 | Sync captures concentration synchronously when creating the shared operation, carries it through download, Health conversion, and subscription-recovery retry. Settings explains next-operation behavior and no retroactive change to imported data. | Delayed-download regression passed: changing U100→U500 while suspended and adding a shared caller keeps the current operation at U100; the next operation receives U500. Existing shared cancellation tests passed. This uses fake Health writes; actual sample values and account-backed retry still need device acceptance. |
| UI-03 | Self-hosted section renders persistent error/status feedback and base API URL guidance. Connect posts an accessibility announcement after completion. | Actual invalid URL submission at AX5 passed an inline-feedback assertion and shows “Enter a valid self-hosted service URL…” beside Connect. Successful/unreachable-server behavior and actual VoiceOver announcement delivery remain unverified. Draft text remains present. |
| UI-04 | Observable CredentialValidationLifetime owns/cancels the task and busy state. Leaving the form, changing connection revision, or becoming inactive cancels it. Fields are disabled during validation; completion checks cancellation and configuration revision before saving or presenting errors. Baseline region uses the validated snapshot. | Delayed-completion regression passed: abandoned work cannot commit and cannot clear a newer request's busy state. Configuration checks and snapshot persistence were source reviewed. A real delayed authenticated validation, exit/re-entry, and connection-switch sequence remain device acceptance work. |
| UI-05 | Reduce Motion pauses the custom TimelineView and forces zero rotation. Shared status rows and the global banner avoid spinning progress indicators under Reduce Motion while retaining text. | Rotation regression and existing status/banner tests passed. Actual running-sync motion with Reduce Motion on/off remains unverified; no fixture was used as authenticated sync proof. |
| UI-06 | App Data Handling and hosted setup copy now include account validation as a transmission trigger. Canonical website privacy text was corrected in its owning repository without changing retention claims. | App copy screenshot inspected; website content invariant and full build/tests/HTML validation passed. Actual request capture and publication of the website change remain unperformed. |

Relevant implementation: [credential lifetime owner](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/Tandem/CredentialValidationLifetime.swift), [form cancellation/guards](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/Tandem/TandemCredentialForm.swift:134), [captured sync input](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/Sync/SyncCoordinator.swift:280), [inline feedback](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/UI/SettingsView.swift:87), [motion handling](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/PumpSync/Sources/UI/SyncView.swift:266), [canonical privacy correction](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.website/src/privacy/index.njk:54).

### Validation evidence

- Initial focused run: 60 tests, zero failures. Final owning warning-gated `scripts/ios/validate-tests.sh` run passed after the explicit Region Menu adjustment: **245 unit tests + 13 UI tests, zero failures, no warning matches**; [raw log](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/remediation/ios-final-full-tests.log).
- Disposable runtime harness: one test passed using actual system AX5 and Increase Contrast, inspecting the real disconnected app and malformed-URL validation; [accepted run log](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/remediation/ax5-accepted.log). This proves these sampled layouts/feedback, not successful authentication or Health import.
- Website: `npm test` passed 18 Node tests and HTML validation; [log](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/remediation/website-tests.log).
- `git diff --check` passed in both repositories. Baseline hashes of unrelated dirty files match; pre-existing Settings/Sync/test changes were retained. Xcode project regenerated from the unchanged `project.yml` to register the new production lifetime-owner file.

Earlier rechecks are retained as rejected runs: one interrupted attempt could not set AX5 because the simulator was shut down, one used an incorrect accessibility query and exposed remaining native Picker label overflow, and one queried a segmented control although accessibility sizes use separate connection buttons. The final run corrected those issues. Simulator text size and Increase Contrast were restored to Large/disabled; appearance remained light. No new clean contrast or actual VoiceOver claim is made.

### Inspected remediation screenshots

Real disconnected app, AX5 + Increase Contrast:

![UI-01 — readable Region menu and separate Save action](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/remediation/remediated-tandem.png)

![UI-01 — concentration reflows with full-word Change action](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/remediation/remediated-concentration.png)

![UI-03 — local URL error is visible after Connect](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/remediation/remediated-invalid-connect.png)

Standard-text screenshot fixtures used only to inspect layout/copy rendering, not functional authentication:

![UI-01 — final Region menu at standard text](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/remediation/standard-fixture-tandem.png)

![UI-06 — corrected credential transmission copy](/Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.frontend/docs/reviews/2026-10-01-ui/evidence/remediation/standard-fixture-data-handling.png)

Implementation remediation does not close the review's authenticated-session or manual accessibility coverage gaps. Physical-device validation should still cover hosted entitlement/App Attest, credential rejection/success/cancellation, Health grant/deny/recovery, first and repeated import with duplicate prevention, interruption/retry, actual VoiceOver, running-sync Reduce Motion, and background execution evidence.

Manual VoiceOver acceptance: enable VoiceOver on a physical device, swipe through Sync and each Settings destination, verify title/value/disabled-state announcements and logical order, open and choose every Region/concentration/history menu option, enter an invalid URL and confirm one outcome announcement, then repeat keyboard/back/tab transitions and permission-sheet dismissal. Repeat the running-sync check with Reduce Motion enabled; progress must remain understandable from text with no custom rotation. Account-backed save and import checks require the controlled authenticated session described above.

## Additional safe preview architecture acceptance (2026-10-01)

The six original audit findings and their evidence above remain unchanged. The new architecture adds separate Sample Preview and optional real Preview Import; it does not retroactively verify either flow. Automated zero-write/provenance/isolation coverage and settled candidate UI evidence must be recorded separately. Authenticated physical-device operation, real Health persistence/deduplication, spoken VoiceOver, deployment, and Apple arrangement confirmation remain pending.
