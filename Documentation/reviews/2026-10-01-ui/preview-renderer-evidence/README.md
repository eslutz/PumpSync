# Test-target preview rendering evidence

Captured 2026-10-01 from `ImportPreviewTests.testCaptureTestTargetPreviewRendererEvidence`.
These images use the production `ImportPreviewView`, controller, API request path and import planner, supplied synthetic records and cached authentication from the **test target only**. They do not prove hardware authentication, backend availability, real-device Health preservation, VoiceOver or Apple acceptance.

- `4656CC6F-29D4-4A99-9B61-54567608FF0C.png`: standard light iPhone geometry, three records including a basal interval; U-200 conversion is visible.
- `6E6A9EAE-4897-4860-A20B-1719EFC72A2F.png`: AX5 dark at the top of the scrollable content. Rows are below the fold.
- `81E357E2-A0E9-417F-A723-72C6D6B53A61.png`: virtual iPad-width geometry rendered on the audit iPhone simulator, not an actual iPad run.
- `A5BB17C0-B29C-4FB2-B970-B3370C1370E9.png`: empty successful preview, accurately labeled as zero downloaded records.
- `C351F9E7-DD1F-49F9-B1B8-015A2DFA9EA7.png`: 1,000 records, lazy list, downloaded count. This is rendering evidence, not a measured performance benchmark.

Raw run: `/private/tmp/pumpsync-preview-ui-renderer2.log`; result bundle: `/private/tmp/pumpsync-preview-ui-renderer2.xcresult`. The manifest preserves attachment names and test identity. Settled images were inspected. Actual non-fixture Sample Preview discovery, close and reopen also passed in `PumpSyncUITests.testSamplePreviewIsSeparateAndClosesWithoutChangingConnection`.

`test-target-ready-AX5-dark-rows.png` captures the same real view after a test-target-only UIKit scroll at AX5. Inspected basal value/interval, bolus value and carbohydrate wrapping remain readable without row overlap. The first row scrolls behind the system navigation bar as usual. Follow-up run passed, zero warnings: `/private/tmp/pumpsync-preview-ui-renderer3.log` and `/private/tmp/pumpsync-preview-ui-renderer3.xcresult`.
