# UI refinement from the November 9 screenshot review

This change addresses the owner's twelve findings using native SwiftUI forms,
labels, navigation, and system materials. The feedback revision below replaces
the rejected status toolbar and details sheet with inline progress and floating
messages. HTTPS remains required. Self-hosted
base paths may be the root or any reverse-proxy prefix; the app appends its
relative API routes without changing device-proof protocol paths. No HTTP
migration or stored-configuration repair was added.

## Finding coverage

| Finding | Implemented behavior |
| --- | --- |
| 1. Endpoint format | HTTPS only, including loopback; `/api` is an example rather than a requirement. Existing TLS/ATS and redirect protections remain. |
| 2. Connection and credential clutter | Self-hosted configuration contains the picker, URL and native Connect action. Subscription stays under PumpSync. Leaving an editor discards its draft and cancels owned validation. Tandem Save uses the entered current login password and lives with its fields; credential removal is separate. |
| 3. Health icons | Native syringe and fork/knife labels accompany the existing write-authorization states. |
| 4. Conversion explanation | Native symbol-led explanations and 1×/2×/5× factors replace the duplicate Current Selection section. Conversion semantics are unchanged. |
| 5. Deletion section | Plain description, one native email action, privacy link and a short footer; self-hosted users see deletion instructions. No duplicate envelope or draft disclaimer. |
| 6. About | Requested manual-sync wording and an icon-led Last successful sync row in How Sync Works. |
| 7. Developer | Removed duplicate account/server section; shortened support-bundle footer and aligned native separators. |
| 8. App Event | Summary, readable known preview fields, and Log Details. Optional structured preview metadata preserves older log decoding and redaction. |
| 9. Performance | Report Data disclosure and reporting-period wording; no reference to an invisible histogram. Retained report exports are unchanged. |
| 10. Hosted copy | Removed the redundant manage/restore sentence. |
| 11. Glass placement | Standard Form actions inside content sections. Native glass remains in tabs and navigation/toolbars; the isolated Sync action retains its native prominent style. |
| 12. Moving feedback | Progress appears directly in the Sync screen. Errors and important completion notices use a dismissible overlay, which does not insert a row or change the page's safe-area layout. The toolbar status icon and Sync Details sheet are removed. Ordinary success updates the existing summary without a banner. |

## Ownership and recovery

The Tandem editor updates the login saved by PumpSync. It does not change the
password held by Tandem. The user enters their current Tandem password; no
previous-password challenge or remote password-change form is introduced.

Each subscription destination starts an independent connection candidate from
committed settings. Discarding a parent draft cannot cancel that candidate.
Completed navigation to another screen abandons an editor. Dismissing a
floating message does not leave the current screen or discard its draft.
Keyboard, picker, and Apple authorization UI continue the current action. Stale validation and purchase callbacks cannot activate abandoned
drafts; StoreKit retains undelivered verified purchases for recovery.

Manual retry now handles the existing wait-and-retry state, without adding
automatic retries for rate limits. Dismissing a floating message or closing a
recovery screen never clears the previous sync failure. A renewed session alone does not prove that
the protected sync request succeeded; a later sync updates the result.

## Feedback revision

The Sync screen keeps a stable status area and action in its normal form. A
native progress indicator and readable phase text show activity without opening
another screen. The status area reserves the natural size of its phase copy,
including at larger text sizes; longer failure text remains scrollable within
that area. Recovery stays inside the reserved status area; the independent
Sync Now action remains available when the current connection, credentials and
Health permissions are ready. Its native Liquid Glass style is retained. At
accessibility text sizes, its label uses the full width for text; at other sizes
the sync symbol remains. Both idle and running labels reserve their natural
height so the action does not resize when activity starts or finishes.

Floating messages are limited to failures and nonempty important completion
notices. They use native text, buttons and system material in an overlay. The
close control dismisses only the presentation. Failure information and recovery
remain on Sync, and a later failure can create a new message. Navigation and
ordinary successful syncs do not redisplay a dismissed message. Reduce
Transparency uses an opaque system background.

The intended layout behavior is that showing or dismissing a floating message
changes neither the page's content position nor navigation/tab-bar frames.
Progress phase changes likewise keep the existing status/action layout stable.
The tests below measure this behavior; visual and accessibility evidence must
come from the revised source before those checks are considered passed.

## Full release validation (November 9)

The final complete pre-release gate passed with Xcode 27.2 (27B52) on the
isolated iPhone SE (3rd generation), iOS 27.0 destination required by the local
runbook. `TestResults/cloud-inline-release-final/` retains the raw logs,
result bundles, summaries, and matching source-hash verification:

- Full unfiltered suite: 536 passed, zero failures or skips.
- Standard system text: all four typography, recovery, message readability,
  and layout-transition checks passed.
- Maximum accessibility text: the same four checks passed. Both app and test
  runner reported the required actual UIKit category.
- The warning gate passed. All three result summaries report zero runtime warnings.

The full run exposed low contrast in the inline status explanation, corrected
by using the primary text color. A draft-preservation test also attempted to
edit a field covered by an existing banner; it now creates the draft before
presenting the error and still verifies that dismissal preserves the draft and
leaving Settings clears it. The corrected test passed individually and in the
final full suite. The earlier failed runs remain diagnostic evidence.

The live Internal Beta workflow was read back using the existing protected API
key. It remains enabled on Latest Release Xcode, with the latest selected iOS
runtime, required tests, and an internal-only Beta archive. Its automatic
internal TestFlight distribution configuration was preserved. Cloud execution
and distribution are separate from this local validation.

## Current feedback verification (November 9 follow-up)

Simulator startup recovered after restarting the stale CoreSimulator service
and cold-booting the isolated iPhone SE (3rd generation), iOS 27.2 device. No
simulator data was erased, no runtime was removed, and stable Xcode 27.2 (27B52)
remained selected. The first automation launches were slow; subsequent XCTest
sessions successfully launched, navigated, dismissed banners, and exercised
recovery. Prior runtime installations and service-version transitions were
observed; the exact cause of the earlier service interruption is not proven.

Final focused verification passed on iPhone SE (3rd generation), portrait,
iOS 27.2. Evidence is retained under `TestResults/inline-feedback/`:

| Check | Final evidence |
| --- | --- |
| Standard text | `standard-final-summary.json`: 4 passed, 0 failed, 0 skipped. App and test runner both reported `UICTContentSizeCategoryL`. |
| Maximum accessibility text | `maximum-final-summary.json`: 3 passed, 0 failed, 0 skipped. App and test runner both reported `UICTContentSizeCategoryAccessibilityXXXL`. |
| No layout movement | Each run recorded 13 identical physical-layout snapshots through progress phases, error appearance/dismissal, a repeated identical error, important notice appearance/dismissal, and ordinary success. Raw values are in the corresponding `*-layout-evidence.txt` files. |
| Dismissal and recovery | Close remains reachable; dismissal preserves inline failure/recovery and important notice text. Tab navigation does not revive a dismissed message. A later failed attempt creates a new message. Connection recovery opens Settings. |
| Large-text readability | The full banner action fits inside its viewport, native action targets meet the 44-point minimum, Sync Now has no clipped letters, and the retained notice's final line is readable. Screenshots were visually reviewed. |
| Source and build | All 113 captured Swift, project, and validation files match their pre-run hashes (`verified-source-check.txt`). Both validation runs exited successfully with no build warnings or result-bundle runtime warnings. |

The tests measure the native status Form cell, navigation and tab bars, plus
instantiated downstream controls. At maximum size the lower rows can be
virtualized; a separate scrolled-position check measures Sync Now while visible.
Assertions allow 0.5-point floating-point tolerance; the logged baseline frame
values were identical. Accessibility text-group bounds are logged separately
because they represent their current children rather than the Form allocation.

Verification found and corrected two UI problems: the recovery button's minimum
touch target needed to be applied inside its label, and the maximum-size Sync
Now label needed the full button width. New message identities also reset the
banner's internal scroll position. The first maximum-size test additionally
exposed a test gesture that scrolled the outer Form instead of the message;
the corrected helper uses the visible viewport and retains final-line and
whole-button assertions. Failed earlier bundles remain diagnostic records.

The synthetic state driver is DEBUG-only and additionally requires screenshot
mode plus its dedicated argument. It performs no network requests or Health
writes and is absent from Beta/Release builds. Both feedback tests are now
included in the existing pre-release text-size validation loop, which verifies
the actual app and runner categories. The simulator text setting was restored
to its original `large` value after testing.

These focused simulator checks preceded the full release validation recorded
above. Physical-device acceptance remains separate.

## Historical validation: superseded feedback design

These results describe the earlier toolbar-and-sheet implementation. They
remain useful evidence for the earlier revision and unchanged review findings,
but the source hashes no longer describe the inline-feedback revision.

The complete local preflight passed under `final-source-preflight/` using
Xcode 27.2 (27B52) and the iPhone SE iOS 27.0 runtime. The full suite and both
text-size runs have no failures, skipped tests, build warnings or reported
runtime warnings. All 126 source hashes match the starting snapshot, including
the test files and validation scripts. Raw logs, screenshots and result bundles
are retained under `TestResults/ui-refinement-20261109/`. This is local
validation; no Xcode Cloud build or TestFlight distribution was started.

Verified results:

| Check | Result and evidence |
| --- | --- |
| Complete unfiltered suite | `final-source-preflight/full-summary.json`: 530 passed, 0 failed, 0 skipped. |
| Actual standard text size | `final-source-preflight/recovery-large-summary.json`: typography and connection recovery both passed. UIKit reported `UICTContentSizeCategoryL`. |
| Actual maximum text size | `final-source-preflight/recovery-accessibility-extra-extra-extra-large-summary.json`: typography and connection recovery both passed. UIKit reported `UICTContentSizeCategoryAccessibilityXXXL`. |
| Frozen source | `final-source-preflight/source-verification.txt`: all 126 hashes match. |
| iPhone SE, iOS 27.2 | `ios27-2-summary.json`: 4 passed, 0 failed; no build warnings in the log or runtime warnings in the summary. |
| iPad, iOS 27.2 | `ipad27-2-summary.json`: 4 passed, 0 failed; no build warnings in the log or runtime warnings in the summary. Representative Settings, Performance and Sync screenshots have no clipping or duplicate toolbars. |
| iOS 26.5 | Inconclusive after an automation/accessibility stall. No verified compatibility claim is made. |

Additional maximum-text conversion and adaptive-navigation cases passed
individually in `maximum-text-details`; recovery and native Done reachability
passed individually in `maximum-text-corrected`. Those bundles failed overall
on other test-helper issues and are not counted as passing gates. The final
gate above uses the corrected helpers and passed completely.

The maximum-text helpers now follow native row order so virtualized rows are
not searched in the wrong direction, use predicate lookup for long paragraphs,
and measure the unobscured region at the native tab-bar edge. The last change
removes an extra test-only margin that rejected fully visible final glyphs at
the scroll limit. Final-line, text-height and interactive-target checks remain.
The native Passwords save prompt is handled explicitly during account tests.
Core-screen audits run in independent app processes without excluding hit-region
checks. Failed and interrupted bundles remain diagnostic records.

Visual readback confirms 18.82:1 contrast for Health and Tandem explanations and
21:1 for conversion factors in light mode. Data Deletion dividers now align
across the full content width. The Performance explanation remains inside
Measurements, where its Dynamic Type audit passed. The earlier regression suite also covered failure persistence through sheet
dismissal, tab changes and session replacement. Its sheet-based feedback checks
have been replaced for the current revision.

Live StoreKit purchases, real Health imports, and physical-device acceptance
remain deferred. This change does not alter the Internal Beta workflow or its
automatic internal TestFlight distribution.

## Design references

- [Apple materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple feedback guidance](https://developer.apple.com/design/human-interface-guidelines/feedback)
- [Apple progress indicator guidance](https://developer.apple.com/design/human-interface-guidelines/progress-indicators)
- [SwiftUI overlay layout](https://developer.apple.com/documentation/swiftui/view/overlay(alignment:content:))

Apple guidance was retrieved through Context7 during planning and checked
against the Xcode 27.2 SDK during implementation. iOS 27 uses native toolbar
overflow; iOS 26 uses a standard export menu.


## Screen examples

These are synthetic simulator fixtures, not live pump records or a distributed
TestFlight build. The test fixture's version text is not release evidence.

### Current inline feedback

Progress stays within the existing Sync form; no toolbar status icon or details
sheet is used. The small advance control in this capture is the test fixture.

![Inline sync progress at standard text size](screenshots/sync-progress-standard.png)

Errors float over the page. Dismissing the message retains inline recovery and
the existing layout.

![Floating error at standard text size](screenshots/sync-floating-error-standard.png)

![Same screen after dismissing the message](screenshots/sync-dismissed-error-standard.png)

At the largest system accessibility size on iPhone SE, long message text scrolls
and Close remains visible. The whole recovery action is reachable. Sync Now
retains native Liquid Glass and uses its full width for readable text.

![Whole banner recovery action at maximum text size](screenshots/sync-banner-maximum-text.png)

![Inline recovery and unclipped Sync Now at maximum text size](screenshots/sync-inline-maximum-text.png)

The important notice's final line remains readable after dismissing its banner.
The small advance control in these maximum-text captures is an opt-in DEBUG
fixture for changing synthetic states; it is absent from ordinary app use and
Beta/Release builds.

![Final line of the retained notice at maximum text size](screenshots/sync-notice-final-line-maximum-text.png)

### Earlier review examples

The captures below predate the inline-feedback revision. Their status icon is
superseded; the other screens remain reference evidence for earlier reviewed
content.

### PumpSync connection configuration

Subscription management is part of the PumpSync option. The description omits
the redundant manage/restore instruction.

![PumpSync settings with subscription and shortened service description](screenshots/hosted-settings-light.png)

### Self-hosted connection configuration

The editor contains the mode picker, HTTPS endpoint and native Connect action.
The example uses `/api`; custom base paths are also supported.

![Self-hosted settings with endpoint and native Connect action](screenshots/self-hosted-settings-light.png)

### Apple Health

![Native Health labels and readable explanation](screenshots/health-light.png)

### Tandem account editor

![Native Tandem fields and Save action in one section](screenshots/tandem-edit-light.png)

### Data Deletion

The description, native email action and privacy link share aligned dividers.
The email icon appears once, and the distinction between server metadata,
Apple Health samples and subscriptions sits in the footer.

![Data Deletion with consistent dividers, native actions and readable footer](screenshots/data-deletion-light.png)

### Insulin Conversion

Symbol-led rows explain the U-100 source baseline, concentration multiplier and
Apple Health destination without repeating the current selection. The remaining
rows explain when changes apply and retain the concentration-check guidance.

These captures come from the conversion test in the successful unfiltered run
`accepted-preflight/full.xcresult`. The separate standard- and maximum-text
checks are reported in the overall validation status above.

![Insulin Conversion with native symbols and no duplicate Current Selection section](screenshots/conversion-overview-light.png)

| Conversion factors | When changes apply |
| --- | --- |
| ![All three conversion factors rendered in primary text](screenshots/conversion-factors-light.png) | ![Conversion timing, unchanged pump settings and concentration-check guidance](screenshots/conversion-guidance-light.png) |

### About PumpSync

How Sync Works includes the requested manual-sync wording and the matching
Last successful sync row.

![About PumpSync with four consistent How Sync Works rows](screenshots/about-sync-light.png)

### Developer

Diagnostics use native navigation and action rows. The duplicate account/server
section is removed, and the support-bundle explanation is shorter.

![Developer diagnostics with native actions](screenshots/developer-light.png)

### App Event

Known import-preview fields appear as readable Summary rows. Log Details keeps
the underlying entry available separately; copy and share remain native toolbar
actions.

![App Event with readable preview summary and Log Details disclosure](screenshots/app-event-light.png)

### Performance report

Measurements describe the reporting period, and the disclosure is named
Report Data. Native glass remains in the navigation and export controls.

![Performance report with measurements, reporting-period explanation and Report Data](screenshots/performance-light.png)

### Superseded Sync screenshots: toolbar and details sheet

The owner rejected this feedback design. These captures are retained as a
historical record only; they do not show the current implementation. The status
icon and Sync Details sheet shown here have been removed from source.

| Earlier ready state | Earlier running state |
| --- | --- |
| ![Superseded Sync ready screen with toolbar status icon](screenshots/sync-ready-light.png) | ![Superseded Sync running screen with toolbar status icon](screenshots/sync-running-light.png) |

| Earlier progress sheet | Earlier recovery sheet |
| --- | --- |
| ![Superseded Sync Details progress sheet](screenshots/sync-progress-details-light.png) | ![Superseded Sync Details recovery sheet](screenshots/sync-recovery-details-light.png) |

Data Deletion and the historical Sync Details captures came from completed
screen checks in `final-preflight/`. They remain separate from the current
revision's completed focused validation under `TestResults/inline-feedback/`.
