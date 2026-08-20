# Repository Guidelines

## Project Structure & Module Organization

This repository owns the SwiftUI iOS app, App Store/TestFlight material, and iOS CI. Application code is in `PumpSync/Sources/`, grouped into `App`, `Auth`, `Health`, `Networking`, `Storage`, `Sync`, `Tandem`, and `UI`. Unit tests live in `PumpSyncTests/`; UI and screenshot tests live in `PumpSyncUITests/`. Store submission assets and reference material belong in `docs/app-store/`. `project.yml` is the XcodeGen source of truth.

Do not add backend code, Dockerfiles, Bicep, deployment workflows, or backend runbooks here.

## Build, Test, and Development Commands

```sh
xcodegen generate
xcodebuild -list -project PumpSync.xcodeproj
xcodebuild test -project PumpSync.xcodeproj -scheme PumpSync \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

Regenerate after changing `project.yml`; do not hand-edit generated project or scheme files. Keep raw `xcodebuild` output available when diagnosing failures.

## Coding Style & Naming Conventions

Use four-space indentation and standard Swift naming: `UpperCamelCase` types, `lowerCamelCase` properties/functions, and filenames matching their primary type. Keep SwiftUI views small, move side effects into services or coordinators, and preserve existing dependency-injection patterns. Hosted base URLs include `/api`; clients append `/v1/...`.

## Testing Guidelines

Use XCTest. Name files `FeatureTests.swift` and test methods for observable behavior. Add focused tests for sync, storage, authentication, and UI-state changes. Use `OS=latest` simulator destinations and run `git diff --check` before committing.

## Commit & Pull Request Guidelines

Use concise imperative subjects, optionally prefixed with `fix:`, `docs:`, or `refactor:`. Keep commits scoped to one concern. Pull requests must explain user-visible behavior, list validation, link issues when relevant, and include screenshots for UI or App Store asset changes.

## Security & Configuration

Never commit credentials, service tokens, signing material, or live user health data. Preserve device-only Keychain storage and the Debug/Beta/Release backend and StoreKit environment mapping. Do not add subscription bypasses or an In-App Purchase entitlement key.

## Related Project Guides

- [Backend](../PumpSync.backend/AGENTS.md)
- [Website](../PumpSync.website/AGENTS.md)
- [Wiki](../PumpSync.wiki/AGENTS.md)
