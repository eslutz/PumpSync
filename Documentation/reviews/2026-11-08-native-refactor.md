# Native iOS refactor implementation evidence

Approved plan: https://chatgpt.com/space/page_709af1cbdd7c819183c410bdf3966d84

Starting revision: `092c5c0b25c5c4efbf507157359b1386c5a970f0`. The untouched source is archived locally under ignored `TestResults/native-refactor-baseline/source`.

## Baseline and comparison method

Xcode 27.2 (27B52), iOS 27.0, isolated iPhone SE (3rd generation). Same synthetic screenshot fixture, same simulator and two XCTest performance cases before/after. Five measured iterations per case; XCTest excludes its warmup. These are simulator measurements, not real-device or real-import evidence.

Baseline focused behavior: 20 tests passed. Raw logs/result bundles: `/tmp/pumpsync-native-baseline.log`, `/tmp/pumpsync-native-baseline.xcresult`. Baseline performance: 2 tests passed, `/tmp/pumpsync-native-baseline-performance.log`, `/tmp/pumpsync-native-baseline-performance.xcresult`.

| Measure | Before mean | Relative standard deviation |
| --- | ---: | ---: |
| Launch until responsive | 3.169 s | 1.286% |
| Settings up/down scrolling elapsed | 2.425 s | 3.187% |
| Scrolling CPU time | 0.371 s | 5.626% |
| Scrolling absolute physical memory | 43.640 MB | 5.851% |
| Scrolling peak physical memory | 43.699 MB | 5.826% |
| Scroll deceleration interval | 0.847 s | 1.455% |

Before post-change measurements, flag >20% increases in launch, scrolling wall time, CPU, or peak memory for investigation; report raw values and variance. Memory *delta* is too noisy (162% RSD) to gate this workload. Scroll deceleration duration is an interaction interval, not a stall measurement. Main-thread stall and actual import timing require signpost traces of a representative workload; do not infer those from launch/scroll timings. Static signposts now permit those observations without including private data.

## Phases 1–7: implementation and evidence

Implemented against starting frontend revision `092c5c0b25c5c4efbf507157359b1386c5a970f0`, following the [approved native-first plan](https://chatgpt.com/space/page_709af1cbdd7c819183c410bdf3966d84). Xcode 27.2 / SDK 27.2 supplies the current APIs; the iOS 26 deployment floor remains. New iOS 27 APIs have explicit availability boundaries.

### 1. Native components and baseline

Replaced the custom `GlassUI.swift` screen/card/control layer with SwiftUI `Form`, `List`, `Section`, `NavigationLink`, `LabeledContent`, native pickers and button styles. Existing `TabView` and navigation ownership remain. Added synthetic `#Preview` states and repeatable launch/Settings-scrolling measurements. The adaptive accent follows the [PumpSync website](https://pumpsync.ericslutz.dev/) blue palette, adjusted for native-material contrast: `#005FA8` in light appearance and `#7EB8FF` in dark appearance. Filled prominent actions use a separate `ProminentActionColor`, `#005FA8` in both appearances, to retain readable white text and symbols; text/background/status colors use system semantics. Native glass stays on appropriate actions and navigation, including diagnostic copy/share controls; reading surfaces use system rows. This follows Apple’s [container guidance](https://developer.apple.com/documentation/swiftui/picking-container-views-for-your-content/) and [materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials).

### 2. Settings and subscription presentation

Settings now has one Connection Configuration section. Subscription status leads to a dedicated screen with Apple’s management sheet, purchase options and one Restore Purchases action. Native `SubscriptionStoreView` retains localized purchase presentation and policy links; its duplicate restore control is hidden because restoration lives in the enclosing subscription flow. A recognized subscription can connect without an App Store synchronization prompt. Self-hosted configuration retains staged validation, Connect, Cancel Changes and the currently active service. The controller owns connection cancellation across navigation between Settings and Subscription.

The actual `SubscriptionStoreView` now uses native `.tint(Color("ProminentActionColor"))` for its controls and `.subscriptionStorePolicyForegroundStyle(Color.accentColor)` for adaptive policy links. This adjustment compiled successfully at 15:50 with no reported errors; the real StoreKit purchase view's rendered contrast has not been measured. The measured dark Sync defect is not evidence of a defect or a verified fix in Apple's purchase view.

Tandem credentials use native fields, saved-account rows and destructive confirmation while retaining password privacy, scene redaction, validation ownership and cancellation. Health access describes permission to **write**. Concentration and its explanation live in Settings; concentration was not added to Sync. [Apple subscription presentation](https://developer.apple.com/documentation/storekit/subscriptionstoreview).

### 3. Subscription access and backend sessions

`StoreKitSubscriptionService` owns verified entitlement reads, explicit restoration and one lifetime transaction listener. Candidate auth services do not create additional listeners. App Store synchronization errors now propagate; canceled restore, unavailable App Store, missing entitlement and backend failure are distinct outcomes. Automatic recovery reads current entitlements without prompting for restoration. App Store access remains separate from a usable backend connection.

Transaction acknowledgement requires delivered access with a committed usable hosted connection and no unresolved submission. Historical inactive updates consult current entitlement state before clearing access. Self-hosted subscription restoration does not replace the active connection. App Attest, environment routing, durable journals and atomic candidate activation remain in their existing owners. [Transaction updates](https://developer.apple.com/documentation/storekit/transaction/updates), [explicit restore guidance](https://developer.apple.com/documentation/storekit/appstore/sync()).

### 4. Sync and diagnostic presentation

Sync presents last success and **records received before samples saved**, with separate last-check and connection information. Counts remain attached to the same attempt; no duplicate/skipped count is invented by subtraction. Diagnostic app events group retained snapshots by operation, with outcome/reason first and an optional stage timeline. Performance details distinguish reporting windows, retained measurements, timestamp-only reports and legacy summaries. Sanitized technical text is expandable; copy/share retain the existing privacy handling. Category-specific clearing, native empty states and localized display dates replace the old repetitive presentation; exports retain exact timestamps.

The owner-confirmed U-100 source contract and existing concentration factors **1 / 2 / 5** for U-100 / U-200 / U-500 are unchanged. Carbohydrates remain in grams. Running imports retain their captured concentration. The Health submission boundary still revalidates source/configuration ownership, cancellation and execution lease immediately before saving, without adding a suspension between that fence and submission. Existing Health samples are not rewritten.

### 5. Networking and concurrency

Replaced unsafe shared date formatters with Foundation value-format parsing and fresh codecs. Regression coverage includes whole/fractional seconds, offsets, malformed dates, independent decoder configuration and concurrent decoding. The previous millisecond truncation remains, including seven-digit wire fractions. Requests snapshot URL, session, timeout, retry policy and encoded body so settings changes cannot redirect retries.

Measured decoding justified a narrow `@concurrent` response decoder with explicitly `Sendable` values; UI-observed connection state and inexpensive request encoding remain on MainActor. Imports/previews remain cancellation-aware. Received enrollment/refresh responses and definitive rejections remain available for guarded durable journaling even after their waiter cancels. Ephemeral URLSession configuration and protected-request redirect denial remain. [Foundation URLSession](https://developer.apple.com/documentation/foundation/urlsession).

### 6. Native performance reporting

The iOS 27 path consumes `MetricManager.metricReports` and `diagnosticReports`; iOS 26 uses an availability-scoped legacy subscriber. Each live collector owns one ingestion path and releases/cancels its observers/tasks. Typed adapters project explicitly reviewed measurements into the existing sanitized report model, preserving windows, units, app/build context and empty-report honesty. Daily aggregates are not added to their component intervals. Native APL units, exit categories, suspended-memory averages, launch/hang histograms and location-duration aggregates are retained; arbitrary raw Codable reports and state labels are not exported.

Static Logger/signpost events cover session recovery, request encoding/download/decoding, import conversion, Health submission and report normalization. They contain no credentials, URLs, account identifiers or health values. The bounded user-exportable support log remains. [MetricKit reporting](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit), [native logging](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code).

### 7. Conditional background and storage changes

No persistence migration or background-task replacement is justified by the available evidence. Keep `BGTaskScheduler` for unattended sync, its deadline/expiration handling, lease revocation, durable checkpoints and single completion. `BGContinuedProcessingTask` remains a separate option only if representative manual-import device traces establish a need for foreground-started continuation. It is not a recurring-sync guarantee. [Background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app).

Native reports already use protected atomic files capped at 50 entries; the support log and attempt history are bounded at 200 and 20. The import ledger retains its existing 5,000-entry/370-day policy with current-batch protection and device-only key storage. A synthetic Mac persistence probe retained 50 reports / 29,951 bytes; 20 writes had a 13.1 ms median and 95.0 ms maximum. Observation was excluded from that isolated probe and concurrent host work may affect it. These numbers do not prove device writes are cheap; retain device I/O profiling as a follow-up, rather than migrating storage or introducing SwiftData without a demonstrated benefit and migration/rollback design.

## Measurement results and limits

The final full gate passed on the frozen implementation source, now committed as `2b51495fb638642b7a09ffaaf68c08a856f773bd`. These measurements come from its `full.log`, not the outer console containing the later recovery reruns. Baseline and final measurements use Xcode 27.2, iOS 27.0, the same isolated iPhone SE (3rd generation), synthetic fixtures and five measured XCTest iterations per case. They remain simulator measurements, not real-device or real-import evidence.

| Simulator measure | Before mean | Final mean | Change | Before RSD | Final RSD |
| --- | ---: | ---: | ---: | ---: | ---: |
| Launch until responsive | 3.169 s | 3.426 s | +8.1% | 1.286% | 4.608% |
| Settings scrolling elapsed | 2.425 s | 2.544 s | +4.9% | 3.187% | 9.772% |
| Scrolling CPU time | 0.371 s | 0.371 s | 0.0% | 5.626% | 5.186% |
| Scrolling absolute physical memory | 43.639618 MB | 47.385024 MB | +8.6% | 5.851% | 0.049% |
| Scrolling peak physical memory | 43.698600 MB | 47.702874 MB | +9.2% | 5.826% | 0.027% |
| Scroll deceleration interval | 0.847 s | 0.690 s | −18.5% | 1.455% | 1.176% |

No predeclared launch, scrolling elapsed, CPU-time or peak-memory measure exceeds the **20% increase** investigation threshold. Scrolling elapsed has greater dispersion than baseline, so the small mean increase does not establish a reliable slowdown. Memory delta remains too noisy to gate this workload (final RSD 374.166%); absolute memory and scroll-deceleration duration are descriptive. Deceleration is an interaction interval, not a stall measure. Additional CPU counters increased: cycles **816,050.082 → 1,084,236.634 kC (+32.9%)**, instructions **1,387,730.822 → 1,637,313.386 kI (+18.0%)**. Those counters were not the predeclared CPU-time gate and do not establish device energy impact; CPU time remained 0.371 s at the reported precision.

The final raw samples and calculated sample variance (denominator n−1) are:

| Measure / raw unit | Five final samples | Sample variance |
| --- | --- | ---: |
| Launch / s | 3.249311, 3.293925, 3.359007, 3.639915, 3.586180 | 0.0311418944 s² |
| Scrolling elapsed / s | 2.865701, 2.790175, 2.238447, 2.504473, 2.320442 | 0.0772491867 s² |
| CPU time / s | 0.382250, 0.393261, 0.341151, 0.381056, 0.355703 | 0.0004619250 s² |
| Absolute physical memory / kB | 47,401.408, 47,417.792, 47,352.256, 47,368.640, 47,385.024 | 671.088640 kB² |
| Peak physical memory / kB | 47,696.320, 47,712.704, 47,712.704, 47,679.936, 47,712.704 | 214.748365 kB² |
| Deceleration / s | 0.700140, 0.683936, 0.699962, 0.683201, 0.683333 | 0.0000823607 s² |

MB uses decimal conversion from XCTest's reported kB. RSD and rounded means above are XCTest's reported values; calculated sample variance is separately identified. Raw baseline: `/tmp/pumpsync-native-baseline-performance.log` and `.xcresult`. Final source: `TestResults/native-refactor/release-final-20261108T2150Z/full.log` and `full.xcresult`; extraction with metric identifiers, baseline/final samples and variance: `/tmp/pumpsync-native-final-extraction.json`. The final log SHA-256 is `ffc11986684130541361ae7cf07a455b8fe976ac78978295d8ec7ec1a8c6039f`.

An independent optimized Mac probe decoded synthetic responses using the actual `SampleDTO` decoding path. Median of five rounds:

| Records | Encoded bytes | Previous parser | Native value parser |
| --- | ---: | ---: | ---: |
| 100 | 25,937 | 17.68 ms | 1.53 ms |
| 1,000 | 258,137 | 146.65 ms | 15.26 ms |
| 10,000 | 2,580,137 | 1,416.09 ms | 148.08 ms |

Small request encoding had a 0.0025 ms median over 100 rounds. Probe source: `/tmp/pumpsync-native-probes/codec-benchmark.swift`. These isolated CPU timings support moving substantial decoding off the UI executor. They do not measure network time, end-to-end import duration, Health writes, battery impact or real-device responsiveness. Real-device import/stall traces and actual system MetricKit delivery remain separate evidence; synthetic adapter tests establish normalization behavior only.

## Native readability corrections and verification

The initial accessibility run reported 98 findings across the core-screen and new-detail audits (`TestResults/native-refactor/accessibility-fixes-console.log`). Moving essential instructions from secondary footers into body rows, increasing native section-header prominence, using semantic primary text, and allowing native labels/values to wrap reduced the next run to 34 findings (`native-readability-console.log`). The Subscription and Performance audit passed all five checks in that run: contrast, hit region, text clipping, Dynamic Type and sufficient element description. The remaining core findings were investigated individually; the count reduction alone is not acceptance.

Actual iPhone SE / iOS 27.0 inspection changed and read back the system text setting from standard to maximum accessibility size, then restored it. Screenshots show the named Sync, Settings, About and Health body text growing and wrapping, with complete final lines reachable by scrolling. For those inspected elements, the predictive scaling/clipping reports did not correspond to lost text or a fixed font. The same inspection found real truncation of the large About and Health navigation titles; pushed detail screens now use native inline titles. Evidence and coverage limits: `TestResults/native-refactor/visual-compatibility/se-text/observations.md` and its referenced screenshots. Tandem's username row also now exposes the contextual accessibility label “Tandem username” and its value as one native accessibility element; the account-edit label explicitly permits wrapping.

Core-screen verification audits contrast, hit regions and semantic descriptions. Its predictive Dynamic Type/clipping checks are replaced by a strict gate using the actual UIKit text category, preferred body line height, measured label growth and final-line scroll reachability at standard and maximum system text sizes. This is a measured replacement for those checks, not a blanket known-issue exclusion. The new Subscription/Performance detail audit retains all five audit types, with the narrowly measured iOS 26.5 header exception described below. Focused typography and contrast verification passed; evidence includes `TestResults/native-refactor/typography-gate-console.log` and `contrast-verification.xcresult`. The core contrast audit permits the Sync Now glass button only when its rendered foreground/background measurement meets the normal-body-text threshold of 4.5:1; there are no hit-region or semantic-description exceptions. This is not a claim that every native audit is unsuppressed.

Strict iOS 26.5 compatibility testing reported contrast on the fully visible promoted **Performance metrics** header at frame `(16, 116, 370, 44)`. Original PNG glyph/background measurements were black on `#F2F2F7`, **18.819:1**. Explicit primary styling did not resolve the report, and a fresh contrast-only run reproduced it, so multiple-audit sequencing was not necessary to trigger it. Evidence is retained in `TestResults/native-refactor/runtime-compatibility-26-isolated-audit-20261108T2123Z/REPORT.md`, its PNGs and `header-pixel-measurements.json`. The test now accepts only an iOS 26.5 Performance contrast issue whose existing static-text element has that exact label, is fully unobscured and independently passes the current rendered-pixel helper at **7:1 or better**. Nil elements, unrelated nodes and every other issue type still fail. The pixel helper moved unchanged into a shared `XCTestCase` extension; Performance starts from a fresh app and runs contrast separately for precise diagnostics. Read-only peer review found no blocking false-pass path in these conditions. The later passing compatibility run measured this exact header at **18.640589730036634:1** through the live helper; this limited exception is not an unsuppressed-audit claim.

The next guard investigation found a floating-point boundary mismatch: header y **116** versus navigation boundary **116.00000000000004**, a **4.26 × 10⁻¹⁴-point** difference, incorrectly rejected visibility. The comparison now permits **10⁻⁶ points** of numerical tolerance, far below one pixel and insufficient to permit visible occlusion. All exact-header, iOS 26.5, contrast-only and current-pixel ≥7:1 requirements remain. Evidence: `TestResults/native-refactor/runtime-compatibility-26-guard-20261108T2135Z/REPORT.md`. The 16:37:44 build reported no errors, and the subsequent serial compatibility verification passed as recorded below.

Rendered color measurements also found genuine contrast issues. The initial native glass blue rendered as sRGB `(0, 131, 199)`, giving white text approximately **4.14:1**, below the normal-text target. The first light-accent correction to **`#005FA8`** rendered as `(0, 115, 181)`, giving white text **5.0977:1 (approximately 5.10:1)**. This independent measurement is used instead of the test helper's higher quantized-color estimate. Evidence: `TestResults/native-refactor/rendered-glass-srgb-contrast.txt` and `rendered-glass-final-contrast.txt`. Subsequent dark-appearance inspection found white text on the pale adaptive accent measured only **2.0845:1**. Filled actions now use `ProminentActionColor` **`#005FA8` in both appearances**, while the global accent stays light **`#005FA8`** / dark **`#7EB8FF`**. Corrected dark Sync glass rendered as `(0, 95, 168)`, giving white text **6.5578:1 (approximately 6.56:1)**, with its white symbol visibly present. Exact pixel samples and screenshots: `TestResults/native-refactor/visual-compatibility/final-se/contrast-measurements.json` and `observations.md`. The native red “Remove Credentials” entry point measured **3.20:1**; it now uses semantic primary text and a trash symbol for legibility, while keeping the destructive button role and destructive confirmation. This trades the entry point's red color cue for readable text; the destructive action remains explicit. These corrections do not change Health access semantics, concentration conversion or credential privacy.

The first full `release-preflight` run passed all **466 unit tests**; its UI target ran **47 tests: 38 passed and 9 failed**, including a passing performance subset. That failed run remains part of the investigation record. After the corrections below, the final complete local gate passed **513 of 513 tests**, followed by both required recovery/typography reruns. Cloud, distribution and human acceptance remain separate from these simulator results.

### UI reachability investigation — retained failed checkpoints

The first full-run failures were investigated against native row behavior rather than retried unchanged. Five failures assumed Developer rows were already visible; tests now reveal the relevant row before asserting or acting. The adaptive scrolling helper queried geometry/identity before a lazy row existed and now scrolls until it is materialized. The inline-progress check needs to reveal progress both initially and after returning from another tab. The U-200 selection check relied on stale menu-closing speech; its corrected assertion verifies the selected value. Raw evidence remains in `TestResults/native-refactor/release-preflight-console.log` and `release-preflight/full-summary.json`.

The concentration menu picker exposed a real **34.5-point native accessibility target**. Row padding, an outer 44-point frame, a minimum height on its label and large control size did not enlarge the native child target. A physical tap near the upper edge of the required 44-point area also failed: target frame `(32, 127, 311, 34.5)`, tap `(321, 122.35)`. Evidence: `TestResults/native-refactor/picker-geometry-console.log` and `native-picker-hit-area-console.log`. Those sizing attempts were reverted. The dedicated concentration screen now uses Apple's built-in inline picker with its duplicate label hidden, exposing the three native choice rows directly. This introduces no custom selection control; its targeted verification is recorded below.

Separately, Installation ID had duplicate VoiceOver output because an explicit accessibility value repeated the native `LabeledContent` value. Removing that redundant value preserves the native row and explicit Copy action; the copy test passes.

The focused `TestResults/native-refactor/ui-corrections.xcresult` run passed **5 of 7 tests**: core screen rendering, adaptive reachability, Installation ID copy, Sync/Settings/Developer rendering, and region/concentration selection. The subsequent `native-target-progress.xcresult` passed the inline-progress check both initially and after tab navigation; its only failure was the old menu picker's target height. These are investigation checkpoints, not final acceptance.

### Verified follow-up checks

- **Inline concentration:** the touch test in `TestResults/native-refactor/concentration-inline.xcresult` passed for all three native choices, each at least 44 points high. Upper- and lower-edge taps select the intended row, retain one checkmark and update the explanation to factors **1 / 2 / 5**. The first VoiceOver assertion failed solely because it expected capitalized “Selected”; after making the semantic trait check case-insensitive, `concentration-inline-voiceover.xcresult` passed with exact native speech **“selected U-200 Button”**, U-200 spoken once and the selected trait present.
- **Actual maximum text:** `TestResults/native-refactor/max-type-final.xcresult` passed **2 of 2 tests**, covering connection recovery and native typography/final-content reachability. UIKit reported `UICTContentSizeCategoryAccessibilityXXXL`; preferred body line height was **63.248046875 points**, versus **20.287109375** at standard size, and the Samples Saved label measured **125.5 points** high. All checked final lines remained reachable. The exit trap restored standard text size. Build succeeded at 15:27 with no reported errors, and the subsequent maximum-text run also compiled successfully.
- **Visual evidence:** `TestResults/native-refactor/visual-compatibility/final-se/observations.md`, its images and `contrast-measurements.json` record corrected dark Sync contrast, preserved native glass Performance controls, and maximum-text layouts for Performance, Subscription and concentration. These are simulator checks using synthetic data.

The subsequent public-XCTest accessibility-settings probe enabled **Reduce Motion and Reduce Transparency**, verified both actual UIKit flags were true, and exercised Sync, Performance, copy and disclosure. It restored both switch values to `0`, both UIKit flags to false and the standard text category `L`. The raw probe remains **failed with three contrast findings**. Screenshots and crops independently showed those named nodes behind the floating tab bar; that explanation does not turn the failed run into a pass.

The same inspection separately found a visible Performance value rendered as **`#8A8A8E` on white, 3.4389:1**, insufficient for normal body text. The audit missed that value inside a combined accessibility row. The correction applies semantic `Color.primary` to native value `Text` closures in Performance and App Events, and the matching subscription-status and concentration-explanation rows, retaining native `LabeledContent` controls and layout. It built successfully at **15:57:03 with no reported errors**. Final unedited Performance screenshots verify visible values at **21:1 in light appearance** (black on white) and **17.0147:1 in dark appearance** (white on `#1C1C1E`); visible first/final expanded technical text is readable and its final line is scroll-reachable. This closes the measured visible-value defect, without implying that combined-row audits detect every contrast defect.

Final reduced-settings interactions and pixel checks passed separately from the temporary whole-tree audits, which remain **failed**. Both actual UIKit Reduce Motion/Reduce Transparency flags were true during observation and restored false afterward; standard `large` text and light appearance were restored and read back. All simulators were shut down before serial compatibility validation began. The final probes logged and excluded only wholly occluded contrast samples; partial samples and unresolved visible, hit-region and semantic findings remained strict. Retained partial-navigation failures include Samples Saved at y62.75–83.25 and Time Zone at y54.25–74.75, against content starting at y74. The first expanded-text capture also extended beyond the viewport. Those sampling artifacts do not constitute a clean full audit. Evidence, raw failed-result references, pixels and restoration records: `TestResults/native-refactor/visual-compatibility/reduced-settings/REPORT.md` and its `final-light*` / `final-dark` directories. These screenshots have both reduced settings enabled and must not be presented as the default Liquid Glass appearance; the review Page's earlier Performance illustration still needs a fresh default-settings capture after the test gate.

An actual **iPad / iOS 27.0 window resize** passed through public XCTest without warnings: the app window changed from **1032 × 1376** to **375 × 798** and back to **1032 × 1376**, while screen bounds stayed unchanged. Native top tabs adapted to compact bottom tabs and back. Subscription navigation and the exact synthetic unsaved server draft `https://resize.example/api` survived the changes; Cancel Changes restored the hosted configuration. A visible software keyboard and the focused, hittable field were captured, providing direct keyboard-occlusion evidence. No keyboard or windowing preferences were changed, and the iPad simulator was shut down afterward. The initial probe's expansion-coordinate mistake remains recorded; the corrected continuation passed. Evidence: `TestResults/native-refactor/visual-compatibility/ipad-resize/`, including both probe logs, geometry, hierarchy and screenshots.

Serial runtime compatibility verification passed on unchanged compiled products:

| Runtime | Passed | Expected API-availability skips | Failed | Non-fixture startup |
| --- | ---: | ---: | ---: | --- |
| iOS 26.5 | 468 | 6 | 0 | Exactly one legacy MetricKit collector |
| iOS 27.2 | 474 | 0 | 0 | Exactly one async MetricKit collector |

Each runtime ran the 466-unit suite plus eight representative UI checks. The six iOS 26.5 skips concern unavailable iOS 27 APIs; no UI tests were skipped. iOS 27.2 passed all five Subscription/Performance audit types without entering the iOS 26.5 measured-header branch. Both runtimes verified all **25 compiled artifact hashes** unchanged, recorded zero runtime/driver warnings, restored original settings and shut down their simulators before returning ownership for the full gate. Evidence: `TestResults/native-refactor/runtime-compatibility-final-20261108T2138Z/REPORT.md` and its per-runtime logs, result bundles, hashes and cleanup records. Startup proves collector-path selection, not delivery of a real system report.

The **Beta simulator compile succeeded in 32.7 seconds**, with empty warning/error diagnostics (`TestResults/native-refactor/beta-compile.log`). This is a compile result, not a signed archive or distribution result.

The required local gate completed successfully on **2026-11-08 at 17:30 EST**, using Xcode 27.2 (27B52), iOS 27.0 (24A434) and the isolated iPhone SE (3rd generation). `full-summary.json` records **513 passed, 0 failed, 0 skipped**: 466 unit tests and 47 UI tests, including the two performance cases. The required standard and maximum text reruns each passed **2 of 2 tests**; these four additional executions are reported separately from the 513-test full suite. All three summaries contain empty runtime-warning arrays, and all three build/test logs contain zero `warning:` diagnostics.

| Actual system text | Verified UIKit category | Preferred body line height | Samples Saved label height | Recovery + typography/final-content tests |
| --- | --- | ---: | ---: | ---: |
| Standard (`large`) | `UICTContentSizeCategoryL` | 20.287109375 pt | 20.5 pt | 2/2 passed |
| Maximum accessibility | `UICTContentSizeCategoryAccessibilityXXXL` | 63.248046875 pt | 125.5 pt | 2/2 passed |

The script verified both actual categories, then checked **125 of 125 source-manifest entries successfully**, printed `Cloud device preflight passed` and exited **0**. That marker names a local preflight; it does not claim an Xcode Cloud run passed. Evidence root: `TestResults/native-refactor/release-final-20261108T2150Z/`, containing `full-summary.json`, both `recovery-*-summary.json` files, their logs/result bundles, `source-hashes.txt`, `source-verification.txt` and `environment.txt`. The SHA-256 of the manifest itself is `5e6a2b8414210ad4a987cf9e7723226a258144794ab7a2303404de5df1cc3c93`. The recorded starting revision is `092c5c0b25c5c4efbf507157359b1386c5a970f0`; the verified implementation was subsequently committed as `2b51495fb638642b7a09ffaaf68c08a856f773bd`. Documentation is recorded separately. Hosted build, signed archive and automatic internal TestFlight distribution are still pending for this implementation.

Read-only review of the current functionality diff found no actionable verified defects in auth cancellation/durable delivery, candidate activation, historical entitlement handling, Health submission fences or the exclusive MetricKit async/legacy lifetime paths. This source review ran no builds or tests and does not verify live StoreKit redelivery, actual MetricKit reporting or iOS 26 runtime behavior.

## Final acceptance and release status

- Implementation commit: **`2b51495fb638642b7a09ffaaf68c08a856f773bd`**. Final gate source manifest: **125/125 verified**, SHA-256 `5e6a2b8414210ad4a987cf9e7723226a258144794ab7a2303404de5df1cc3c93`.
- Local full unit/UI gate: **passed, 513/513, no failed or skipped tests, no compiler/runtime warnings**. Result: `TestResults/native-refactor/release-final-20261108T2150Z/full.xcresult`. The complete preflight exited 0 after all followups and source verification.
- Standard/maximum Dynamic Type: **2/2 recovery and typography/final-content checks passed at each actual category**, with measured label growth above. Appearance, reduced-settings, keyboard and iPad-resize evidence is recorded separately; temporary failed whole-tree audit probes remain failed. The Page's fresh default-settings Performance capture is **pending**.
- iOS 26 legacy-path runtime / iOS 27 path verification: **passed on iOS 26.5 and 27.2**, with the scope, expected skips and measured iOS 26.5 audit exception recorded above.
- Evidence commit, push, hosted build, signed archive and internal TestFlight distribution: **pending** for this implementation; local validation does not establish these outcomes.
- Physical-device and human acceptance: **retain the previously deferred status unless separately performed**. Real-device import/stall profiling, live StoreKit delivery and actual system MetricKit report delivery remain unverified.
