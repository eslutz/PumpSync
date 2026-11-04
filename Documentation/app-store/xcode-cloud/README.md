# Xcode Cloud workflow configuration

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
