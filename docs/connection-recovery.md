# Connection recovery and sync feedback

`AuthService.isConnecting` reflects operation-scoped progress while the scene is
active or inactive. Background work remains headless; valid-session cache hits do
not display a false connection attempt. The foreground controller owns bootstrap
and Retry Connection work, survives inactive transitions, and cancels its owner
when the scene backgrounds. Shared recovery and sync operations retain work only
while another caller owns it.

Disconnected recovery failures remain visible on the Sync screen with a safe
explanation and Retry Connection, subscription, or settings actions. Retry
Connection uses existing coalesced recovery and then checks sync freshness. Failed
recovery does not automatically loop. Connected describes the PumpSync session,
not successful Tandem retrieval. Last Successful Sync remains separate from the
latest failure.

Upstream `tandem_source_request_rejected` is non-transient even with HTTP 502.
One sync action makes one request for this rejection; transient failures retain
bounded retries. Tandem request rejection alone does not invalidate credentials
or disconnect PumpSync. Safe error messages and correlation references remain in
the failure banner.

Cancellation is checked before initiating HealthKit work and before success
metadata updates. An already-submitted HealthKit save cannot be recalled: confirmed
writes remain ledgered for deduplication, but abandoned work is not recorded as a
successful sync. Device testing is still required to establish cold-start
background reliability; a scheduled request is not execution proof.


## Safe preview candidate acceptance

Preview-capable rollout remains pending. Verify authenticated **Settings → Sample Preview** connection, public credential validation, Past 2 days/U100 defaults, converted row details, invalid-input/network recovery, retry, dismissal, and background cancellation. No Health permission is needed. Confirm zero synthetic Health writes and byte-for-byte preservation of live configuration, credential records, concentration, ledger, and metadata with test-target instrumentation; screenshot inspection alone cannot prove this boundary.

Verify optional real **Preview Import** with denied Health permission; it reports downloaded records (including already imported records), effective window and concentration, never imported/new counts. It closes back to normal Sync and cannot commit cached rows. Test missing/unknown/inconsistent/stale provenance and all manual/app-open/granted-background/retry entry points.

Actual iPhone Secure Enclave/App Attest authentication, legitimate Health writes and repeat-sync deduplication, spoken VoiceOver, hosted purchase/restore, and distribution-specific acceptance remain separate release gates. Preserve personal data and use an agreed device arrangement for reinstall/reset tests. Apple's confirmation of the sample-preview plus legitimate-import-video arrangement is still pending; do not send or submit this draft without authorization.
