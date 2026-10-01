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
