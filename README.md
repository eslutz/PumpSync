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

Connect a US or European Tandem account in Settings, choose the insulin concentration and initial import range, and allow PumpSync to write insulin and dietary carbohydrates to Apple Health. An upgrade with saved credentials offers a one-time reconnect. Sync Now, app-open catch-up and iOS background refresh use the same importer.

The app keeps credentials in device-only Keychain. Only the regional Tandem service receives them. Tandem sessions and downloaded records are processed in memory. HealthKit stores the permitted samples. A device-local ledger of keyed identifiers prevents repeats.

See the [internal beta acceptance instructions](Documentation/app-store/direct-beta.md) for validation and release evidence.

## Generate Project

```sh
xcodegen generate
```

Do not hand-edit generated Xcode project or scheme files unless XcodeGen cannot represent a setting.

## Build And Test

Use raw `xcodebuild` output for validation:

```sh
xcodebuild -list -project PumpSync.xcodeproj
xcodebuild test -project PumpSync.xcodeproj -scheme PumpSync -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

Before pushing a candidate or starting Xcode Cloud, run:

```sh
bash Scripts/ios/validate-cloud-tests.sh
```

Use the latest stable Xcode (currently 27.2, build `27B52`; minimum 27.2). GitHub CI selects the newest stable installed Xcode and fails if it is older than 27.2. The local preflight retains iPhone SE (3rd generation) / iOS 27.0 for compact-device coverage, runs the full suite and standard/maximum accessibility-text recovery checks, and rejects build-tool warnings. Additional checks use the latest available iOS runtime on a supported modern iPhone; the locally installed latest runtime is iOS 27.1, while the Xcode 27.2 SDK is iOS 27.2. Neither an SDK nor a simulator pass establishes physical-device, Xcode Cloud, or distribution acceptance. Cloud workflow settings must be read back separately when changing hosted validation. Raw evidence is retained under ignored `TestResults/`.

## License

PumpSync source is available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md).
