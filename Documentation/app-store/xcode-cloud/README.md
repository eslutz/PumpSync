# Xcode Cloud workflow configuration

## November 7 design remediation

API readback confirmed **Latest Release Xcode**, currently 27.2 (`27B52`), and iPhone SE (3rd generation) / iOS 27.2 on PumpSync Validation, PumpSync External Beta, and PumpSync App Store Release.
The previous iOS 27.0 destination is unavailable under the current Cloud toolchain; local compact preflight remains on iOS 27.0 with Xcode 27.2.

The existing PumpSync Internal Beta workflow remains unchanged on Xcode 27.1 / iOS 27.0.
Updating its actions through the API returned `Deployment configured for unknown action`; changing only Xcode returned `Invalid runtime` for iOS 27.0.
Repair that workflow through App Store Connect before using it; do not remove its distribution action to make an API update succeed.
Browser configuration is currently blocked by the locked Mac.

For this release, the updated PumpSync External Beta workflow runs the required tests and Beta archive without a distribution post-action.
Despite its name, starting that workflow does not add a build to external testers.
After successful validation and processing, add the resulting build only to the existing Internal Testers group.

Configuration rollback/readback evidence: `workflows-before-2026-11-07.json` and `workflows-after-2026-11-07.json`.
The latter contains the three successfully updated workflows; Internal Beta is unchanged.
Restore the saved Xcode relationship and matching test destinations together if rollback is required; retain triggers, archive configuration and distribution scope.

Cloud validation run 52 and Beta tests/archive run 53 were started against frontend commit `8e3ebf17b1fcb16ea940b4a21841d7f128127875`.
Both runs succeeded: 467/467 tests each on iPhone SE (3rd generation) / iOS 27.2, and the Beta archive succeeded. Build 53 processed as VALID and was added only to Internal Testers; API readback verified group membership and IN_BETA_TESTING. Test counts and distribution readback are retained in the dated JSON evidence here. Physical-device acceptance remains deferred by Eric Slutz.

## November 5 release preparation

Two additional manual workflows were created and read back in App Store Connect:

| Workflow | ID | Tests | Archive | Distribution |
| --- | --- | --- | --- | --- |
| PumpSync External Beta | `62e8529f-3823-4866-ba93-0f7a82d14eac` | Required full suite, `PumpSync` | `PumpSync Beta` / Beta | App Store Connect; no distribution post-action |
| PumpSync App Store Release | `752ce628-544a-43dc-b9f0-08b041e2ae9e` | Required full suite, `PumpSync` | `PumpSync` / Release | App Store Connect; no distribution post-action |

Both inherit Xcode 27.1 (27A9275), the existing single test destination, cached builds, and manual branch starts. No branch/PR/tag/schedule automation was added. Neither workflow has run, and their saved configuration is not proof of hosted build or distribution acceptance. The internal and validation workflows were preserved. The external testing group exists separately and has no candidate or public link yet.

The October JSON files below remain historical evidence and do not contain these new workflows. See [release preparation status](../release-status-2026-11-05.md) and its screenshot evidence for the current verification limits and blockers.

## October 22 baseline

Saved and independently read back on October 22, 2026.

| Workflow | Start | Actions | Destination | Clean |
| --- | --- | --- | --- | --- |
| PumpSync Validation | Manual, any branch | Required full unit and UI suite using `PumpSync` | iPhone SE (3rd generation), iOS 27.0 | Off |
| PumpSync Internal Beta | Manual, any branch | Same required tests plus `PumpSync Beta` archive | iPhone SE (3rd generation), iOS 27.0 | Off |

Both workflows use Xcode 27.1 (27A9275) and Latest Release macOS.
The internal beta workflow retains its TestFlight Internal Testing - iOS post-action and Internal Testers group.
Validation has no archive or post-actions.
No automatic branch, pull request, tag, or schedule triggers are configured.

Run `bash Scripts/ios/validate-cloud-tests.sh` before starting either workflow, as required by the frontend guide.
Use validation for routine checks and Internal Beta only when a new tester build is intended.
The beta workflow reruns tests on its own source revision; a separate validation pass alone does not authorize distribution.
The single Cloud destination does not establish acceptance on other devices or OS versions.

The saved settings were checked through the UI and independently through the App Store Connect API.
No Cloud build was started as part of this configuration change, so runtime savings, successful cache reuse, and post-change TestFlight delivery remain unmeasured.
The first run of a new workflow may need to populate its cache.

## Evidence and rollback

`workflows-2026-10-22.json` records the two saved workflows.
`workflow-before-2026-10-22.json` preserves the original internal beta settings.
To roll back, restore the original Recommended iPhones/default-runtime test destination, enable Clean, and restore the original description on Internal Beta.
Deactivate PumpSync Validation rather than deleting its build history.

The App Store Connect API returned HTTP 405 for create/update requests during this change; saves were completed through App Store Connect in Codex Browser.
Read-only API verification succeeded.
