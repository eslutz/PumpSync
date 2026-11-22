# PumpSync iOS

PumpSync is the iOS app that syncs Tandem Source insulin and carbohydrate data into Apple Health.

The direct-client candidate connects the iPhone to Tandem Source. The app handles authentication, reads pump logs, and converts them to HealthKit samples. Existing service-backed builds use the [legacy backend](https://github.com/eslutz/PumpSync-Backend).

## Repository Layout

- `PumpSync/`: SwiftUI app sources, resources, entitlements, and app configuration.
- [`Design/`](Design/README.md): editable OpenPencil designs, screen coverage, reference records, and the interactive review preview.
- `PumpSyncTests/`: unit tests.
- `PumpSyncUITests/`: UI tests and screenshot automation entry points.
- `project.yml`: XcodeGen source of truth for schemes, configurations, build settings, entitlements, and generated project files.
- `Documentation/app-store/`: App Store metadata, screenshots, accessibility notes, and review assets.
- `Documentation/legal/`: pointers to the website's Privacy Policy, Terms of Use, and Account/Data Deletion pages, plus repo-local App Store privacy notes.
- `Scripts/ios/`: iOS screenshot capture scripts.

## Direct sync

On the Sync tab, choose **Connect to Tandem** to sign in to a US or European account. An upgrade with saved credentials offers **Reconnect to Tandem**. The Sync tab also links to Apple Health setup when write access is needed. Set the insulin concentration in Settings and choose the history range on Sync before the first import. Later manual syncs, app-open catch-up and iOS background refresh use the same importer.

The app keeps credentials in device-only Keychain. Only the regional Tandem service receives them. Tandem sessions and downloaded records are processed in memory. HealthKit stores the permitted samples. A device-local ledger of keyed identifiers prevents repeats.

See the [internal beta acceptance instructions](Documentation/app-store/direct-beta.md) for validation and release evidence.

## Generate Project

Use XcodeGen 2.48.0 to match the version pinned in iOS CI.

```sh
xcodegen generate
```

Do not hand-edit generated Xcode project or scheme files unless XcodeGen cannot represent a setting.

## Build And Test

Run the full simulator validation locally to preserve GitHub Actions compute quotas. GitHub Actions validates project generation, builds and analyzes the iOS app, lints Swift, scans for security issues, and runs Foundation-only unit tests on macOS. Xcode Cloud retains its existing workflow-specific tests, archives, and distribution. Use raw `xcodebuild` output for local validation.

```sh
xcodebuild -list -project PumpSync.xcodeproj
xcodebuild test -project PumpSync.xcodeproj -scheme PumpSync -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

Before pushing a candidate or starting Xcode Cloud, run:

```sh
bash Scripts/ios/validate-cloud-tests.sh
```

Use the latest stable Xcode, version 27.2 or newer. The local preflight runs the full suite on an iPhone SE (3rd generation) with iOS 27.0, then checks navigation and layout at standard and maximum accessibility text sizes. It rejects build warnings and saves the exact Xcode version, runtime, source hashes and test results under ignored `TestResults/`. Record physical-device, Xcode Cloud and distribution results separately.

## License

PumpSync source is available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md).
