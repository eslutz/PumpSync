# PumpSync iOS

PumpSync is the iOS app that syncs Tandem Source insulin and carbohydrate data into Apple Health.

This repository is frontend-only. Backend API code, infrastructure, backend workflows, data-deletion tooling, Docker images, and Azure operations live in [eslutz/PumpSync-Backend](https://github.com/eslutz/PumpSync-Backend).

## Associated Repositories

| Repository | Owns | Notes |
| --- | --- | --- |
| [eslutz/PumpSync](https://github.com/eslutz/PumpSync) | iOS app, App Store/TestFlight metadata, iOS CI, screenshots, app legal docs | This repo. Do not add backend code, backend infrastructure, or backend deploy workflows here. |
| [eslutz/PumpSync-Backend](https://github.com/eslutz/PumpSync-Backend) | ASP.NET Core backend, Docker/Compose self-hosting, Azure Container Apps infrastructure, backend deploy workflows, data deletion tooling | Canonical backend for hosted service, real self-hosting, and synthetic demo/App Review mode. |

Hosted production/nonprod backend images are private GitHub Container Registry images pulled by Azure Container Apps with a backend Key Vault-stored read-only package token. Public self-host/demo images are also published from the backend repo to GitHub Container Registry so users can run the backend without Azure access. The iOS app does not build, publish, or select container images; it only points at a backend base URL.

## Repository Layout

- `PumpSync/`: SwiftUI app sources, resources, entitlements, and app configuration.
- [`Design/`](Design/README.md): editable OpenPencil designs, screen coverage, reference records, and the interactive review preview.
- `PumpSyncTests/`: unit tests.
- `PumpSyncUITests/`: UI tests and screenshot automation entry points.
- `project.yml`: XcodeGen source of truth for schemes, configurations, build settings, entitlements, and generated project files.
- `Documentation/app-store/`: App Store metadata, screenshots, accessibility notes, and review assets.
- `Documentation/legal/`: pointers to the website's Privacy Policy, Terms of Use, and Account/Data Deletion pages, plus repo-local App Store privacy notes.
- `Scripts/ios/`: iOS screenshot capture scripts.

## Access Model

PumpSync supports two backend access paths:

- Hosted: the user buys or restores the PumpSync auto-renewable subscription through StoreKit. The app sends the signed App Store transaction JWS plus an App Attest proof and receives a renewable device-bound session.
- Self-hosted: the user enters their own backend base URL. A backend deployed in `SelfHosted` mode verifies a Secure Enclave P-256 signature and issues a renewable session without App Store or Apple authentication.

Sign in with Apple is intentionally not part of this flow.

## Privacy Model

- Tandem credentials are stored only by the iOS app in Keychain with device-only accessibility.
- Renewable session credentials and device-key references are also stored in device-only Keychain items; private proof keys never leave App Attest or the Secure Enclave.
- Tandem credentials are sent to the configured backend only inside an active HTTPS sync request.
- The app writes Tandem insulin and carbohydrate samples to Apple Health and then discards the returned payload.
- Duplicate prevention uses a local rolling HMAC external-ID ledger.
- Tandem credentials are not synced through iCloud in v1; each device must be configured separately.

## Backend URL Routing

`project.yml` defines the hosted API base URL per configuration (the `API_BASE_URL` build setting, injected into Info.plist). Public docs intentionally avoid repeating live hosted endpoint values — `project.yml` is the source of truth:

| Purpose | Scheme | Configuration | Backend environment |
| --- | --- | --- | --- |
| Local Xcode install | `PumpSync` | `Debug` | Nonprod hosted API |
| TestFlight upload | `PumpSync Beta` | `Beta` | Nonprod hosted API |
| App Store release | `PumpSync` | `Release` | Production hosted API (custom domain) |

The `/api` path segment is part of the base URL for hosted builds. The app appends `/v1/...` endpoint paths. A build whose Info.plist is missing `API_BASE_URL` fails fast at launch rather than falling back to a hardcoded environment.

Self-hosted users enter their own backend base URL in app settings. They should include `/api` unless their reverse proxy intentionally maps the backend API at the domain root.

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

The project targets Xcode 27.1 Release Candidate (build `27A9275`). GitHub CI uses the `xcode-27` preview runner and explicitly selects that toolchain, following the [runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md). The preflight pins that toolchain, iOS 27.0, and iPhone SE (3rd generation). It creates a dedicated simulator if needed, runs all unit and UI tests, then runs the connection recovery flow once each at standard and maximum accessibility text sizes using actual simulator text settings. It restores the previous text size on exit. Any failure or build-tool warning fails validation. Raw logs, `.xcresult` bundles, summaries, and the tested environment/commit are saved under ignored `TestResults/`. The iOS 27.0 runtime preserves small-screen SE coverage; the installed iOS 27.1 runtime rejects this device type. Xcode Cloud must separately be configured for Xcode 27.1 and its test destination verified; a local pass does not confirm hosted workflow settings. Additional minimum-supported-OS, iPad, and physical-device checks remain necessary for release acceptance.

## App Store Routing

| Purpose | Scheme | Configuration | StoreKit environment |
| --- | --- | --- | --- |
| Local Xcode install | `PumpSync` | `Debug` | Sandbox |
| TestFlight upload | `PumpSync Beta` | `Beta` archive | Sandbox |
| App Store release | `PumpSync` | `Release` archive | Production |

TestFlight and development-signed purchases use Apple's sandbox and do not charge real money. App Store release builds use the production App Store transaction environment.

## License

PumpSync source is available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md). Noncommercial use — including running your own self-hosted backend for personal use — is permitted. Commercial use is reserved by the copyright holder.

Automated local, GitHub CI and Xcode Cloud tests consume committed test-only snapshots in `PumpSyncTests/SessionContractSnapshots/`. Their backend revision and SHA-256 checksums are recorded in `session-contract-manifest.json`; preparation validates the snapshots without backend access or a .NET SDK. Missing resources fail the tests. Backend CI regenerates deterministic exports and rejects drift against its own committed copies. After a reviewed backend contract change is committed, use `bash Scripts/ios/update-session-contract-snapshots.sh --backend-path <clean checkout>` to update frontend snapshots and provenance. A pass proves compatibility with that recorded revision, not an arbitrary later deployed backend.
