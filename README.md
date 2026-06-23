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
- `PumpSyncTests/`: unit tests.
- `PumpSyncUITests/`: UI tests and screenshot automation entry points.
- `project.yml`: XcodeGen source of truth for schemes, configurations, build settings, entitlements, and generated project files.
- `docs/app-store/`: App Store metadata, screenshots, accessibility notes, and review assets.
- `docs/legal/`: privacy, terms, data deletion request, and App Store privacy notes.
- `scripts/ios/`: iOS screenshot capture scripts.

## Access Model

PumpSync supports two backend access paths:

- Hosted: the user buys or restores the PumpSync Hosted auto-renewable subscription through StoreKit. The app sends the signed App Store transaction JWS to the backend and receives a short-lived PumpSync service token.
- Self-hosted: the user enters their own backend base URL. A backend deployed in `SelfHosted` mode issues a service token for that installation without App Store subscription verification.

Sign in with Apple is intentionally not part of this flow.

## Privacy Model

- Tandem credentials are stored only by the iOS app in Keychain with device-only accessibility.
- Tandem credentials are sent to the configured backend only inside an active HTTPS sync request.
- The app writes Tandem insulin and carbohydrate samples to Apple Health and then discards the returned payload.
- Duplicate prevention uses a local rolling HMAC external-ID ledger.
- Tandem credentials are not synced through iCloud in v1; each device must be configured separately.

## Backend URL Routing

`project.yml` defines hosted API base URLs:

| Purpose | Scheme | Configuration | Backend URL |
| --- | --- | --- | --- |
| Local Xcode install | `PumpSync` | `Debug` | `https://ca-pumpsync-nonprod-api.gentlesea-b1e8a783.eastus2.azurecontainerapps.io/api` |
| TestFlight upload | `PumpSync Beta` | `Beta` | `https://ca-pumpsync-nonprod-api.gentlesea-b1e8a783.eastus2.azurecontainerapps.io/api` |
| App Store release | `PumpSync` | `Release` | `https://api.pumpsync.ericslutz.dev/api` |

The `/api` path segment is part of the base URL for hosted builds. The app appends `/v1/...` endpoint paths.

Self-hosted users enter their own backend base URL in app settings. They should include `/api` unless their reverse proxy intentionally maps the backend API at the domain root.

The nonprod Container Apps URL above is the current live backend for local Debug installs and TestFlight/Beta builds. The production custom domain is the intended Release base URL and depends on the backend repo's production Container Apps/custom-domain cutover.

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

## App Store Routing

| Purpose | Scheme | Configuration | StoreKit environment |
| --- | --- | --- | --- |
| Local Xcode install | `PumpSync` | `Debug` | Sandbox |
| TestFlight upload | `PumpSync Beta` | `Beta` archive | Sandbox |
| App Store release | `PumpSync` | `Release` archive | Production |

TestFlight and development-signed purchases use Apple's sandbox and do not charge real money. App Store release builds use the production App Store transaction environment.
