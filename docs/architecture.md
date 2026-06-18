# PumpSync Architecture

## Boundaries

PumpSync keeps backend logic independent from Azure Functions triggers. Triggers deserialize requests, call application services, and serialize responses. Business logic lives in reusable libraries so the backend can move to another host without rewriting Tandem parsing, access checks, rate limiting, or sync orchestration.

The iOS app owns Apple-only platform capabilities:

- StoreKit purchase and restore for the hosted subscription.
- HealthKit authorization and writes.
- Background refresh scheduling.
- Device-only Tandem credential storage.
- Local duplicate-prevention ledger.
- Self-hosted backend URL selection.

The backend owns server-side concerns:

- App Store signed transaction and notification verification for hosted access.
- Self-hosted session issuance when deployed in self-hosted mode.
- Subscription entitlement, installation lookup, rate-limit, sync attempt, and notification idempotency records in Azure Table Storage.
- Request-local Tandem retrieval and normalization.

## Access Modes

Hosted mode accepts only verified App Store subscription transactions. The backend derives an internal user ID from the original transaction ID and issues short-lived PumpSync service tokens to installations associated with that transaction.

Self-hosted mode is intended for a user-controlled backend. It issues short-lived PumpSync service tokens for the configured installation ID without App Store subscription verification. Do not deploy the public hosted infrastructure in self-hosted mode.

## Data Retention

Tandem credentials, Tandem bearer/session tokens, raw Tandem records, and normalized Tandem samples are not durable backend data. They exist only for a single sync request and are discarded after the response is produced.

The app purges raw and normalized Tandem payloads after HealthKit confirms the write. It keeps a rolling HMAC ledger of imported external IDs so app reinstalls or repeated background jobs do not create duplicate Apple Health samples.

## Sync Initiation

Sync is initiated by the iOS app:

- when the app opens and the last successful sync is stale;
- when the user manually starts sync;
- when iOS grants the daily background processing task.

iOS background execution is opportunistic, so the app treats the daily task as best effort and performs a stale-data refresh when the user next opens the app.

## Folder Contract

- `backend/` is the main PumpSync product backend.
- `client/` contains end-user apps.
- `services/` contains helper deployables such as log drains, scheduled workers, and operational updaters.
- `infra/` contains infrastructure-only declarations and environment setup.
