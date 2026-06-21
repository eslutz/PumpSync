# PumpSync

PumpSync is a privacy-first Tandem Source to Apple Health sync system.

The repository is split by deployable and ownership boundary so the main backend, iOS client, helper services, and infrastructure can evolve independently.

## Repository Layout

- `backend/`: core PumpSync product backend. This is currently a C# Azure Functions solution with thin triggers and reusable application/domain/infrastructure libraries.
- `client/ios/`: SwiftUI iOS client that owns backend access mode selection, StoreKit hosted subscriptions, HealthKit authorization, Tandem credential storage, sync initiation, and Apple Health writes.
- `services/`: supporting deployable code that is not part of the core product API, including the log drain endpoint and model cost updater.
- `infra/`: infrastructure-only assets such as Bicep deployment templates and environment templates.
- `docs/`: architecture, privacy, setup, and release handoff notes.

## Access Model

PumpSync supports two backend access paths:

- Hosted: the user buys or restores the PumpSync Hosted auto-renewable subscription through StoreKit. The app sends the signed App Store transaction JWS to the backend, and the backend verifies it before issuing a short-lived PumpSync service token.
- Self-hosted: the user enters their own backend URL. A backend deployed in `SelfHosted` mode issues a service token for that installation without App Store subscription verification.

Sign in with Apple is intentionally not part of this flow. The hosted backend keys durable sync state by the App Store original transaction ID plus an installation ID, not by an Apple account identity token.

## Privacy Model

- Tandem credentials are stored only by the iOS app in Keychain with device-only accessibility.
- Tandem credentials are sent to the backend only inside an active HTTPS sync request.
- The backend does not persist Tandem credentials, Tandem tokens, raw Tandem events, or normalized Tandem samples.
- Tandem payloads are written to Apple Health by the iOS app and then discarded from app memory/storage.
- The app retains only minimal sync metadata and a rolling HMAC external-ID ledger for duplicate prevention.
- Hosted subscription state, installation mapping, rate limits, sync attempts, and App Store notification idempotency are stored in Azure Table Storage.

## Backend

Backend projects:

- `PumpSync.Functions`: HTTP triggers only.
- `PumpSync.Application`: use cases, access checks, sync orchestration, interfaces.
- `PumpSync.Domain`: user IDs, subscription entitlement state, Tandem event abstractions, normalized insulin/carb samples.
- `PumpSync.Infrastructure`: Azure Table Storage, App Store signed payload verification, Tandem authentication, and request-local Tandem event parsing.
- `PumpSync.ApiContracts`: public request and response DTOs.

API surface:

- `GET /v1/capabilities`
- `POST /v1/subscription/session`
- `POST /v1/self-host/session`
- `POST /v1/app-store/notifications`
- `POST /v1/sync/tandem`
- `POST /v1/tandem/credentials/validate`
- `GET /v1/status`

Register the public Azure Functions URL with App Store Server Notifications. For nonprod, use `https://func-pumpsync-nonprod-flex-api.azurewebsites.net/api/v1/app-store/notifications`.

Credential-bearing Tandem sync requests must not use persistent idempotency storage.

The deployed hosted backend runs on Azure Functions Flex Consumption using Linux-hosted .NET isolated worker apps. Classic Linux Consumption is intentionally avoided because .NET 10 Functions are not supported there.

## Local Validation

```sh
dotnet restore backend/PumpSync.sln
dotnet build backend/PumpSync.sln
dotnet test backend/PumpSync.sln
```

```sh
dotnet restore services/services.slnx
dotnet build services/services.slnx
az bicep build --file infra/bicep/main.bicep
az bicep build --file infra/bicep/main.subscription.bicep
```

## Deploy Infrastructure

PumpSync follows the GifForge-style split between a subscription bootstrap template and a resource-group runtime template. Pass `.bicepparam` files without `@`:

```sh
AZURE_LOCATION=eastus2 \
APPSTORE_BUNDLE_ID=dev.ericslutz.PumpSync \
APPSTORE_ENVIRONMENT=Sandbox \
APPSTORE_SUBSCRIPTION_PRODUCT_ID=dev.ericslutz.PumpSync.hosted.monthly \
APPSTORE_ISSUER_ID=<issuer-id> \
APPSTORE_KEY_ID=<key-id> \
APPSTORE_PRIVATE_KEY=<private-key-pem> \
APPSTORE_ROOT_CERTIFICATE_PEM=<apple-root-cert-pem> \
PUMPSYNC_SERVICE_TOKEN_SIGNING_KEY=<secret> \
PUMPSYNC_LOG_DRAIN_SHARED_SECRET=<secret> \
az deployment sub create \
  --name pumpsync-nonprod-bootstrap \
  --location eastus2 \
  --template-file infra/bicep/main.subscription.bicep \
  --parameters infra/environments/nonprod.bicepparam
```

The Bicep template creates three Flex Consumption Function Apps:

- `func-pumpsync-<environment>-flex-api`
- `func-pumpsync-<environment>-flex-log`
- `func-pumpsync-<environment>-flex-cost`

Each app has its own package container in the shared storage account and uses user-assigned managed identity for Key Vault, package storage, Functions host storage, and Table Storage. The deploy workflow publishes Linux-x64 ReadyToRun packages; Native AOT is deferred until the Functions worker, HTTP extensions, and application dependencies are explicitly audited for trim/AOT compatibility.

```sh
cd client/ios
xcodegen generate
xcodebuild test -project PumpSync.xcodeproj -scheme PumpSync -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

The Azure Functions Core Tools CLI is needed to run the Functions host locally.

## Manual Gates

See [docs/manual-setup-and-validation.md](docs/manual-setup-and-validation.md) and [docs/hosted-subscription-self-hosting-handoff.md](docs/hosted-subscription-self-hosting-handoff.md) for the remaining items that require Apple Developer access, Azure secrets, real Tandem credentials, GitHub repository settings, or physical-device validation.
