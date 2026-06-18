# PumpSync Privacy Policy

Effective date: 2026-06-18

PumpSync syncs Tandem Source pump data to Apple Health at the user's request. PumpSync is designed to minimize server-side storage of health data and credentials.

This policy describes the data handled by the PumpSync iOS app and backend service.

## Data PumpSync Handles

PumpSync may handle:

- Apple account identity token data from Sign in with Apple, used to create a PumpSync session.
- The user's Apple-provided private relay email address or email address, when Apple provides it.
- Tandem Source username, password, selected region, and pump/device identifiers, used only to perform a sync request.
- Tandem pump events returned during a sync request, including insulin delivery and carbohydrate-related records.
- Normalized insulin and carbohydrate samples generated from Tandem events.
- PumpSync service session tokens.
- Operational metadata such as sync attempt timestamps, status, rate-limit events, correlation IDs, and redacted error metadata.
- Technical telemetry needed to operate the backend, such as request success/failure status and service diagnostics.

## Data Stored On Device

The iOS app stores Tandem credentials in the device Keychain using device-only accessibility. Tandem credentials are not synced through iCloud by PumpSync.

The app stores minimal sync metadata and a rolling duplicate-prevention ledger so repeated syncs do not create duplicate Apple Health samples.

## Data Sent To PumpSync Servers

The app sends Tandem credentials to the PumpSync backend only during an active HTTPS sync request. The backend uses those credentials to retrieve Tandem Source data for that request.

The backend does not persist Tandem username, password, Tandem session cookies, Tandem access tokens, raw Tandem events, or normalized Tandem samples.

## Apple Health

PumpSync writes insulin and carbohydrate samples to Apple Health only after the user grants Apple Health permission. Apple Health controls whether other apps can read those samples.

PumpSync does not read unrelated Apple Health data. PumpSync does not use HealthKit data for advertising, marketing, or data mining.

## Backend Storage

PumpSync stores:

- user account identifiers derived from Sign in with Apple;
- billing entitlement state when subscriptions or purchases are enabled;
- rate-limit events;
- sync attempt metadata;
- idempotency records for non-credential endpoints;
- redacted operational audit events.

PumpSync does not store Tandem credentials or Tandem health payloads in backend durable storage.

## Sharing

PumpSync does not sell user data. PumpSync does not share HealthKit data, Tandem credentials, Tandem tokens, raw Tandem events, or normalized Tandem samples with advertisers, data brokers, or marketing services.

PumpSync may use infrastructure providers such as Apple, Microsoft Azure, and GitHub to operate the app, backend, telemetry, deployment, and support workflows. Those providers process data only as needed to provide their services.

## Retention

Tandem credentials remain on the user's device until the user deletes them in the app or deletes the app.

The backend retains account, billing, rate-limit, sync metadata, and redacted operational records only as long as needed to operate PumpSync, troubleshoot issues, meet legal obligations, and protect the service.

Raw Tandem events and normalized Tandem samples are discarded by the backend after the sync response is produced. The iOS app discards raw and normalized Tandem payloads after Apple Health confirms the write.

## Deletion

Users may delete Tandem credentials in the app. Users may also request deletion of their PumpSync account and server-side account metadata using the account and data deletion instructions in `docs/legal/data-deletion.md`.

Deleting PumpSync does not automatically delete samples already written to Apple Health. Users can manage Apple Health records in the Apple Health app.

## Security

PumpSync uses HTTPS for network requests. Tandem credentials are stored on device in Keychain and are sent to the backend only for active sync requests. Backend logs and audit events are designed to redact credential and token fields.

## Medical Disclaimer

PumpSync is not a medical device and does not provide medical advice, diagnosis, treatment, or dosing recommendations. Users should verify health data and follow guidance from qualified healthcare professionals.

## Changes

This policy may be updated as PumpSync changes. The effective date will be updated when material changes are made.

## Contact

For privacy, deletion, or support requests, use the PumpSync support contact listed on the App Store product page or TestFlight invitation.
