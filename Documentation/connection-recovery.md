# Connection recovery and sync feedback

PumpSync connects directly to the selected Tandem region using the sign-in saved on the device. The Sync tab shows the latest outcome for the current account. **Sync Details** shows the last successful import's counts and timestamp and the start of the last attempt.

## Recovering an import

- **Reconnect to Tandem** opens the Tandem account screen. An upgrade from a legacy connection requires a foreground reconnection before importing.
- **Review Health Access** opens the per-type Apple Health write permissions. If some types are allowed, **Sync Details → Sync Allowed Types** can continue importing them. Enable the missing permission and sync again to pick up records still available from Tandem.
- **Try Again** starts a manual sync. When Tandem provides a retry deadline, PumpSync displays it and defers new requests until then.
- A newer failure or interruption remains visible alongside the last successful time. A gap before the available history window appears in the import result. The number of records received can exceed the number of samples saved, including when samples were imported previously.

Manual, app-open and background sync share an in-flight operation. The first import captures the selected range and concentration when it starts. Foreground or background work continues while it has a valid execution lease. PumpSync checks cancellation before submitting Health writes and before recording success. It records confirmed writes for deduplication even if an attempt is subsequently abandoned.

## Inspecting source records

Open **Settings → Support & Diagnostics → Inspect source data** to view a read-only preview from the connected account. Inspection shows available records, the effective time range, and converted values. A preview can include records already imported to Apple Health. Inspecting or refreshing the list leaves Health samples and the sync watermark untouched.

For local validation, use synthetic data when checking account changes, permission failures, preview cancellation, and recovery. Physical-device checks for direct-account imports and actual Apple Health writes are described in the [internal beta guide](app-store/direct-beta.md).
