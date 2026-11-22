# Repository Guidelines

## Project Structure & Module Organization

This repository owns the SwiftUI iOS app, App Store/TestFlight material, and iOS CI. Application code is in `PumpSync/Sources/`, grouped into `App`, `Health`, `Networking`, `Storage`, `Sync`, `Tandem`, and `UI`. Unit tests live in `PumpSyncTests/`. UI and screenshot tests live in `PumpSyncUITests/`. Store submission assets and reference material belong in `Documentation/app-store/`. `project.yml` is the XcodeGen source of truth.

Do not add backend code, Dockerfiles, Bicep, deployment workflows, or backend runbooks here.

## Build, Test, and Development Commands

```sh
xcodegen generate
xcodebuild -list -project PumpSync.xcodeproj
xcodebuild test -project PumpSync.xcodeproj -scheme PumpSync \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

Regenerate after changing `project.yml`; do not hand-edit generated project or scheme files. Keep raw `xcodebuild` output available when diagnosing failures.

Run the full iOS simulator validation locally to preserve GitHub Actions compute quotas. GitHub Actions checks project generation, compiles and analyzes for a generic iOS device, runs SwiftLint and Semgrep, and runs Foundation-only unit tests on macOS. Xcode Cloud retains its existing workflow-specific tests, archives, and distribution. For app or test changes, and before an iOS release, run `bash Scripts/ios/validate-cloud-tests.sh`. The script requires the latest stable Xcode (27.2 or newer) and uses the iOS 27.0 runtime for compact-device coverage. It creates or reuses an isolated iPhone SE (3rd generation), runs the full suite without test filters through `validate-tests.sh`, then runs both the connection recovery flow and native typography/final-content reachability checks at standard and maximum accessibility text sizes. These checks verify the actual UIKit text category, label growth and scroll access to the final line of content. The script changes the actual simulator text setting and restores it on exit; launch-environment variables alone are insufficient evidence of a Dynamic Type check. It preserves raw logs, result bundles, and environment/source details in ignored `TestResults/`. A focused or larger-device pass is insufficient for this gate; do not retry failures until one passes. When changing the validation environment, record the local toolchain and runtime. Use `validate-tests.sh` for focused development checks and additional destinations. Both scripts reject build-tool warnings as well as failures. All targets and configurations treat Swift and Clang compiler warnings as errors through `project.yml`; do not override this gate. Local preflight cannot guarantee an identical Cloud host or distribution result.

## Coding Style & Naming Conventions

Use four-space indentation and standard Swift naming: `UpperCamelCase` types, `lowerCamelCase` properties/functions, and filenames matching their primary type. Keep SwiftUI views small, move side effects into services or coordinators, and preserve existing dependency-injection patterns. The direct importer uses regional Tandem Source endpoints.

## Testing Guidelines

Use XCTest. Name files `FeatureTests.swift` and test methods for observable behavior. Add focused tests for sync, storage, authentication, and UI-state changes. Use `OS=latest` simulator destinations and run `git diff --check` before committing.

## Commit & Pull Request Guidelines

Use concise imperative subjects, optionally prefixed with `fix:`, `docs:`, or `refactor:`. Keep commits scoped to one concern. Pull requests must explain user-visible behavior, list validation, link issues when relevant, and include screenshots for UI or App Store asset changes.

## Security & Configuration

Never commit credentials, service tokens, signing material, or live user health data. Keep Tandem credentials device-only in Keychain. Use synthetic Tandem responses for automated tests, including the HealthKit write-boundary checks.

## Related Project Guides

- [Backend](../PumpSync.backend/AGENTS.md)
- [Website](../PumpSync.website/AGENTS.md)
- [Wiki](../PumpSync.wiki/AGENTS.md)
