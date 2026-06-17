# Security and Operations

## Sensitive Data Rules

- Do not store Tandem username, password, session cookies, access tokens, raw events, or normalized samples in backend durable storage.
- Do not write Tandem credentials or tokens to logs.
- Do not add persistent idempotency storage to credential-bearing Tandem sync endpoints.
- Keep Tandem credentials on-device in Keychain with device-only accessibility.
- Send Tandem credentials to the backend only during an active HTTPS sync request.

## Backend Operations

- Use Azure SQL for user accounts, billing entitlement state, rate-limit events, sync attempt metadata, and idempotency records for non-credential endpoints.
- Use Application Insights for operational telemetry.
- Use Key Vault/App Configuration for service secrets and environment settings.
- Treat Tandem endpoint failures as transient unless the response clearly indicates invalid credentials or authorization failure.

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

The Tandem sync endpoint currently allows 12 sync requests per user per hour. Increase only with real Tandem rate-limit evidence and measured backend cost.

## Background Sync

iOS background execution is best effort. The app must keep the app-open stale refresh path because iOS may skip or delay daily background processing.
