# PumpSync Data Deletion Request Runbook

Use this runbook to process low-frequency PumpSync Hosted metadata deletion requests from a user-provided installation ID.

## Inputs

- PumpSync installation ID from the user's Delete Data Request email.
- Target environment: `prod` for App Store users, `nonprod` for TestFlight or local sandbox testing.
- Local Azure access with permission to read and delete rows from the PumpSync storage account tables.
- `DataDeletion:AuditHashSalt` stored in local .NET user-secrets before executing a purge.

Do not request or store Tandem passwords, Tandem tokens, screenshots containing health data, or sensitive medical details.

## Configure The CLI

For nonprod, the CLI is configured to use storage account `stpumpsyncnonprodigfrpul` with the signed-in Azure CLI identity.

```bash
az login
az account set --subscription "Personal Subscription"
```

The local machine should store the deletion audit salt in .NET user-secrets for the CLI project:

```bash
dotnet user-secrets set DataDeletion:AuditHashSalt "<private-support-audit-salt>" \
  --project backend/tools/PumpSync.DataDeletionRequest
```

For prod, add the prod storage account name to `backend/tools/PumpSync.DataDeletionRequest/appsettings.json` or pass `AzureStorage__AccountName` in the shell. Do not store connection strings or audit salts in source control.

## Dry Run

Run a dry-run first. This does not delete records and does not write an audit event.

```bash
dotnet run --project backend/tools/PumpSync.DataDeletionRequest -- \
  --installation-id "<INSTALLATION_ID>" \
  --environment prod
```

If nothing matches, the CLI returns JSON like:

```json
{
  "status": "no_records_found",
  "execute": false,
  "environment": "prod",
  "installationId": "<INSTALLATION_ID>",
  "originalTransactionIds": [],
  "auditEventId": null,
  "found": 0,
  "purged": 0,
  "tables": {}
}
```

If records match, review `found`, `originalTransactionIds`, and the per-table counts before executing.

## Execute Deletion

After reviewing the dry-run output, execute the purge:

```bash
dotnet run --project backend/tools/PumpSync.DataDeletionRequest -- \
  --installation-id "<INSTALLATION_ID>" \
  --environment prod \
  --execute
```

The CLI deletes matching hosted metadata from:

- `InstallationLookup`
- `Installations`
- `SubscriptionEntitlements`
- `SyncAttempts`
- `RateLimitBuckets`

It writes one `AuditEvents` row containing the tool name, a salted hash of the installation ID, the environment, status, totals, and per-table counts. The audit row must not contain the raw installation ID or App Store original transaction ID.

`AppleNotificationIdempotency` is not purged by installation ID because current records are notification-level dedupe records and are not linked to installation IDs.

## User Response Templates

No records found:

```text
No PumpSync hosted backend metadata records were found for installation ID <INSTALLATION_ID>.
```

Records purged:

```text
PumpSync hosted backend metadata associated with installation ID <INSTALLATION_ID> has been deleted, subject to records PumpSync must retain for security, fraud prevention, legal compliance, billing, dispute handling, or service integrity.
```

Apple App Store purchase, billing, and subscription records are controlled by Apple and are not deleted by PumpSync backend metadata deletion.
