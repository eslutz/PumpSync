# Xcode Cloud workflow configuration

## Lean internal release allocation (November 10)

The owner requested reduced Cloud quota use. The `PumpSync` scheme remains the full, unfiltered unit and UI suite used locally and in GitHub CI. The required local preflight still includes the full suite and standard/maximum accessibility-text checks. No accessibility checks are waived.

The separate `PumpSync Cloud Smoke` scheme runs all unit tests plus two UI smoke checks: app launch and connection-recovery navigation. The Internal Beta test action should use this scheme, remain required, and retain Latest Release Xcode/runtime. The existing required `PumpSync Beta` internal-only archive and automatic Internal Testers distribution must remain unchanged. Verify the live saved workflow before starting a run.

Release requires the full local gate and exact-head GitHub CI to pass before starting Apple Cloud. Expensive accessibility/UI coverage remains local/GitHub, not the Apple release job. GitHub and the mandatory compact local gate use iOS 27.0; this is not equivalent to exhaustive coverage of Apple's latest runtime. Verify any known latest-runtime failure locally before release; physical-device acceptance remains separate.

Cloud run 57's test action elapsed 60m54s, versus 2m33s for its failed archive action. These are action wall-clock durations, not measured billed quota. Its core-screen accessibility test stalled waiting for app idle after a Developer-screen swipe and timed out at 600s; the root cause is not proven. Its archive also reused already-uploaded build 57. Neither failure is waived by this allocation change.

## November 8 Internal Beta repair

PumpSync Internal Beta is repaired and saved through App Store Connect's web editor.
It now selects **Latest Release Xcode** (currently 27.2, `27B52`), with iPhone SE (3rd generation) using **Latest from Selected Xcode** (currently iOS 27.2, runtime identifier `default`).
This replaces the fixed 27.1 toolchain and 27.0 runtime without pinning future stable releases.

Reloaded web-editor and independent API readback verified the saved configuration.
The existing test and archive action IDs are unchanged: required full tests use `PumpSync`, and the required `PumpSync Beta` archive retains `INTERNAL_ONLY` distribution preparation.
The original **TestFlight Internal Testing - iOS** post-action still references **Archive - iOS** and the **Internal Testers** group.
Manual start for any branch, cached builds, macOS selection and other start conditions are unchanged.
No new build was started for this configuration repair; a subsequent Internal Beta run is the execution/distribution gate for the repaired configuration.

Before/after settings and verification: [repair record](internal-beta-repair-2026-11-08.json).
Screenshots: [saved workflow and automatic post-action](evidence/2026-11-08/internal-beta-repaired.png), [saved runtime alias](evidence/2026-11-08/internal-beta-runtime.png).
Rollback restores the before-record's Xcode relationship, matching test runtime and description together through the web editor; retain the existing action IDs and TestFlight post-action.

The November 7 Internal Beta API-repair limitation below is historical and is resolved by this web-editor repair.

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

## API-key CLI fallback

When Cloud cannot start, an explicitly authorized local delivery can use the existing team API key and Xcode command-line tools without interactive App Store Connect sign-in. The established signing setup is documented in Gus's `Documentation/AppStore/cli-release.md`; credentials and its dedicated signing keychain remain outside Git under `~/.appstoreconnect/`. Never copy credential contents into logs or documentation.

Use the required successful local gate and verify its source manifest against the exact archived revision. Choose an unused build number after checking uploaded app builds and Cloud runs. Archive the `PumpSync Beta` scheme/configuration for `generic/platform=iOS`, overriding `CURRENT_PROJECT_VERSION` only for the release invocation. Supply `-allowProvisioningUpdates` and Xcode's `-authenticationKeyPath`, `-authenticationKeyID`, and `-authenticationKeyIssuerID` from the existing protected configuration. Keep the normal warning gates, team, entitlements and Beta environment.

Export with `method=app-store-connect`, `signingStyle=automatic`, the existing distribution identity, `testFlightInternalTestingOnly=true`, `manageAppVersionAndBuildNumber=false`, and `uploadSymbols=true`. First use `destination=export` to inspect the signed IPA; then use `destination=upload`. Put system tools first in PATH to avoid the documented Homebrew/system rsync packaging mismatch. Verify archive/package signatures, version, bundle identifier, Beta backend and App Attest environment before upload.

After upload, inspect Apple's build-upload errors/warnings, require the exact build to become `VALID` and `INTERNAL_ONLY`, then verify its Internal Testers group linkage and `IN_BETA_TESTING` state. Add only that verified new build to the existing internal group if necessary. A successful CLI release does not establish successful Cloud tests or execution of Cloud post-actions. Preserve the saved automatic Internal Beta workflow. Before its next run, verify the Cloud-assigned build number is greater than the CLI-uploaded number to avoid a duplicate version.
