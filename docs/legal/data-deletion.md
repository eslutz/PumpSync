# PumpSync Account And Data Deletion

Effective date: 2026-06-18

PumpSync stores minimal hosted subscription and installation metadata and does not persist Tandem credentials, Tandem tokens, raw Tandem events, or normalized Tandem samples on the backend.

## Delete Tandem Credentials From The Device

In the PumpSync app:

1. Open Settings.
2. Open the Tandem section.
3. Delete the saved Tandem credentials.

Deleting Tandem credentials prevents future syncs until credentials are added again.

## Revoke Apple Health Access

In iOS:

1. Open Settings.
2. Open Health.
3. Open Data Access & Devices.
4. Select PumpSync.
5. Disable PumpSync access or remove PumpSync data as desired.

Samples already written to Apple Health are controlled by Apple Health. Deleting PumpSync does not automatically delete samples already written to Apple Health.

## Delete PumpSync Hosted Metadata

To request deletion of PumpSync hosted backend metadata, contact PumpSync support using the support contact listed on the App Store product page or TestFlight invitation.

Include the PumpSync installation ID shown in Settings, the App Store subscription original transaction ID if available from Apple purchase history, or the Apple ID receipt details needed to locate the subscription through App Store support tooling. Do not include Tandem passwords, Tandem tokens, screenshots containing health data, or other sensitive medical details in the request.

Deletion covers PumpSync hosted server-side metadata associated with the subscription or installation, subject to records PumpSync must retain for security, fraud prevention, legal compliance, billing, dispute handling, or service integrity.

Self-hosted users control their own backend data and should delete data directly from their self-hosted storage account or database.

## Nonprod And TestFlight Data

For nonprod and TestFlight builds, PumpSync may reset backend data during testing. Testers can request deletion using the same support path above.
