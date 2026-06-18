# Hosted Subscription And Self-Hosting Handoff

Effective date: 2026-06-18

## App Capabilities And Entitlements

Add or keep:

- HealthKit capability and `com.apple.developer.healthkit` entitlement.
- In-App Purchase capability in the Apple Developer App ID and App Store Connect app record.
- Background processing mode for the existing daily sync task.

Remove:

- Sign in with Apple capability.
- `com.apple.developer.applesignin` entitlement.
- Any Sign in with Apple Services ID and server-to-server notification configuration.

No In-App Purchase entitlement key is added to `PumpSync.entitlements`; StoreKit access comes from the App ID/App Store Connect capability.

## App Store Connect Setup

- Create the PumpSync Hosted auto-renewable subscription product: `dev.ericslutz.PumpSync.hosted.monthly`.
- Configure App Store Server Notifications to `https://<backend-host>/api/v1/app-store/notifications`.
- Create an App Store Server API key and set `APPSTORE_ISSUER_ID`, `APPSTORE_KEY_ID`, and `APPSTORE_PRIVATE_KEY` for deployment.
- Set `APPSTORE_ROOT_CERTIFICATE_PEM` to the Apple root certificate used to pin App Store signed payload verification.
- Use `Sandbox` for nonprod and `Production` for prod in `APPSTORE_ENVIRONMENT`.

## Azure Resources To Delete Or Stop Using

Delete or remove if PumpSync was the only consumer:

- Azure SQL PumpSync schema/tables created from the old `infra/sql/001_initial_schema.sql`.
- PumpSync contained SQL users and SQL permissions for the backend managed identity.
- Key Vault secret `AzureSql--ConnectionString`.
- Function app setting `AzureSql__ConnectionString`.
- Function app setting `Apple__ClientId`.
- GitHub variables/secrets `AZURE_SQL_SERVER`, `AZURE_SQL_DATABASE`, and `APPLE_CLIENT_ID`.

Keep:

- Azure Functions Flex Consumption apps.
- Storage account and package containers.
- Key Vault.
- Managed identities.
- Application Insights and Log Analytics.

New hosted state is stored in Azure Table Storage tables created by Bicep:

- `SubscriptionEntitlements`
- `Installations`
- `InstallationLookup`
- `SyncAttempts`
- `RateLimitBuckets`
- `AppleNotificationIdempotency`
- `AuditEvents`

## Creator Access Without Paying Yourself

For development and TestFlight, use App Store sandbox testing. Sandbox purchases do not charge real money and still produce signed StoreKit transactions that exercise the hosted subscription path.

For the production App Store build, prefer App Store Connect offer codes or promotional offers for your own Apple ID. That keeps access represented as an App Store subscription transaction, so the backend does not need a hidden creator bypass.

Do not add a production allowlist unless you are willing to own the support and abuse surface. Without Sign in with Apple, a bypass would need to key off installation ID or original transaction ID, which is harder to recover across reinstalls and can create App Review and operational questions.

Self-hosted mode is also available for creator/admin testing when the goal is to avoid hosted billing entirely.

## Self-Hosted Deployment Contract

A self-hosted backend should set:

- `PumpSync__BackendMode=SelfHosted`
- `PumpSync__ServiceTokenIssuer`
- `PumpSync__ServiceTokenAudience`
- `PumpSync__ServiceTokenSigningKey`
- `AzureStorage__ConnectionString` or `AzureStorage__AccountName`
- `AzureStorage__SubscriptionEntitlementsTableName`
- `AzureStorage__InstallationsTableName`
- `AzureStorage__InstallationLookupTableName`
- `AzureStorage__SyncAttemptsTableName`
- `AzureStorage__RateLimitBucketsTableName`
- `AzureStorage__AppStoreNotificationIdempotencyTableName`
- `AzureStorage__AuditEventsTableName`

Hosted-only App Store settings are not required for self-hosted mode unless the self-hosted operator wants to run their own subscription-gated service.
