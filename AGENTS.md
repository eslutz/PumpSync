# PumpSync Agent Notes

## Repo Scope

- This repository is frontend-only. Do not add backend API projects, backend infrastructure, backend deploy workflows, log drains, model-cost updaters, or data-deletion tooling here.
- Backend implementation and operations belong in the PumpSync Backend repository.

## Hosted Subscription Builds

- Local Xcode installs use the `PumpSync` scheme with the `Debug` configuration. They must point at the nonprod backend and use Apple's sandbox App Store transaction environment.
- TestFlight uploads use the `PumpSync Beta` scheme with the `Beta` archive configuration. They must point at the nonprod backend and use Apple's sandbox App Store transaction environment.
- App Store release uploads use the `PumpSync` scheme with the `Release` archive configuration. They must point at the prod backend and use Apple's production App Store transaction environment.
- Do not add a hosted-subscription bypass or production allowlist unless the user explicitly asks for it.
- Do not add an In-App Purchase entitlement key to `PumpSync.entitlements`; StoreKit access comes from enabling the In-App Purchase capability in Apple Developer and App Store Connect.

## iOS Validation

- `project.yml` is the XcodeGen source of truth.
- Regenerate the project with `xcodegen generate` after editing `project.yml`.
- Prefer destination strings that include `OS=latest`, for example `platform=iOS Simulator,name=iPhone 17,OS=latest`, to avoid ambiguous-destination warnings.
- Keep validation output unfiltered. Raw `xcodebuild` may print Xcode/simulator runtime warnings such as `IDELaunchParametersSnapshot`, AppIntents metadata extraction notices, CA event messages, or duplicate `UIAccessibilityLoaderWebShared` messages during simulator UI tests.
