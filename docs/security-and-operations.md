# Security and Operations

## Sensitive Data Rules

- Do not store Tandem username, password, session cookies, access tokens, raw events, or normalized samples in backend durable storage.
- Do not write Tandem credentials or tokens to logs.
- Do not add persistent idempotency storage to credential-bearing Tandem sync endpoints.
- Keep Tandem credentials on-device in Keychain with device-only accessibility.
- Send Tandem credentials to the backend only during an active HTTPS sync request.

## Backend Operations

- Use Azure Table Storage for subscription entitlement state, installation lookup, rate-limit buckets, sync attempt metadata, and App Store notification idempotency.
- Use Application Insights for operational telemetry.
- Use Key Vault/App Configuration for service secrets and environment settings.
- Treat Tandem endpoint failures as transient unless the response clearly indicates invalid credentials or authorization failure.
- Keep `AppStore__RootCertificatePem` configured for hosted deployments. App Store payload verification fails closed when the Apple root certificate is missing.

## Logging

Backend and helper services must redact keys containing:

- `authorization`
- `cookie`
- `credential`
- `password`
- `secret`
- `token`
- `username`

## Rate Limiting

The Tandem sync endpoint currently allows 12 sync requests per internal user per hour. Hosted users are keyed from the App Store original transaction ID. Self-hosted users are keyed from the installation ID.

Increase rate limits only with real Tandem rate-limit evidence and measured backend cost.

## Background Sync

iOS background execution is best effort. The app must keep the app-open stale refresh path because iOS may skip or delay daily background processing.
