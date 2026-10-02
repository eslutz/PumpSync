# Xcode Cloud Build 38 test diagnosis

## Verified failure and reproduction

[Build 38 test results](https://appstoreconnect.apple.com/teams/1f3fb703-e0b0-42fc-bc0b-d00a3bfdf58e/xcode-cloud/products/2E9036C0-9B68-4B35-9F7C-1867AB66EAC1/builds/63a8b80d-d262-4a52-ac86-b36e3d7ae6cd/action/17f942d9-9882-4fa7-8743-de7fcd2044f6/results?status=failed) identify **iPhone SE (3rd generation), iOS 27.0**, rather than the iPhone 17 used for earlier local validation. Cloud passed 305/306 tests. The failure was a direct `isEnabled` read for a nonexistent accessibility snapshot of `Connect and Preview` in `testSamplePreviewIsSeparateAndClosesWithoutChangingConnection()`.

The sheet was still presented: the failure snapshot contained its Close button and sample-account pickers. Settings controls behind a presented sheet do not prove that the sheet was dismissed. Earlier scene-lifecycle changes and longer waits did not address this lookup failure.

The unchanged test passed once on the local SE at standard text size. With the simulator's actual text size set to `extra-extra-extra-large`, it failed with the same missing-button predicate while the sheet remained presented. The row was below the visible form. A SwiftUI Form can omit offscreen rows from its accessibility hierarchy; waiting for presentation does not make those rows available. This reproduction identifies the test's offscreen-row assumption; it does not establish the Cloud simulator's exact text setting.

- [Before scrolling](evidence/se-larger-text-before-scroll.png)
- [After scrolling](evidence/se-larger-text-after-scroll.png)
- [Reproduced failure](evidence/reproduced-issue.txt)

The launch-environment `UIPreferredContentSizeCategoryName` check did not actually enlarge this form in the captured local run. The new preflight uses `simctl ui ... content_size` and restores the previous simulator setting on exit.

## Test design

The UI flow now resets orientation, waits for a hittable Close control, and scrolls with a bounded search before reading or interacting with form controls. It waits for dismissal and for the entry action to become enabled. It enters a temporary username before closing, so reopening and checking empty fields tests actual input cleanup. It never submits those inputs or requests a sample download.

Storage and network isolation remain covered by `PreviewBoundaryRegressionTests`, including the connected demo lifecycle preserving live configuration, credential/session bytes, concentration, import ledger, and sync metadata. UI control inspection is not used as proof of those storage boundaries. The scrolling test requires no deployed test hooks or authentication bypass.

The earlier Build 37 workaround left the sheet presented after `close()` released `demoPreviewActive`. Because `start()` requires that flag, the retained sheet could no longer start a new sample connection after backgrounding. A separate UI lifecycle regression test backgrounds the real app, returns, and requires a dismissed sheet followed by a usable fresh preview. It [failed against that workaround](evidence/lifecycle-regression.txt) and passes after restoring background dismissal. Transient inactive states still preserve presentation. This checks the production behavior independently of the offscreen-control assertion, without new deployed test hooks.

Apple documents the distinction between [existence in the current hierarchy](https://developer.apple.com/documentation/xcuiautomation/xcuielement/exists) and [being visible and hittable](https://developer.apple.com/documentation/xcuiautomation/xcuielement/ishittable).

## Required preflight

Run `bash scripts/ios/validate-cloud-tests.sh` before pushing a candidate or starting Cloud. The script pins the observed Cloud Xcode build `27A266a`, iOS 27.0, and SE device type; it rejects substituted Xcode versions and missing runtimes. It runs the complete suite and then five fresh-runner iterations of the preview flow at standard text size and five at maximum accessibility text size. Every iteration must pass; failures are not retried until one passes.

Raw logs, result bundles, summaries, and the source/environment record are retained under ignored `TestResults/`. Hashes of the app, test, configuration, and generated-project files are checked at the end to reject source changes during validation. GitHub CI now prefers the SE device type on its available runtime for small-screen coverage; that CI job is supplementary and does not substitute for the pinned Cloud preflight. Minimum-supported-iOS, iPad, authenticated device, and distribution acceptance remain separate checks.

## Validation record

- Local reproduction, unchanged test at actual larger text: **1 failed**, expected missing `Connect and Preview` snapshot.
- Revised flow on that same layout: **1 passed**, no build-tool warnings.
- Lifecycle regression before restoration: **1 expected assertion failure**. Xcode stalled after printing the completed failed test; that command was terminated and its raw failure log retained. Its incomplete result bundle is not acceptance evidence.
- Completed Cloud-device preflight: **307/307 passed** (291 unit tests and 16 UI tests), zero failures or skipped tests. [Full summary](evidence/full-summary.json).
- Preview flow with fresh test runners: **5/5 at standard text size** and **5/5 at maximum accessibility text size**, zero failures. The device-level summary and raw logs confirm all iterations, even though the top-level summary counts one unique test. [Standard summary](evidence/preview-large-summary.json), [maximum-accessibility summary](evidence/preview-accessibility-extra-extra-extra-large-summary.json), [maximum-accessibility screenshot](evidence/se-maximum-accessibility-after-scroll.png).
- Environment: Xcode 27.0 build `27A266a`, iOS 27.0 simulator build `24A434`, iPhone SE (3rd generation). Tested the working-tree changes on base `fd224b1`; all **83 source/configuration hash checks passed** at completion. [Tested source hashes](evidence/source-hashes.txt). The original simulator text setting was restored and checked.
- Raw evidence: `TestResults/cloud-build38-final/` contains the full and two repeated-run logs, result bundles, summaries, environment record, and source verification. `validate-tests.sh` found no build-tool warning matches in any of these three runs.
- Gate tooling: shell syntax and workflow YAML checks passed. Controlled guard checks rejected both a filtered full-suite argument and a mismatched Xcode build. `git diff --check` passed.

A local pass is evidence about the tested source and environment. Cloud execution and TestFlight assignment must still be observed separately.
