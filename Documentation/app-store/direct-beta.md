# Direct-to-Tandem internal beta

The candidate is free and connects directly to the tester’s Tandem account. Testers sign in with their own Tandem credentials. Record the source commit, build number, validation results, and tester confirmation separately. Use only synthetic data in CI.

1. Generate the Xcode project and run `bash Scripts/ios/validate-cloud-tests.sh` in the frontend checkout. Inspect the full suite and both compact-device Dynamic Type checks. Verify the signed Beta archive includes the expected bundle identifier, HealthKit entitlement and background task configuration.
2. Use the internal TestFlight workflow. Verify that the archive corresponding to the tested source is processed and assigned to the existing internal group. Record the build number actually assigned by Apple.
3. On an existing installation, note the last successful sync and concentration, then install the candidate over it. Reconnect the saved Tandem account in the foreground. Confirm account, concentration, permissions, history and the legacy installation ID. Removing credentials must stop sync. A new or replacement account must use its own initial range.
4. On a fresh installation, enter the region and Tandem credentials, select the actual pump concentration and initial range, and grant the intended Health write permissions. Run Sync Now. Verify the source, units, timestamps and quantities for representative records in Apple Health against Tandem. Repeat the overlapping import and verify previously saved samples appear once.
5. Test app-open catch-up after four hours. After an iOS-granted background run on a locked device following first unlock, inspect the local diagnostics and verify the Health results after unlocking. Record the trigger, counts, and Health/ledger checkpoints. A scheduled request alone leaves this check pending.
6. Open Inspect Source Data and refresh. Confirm inspection leaves sync history and Health writes untouched. Verify diagnostics report safe operation stages and counts. Keep personal records, identifiers and passwords out of release evidence.

Start live acceptance with a tester’s US account. Record EU fixture coverage separately from any later live EU run. Legacy service retirement is tracked separately.
