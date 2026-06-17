# PumpSync

PumpSync is a privacy-first Tandem Source to Apple Health sync system.

The repository is split by deployable and ownership boundary so the main backend, iOS client, helper services, and infrastructure can evolve independently.

## Repository Layout

- `backend/`: core PumpSync product backend. This is currently a C# Azure Functions solution with thin triggers and reusable application/domain/infrastructure libraries so the same logic can later move behind ASP.NET Core on Azure App Service.
- `client/ios/`: SwiftUI iOS client that owns Sign in with Apple, HealthKit authorization, Tandem credential storage, sync initiation, and Apple Health writes.
- `services/`: supporting deployable code that is not part of the core product API, including the log drain endpoint and model cost updater.
- `infra/`: infrastructure-only assets such as SQL schema, Bicep/Terraform, deployment scripts, and environment templates.
- `docs/`: architecture, privacy, and implementation notes.

## Privacy Model

- Tandem credentials are stored only by the iOS app in Keychain with device-only accessibility.
- Tandem credentials are sent to the backend only inside an active HTTPS sync request.
- The backend does not persist Tandem credentials, Tandem tokens, raw Tandem events, or normalized Tandem samples.
- Tandem payloads are written to Apple Health by the iOS app and then discarded from app memory/storage.
- The app retains only minimal sync metadata and a rolling HMAC external-ID ledger for duplicate prevention.

## Backend

Backend projects:

- `PumpSync.Functions`: HTTP triggers only.
- `PumpSync.Application`: use cases, idempotency, sync orchestration, interfaces.
- `PumpSync.Domain`: user IDs, Tandem event abstractions, normalized insulin/carb samples.
- `PumpSync.Infrastructure`: Azure SQL, Sign in with Apple validation, Tandem authentication, and request-local Tandem event parsing.
- `PumpSync.ApiContracts`: public request and response DTOs.

API surface:

- `POST /v1/auth/apple/session`
- `POST /v1/sync/tandem`
- `GET /v1/status`

Credential-bearing Tandem sync requests must not use persistent idempotency storage.

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
```

```sh
cd client/ios
xcodegen generate
cd ../..
xcodebuild test -project client/ios/PumpSync.xcodeproj -scheme PumpSync -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -derivedDataPath client/ios/.DerivedData CODE_SIGNING_ALLOWED=NO
```

The Azure Functions Core Tools CLI is needed to run the Functions host locally.

## Manual Gates

See [docs/manual-setup-and-validation.md](docs/manual-setup-and-validation.md) for the remaining items that require Apple Developer access, Azure secrets, real Tandem credentials, GitHub repository settings, or physical-device validation.
