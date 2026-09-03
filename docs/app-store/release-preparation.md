# PumpSync Release Preparation Checklist

Use this document as the release gate for PumpSync 1.0.0. Complete the sections in order. If a release-blocking fix changes the app, backend, subscription configuration, or data-handling behavior, repeat every affected check before advancing.

## Release Record

- [ ] Record the intended iOS release commit: `________________________`
- [ ] Record the intended backend release commit: `________________________`
- [ ] Record the App Store version: `1.0.0`
- [ ] Record the release build number: `________________________`
- [ ] Record the internal TestFlight build number: `________________________`
- [ ] Record the external TestFlight build number: `________________________`
- [ ] Record the production deployment date and revision: `________________________`
- [ ] Record the person making the final release decision: `________________________`

## Gate 1: Internal TestFlight Validation

### Test Matrix

- [ ] Test on at least one physical iPhone.
- [ ] Test the minimum supported iOS version or the oldest available representative device.
- [ ] Test the current iOS version.
- [ ] Record each device model, iOS version, build number, connection mode, and result.
- [ ] Review TestFlight crashes, screenshots, feedback, sessions, and installation data.

### Installation and First Launch

- [ ] Install the current build over an older TestFlight build and verify user settings and Tandem credentials remain usable; the prior hosted session and App Attest state must not be read or migrated, and PumpSync must perform one fresh current-protocol enrollment.
- [ ] Delete PumpSync, reinstall it, and verify Tandem credentials are removed.
- [ ] Confirm a clean installation starts disconnected with no Tandem account configured.
- [ ] Force-quit and reopen the app several times.
- [ ] Restart the device and reopen PumpSync.
- [ ] Confirm there are no repeated warnings, stale sessions, or crashes.
- [ ] Verify the PumpSync icon on the Home Screen, App Switcher, TestFlight listing, and StoreKit purchase sheet.
- [ ] Check light mode, dark mode, Display Zoom, and larger Dynamic Type sizes.

### PumpSync Subscription

- [ ] Open the subscription sheet and verify the product name, monthly price, renewal period, app icon, and current terminology.
- [ ] Confirm the Terms of Use and Privacy Policy links open successfully.
- [ ] Confirm obsolete `PumpSync Hosted` product terminology is absent.
- [ ] Cancel the purchase sheet and verify the app remains usable.
- [ ] Complete a sandbox subscription purchase and verify PumpSync connects.
- [ ] Force-quit and relaunch; verify the subscription session recovers promptly.
- [ ] Verify the hosted session uses protocol v3 exclusively with an App Attest proof in the support bundle; confirm the bundle contains no proof, challenge, transaction JWS, or refresh credential values.
- [ ] Upgrade from Build 10 on a physical iPhone and verify PumpSync performs a fresh App Attest enrollment without showing the stale “reconciling a previous secure connection attempt” failure.
- [ ] Leave the app backgrounded past the refresh target and verify the backend records a successful credential refresh and sync without a StoreKit request.
- [ ] Restore an active subscription.
- [ ] Attempt restore with an account that has no entitlement, if available.
- [ ] Verify a sandbox expiration returns `active_subscription_required` while the support bundle still reports protocol 3/App Attest and finite refresh credential expiries, rather than reporting “Connection session expired.”
- [ ] While the entitlement remains inactive, verify a later iOS-granted background task reaches session refresh or Tandem sync and Azure returns `401`; it must not stop with `renewableCredential=false`.
- [ ] After a verified sandbox renewal notification, verify a later background or foreground attempt succeeds without interactive StoreKit recovery and has a matching durable `SyncAttempts` record in Azure.
- [ ] Test purchase or restore while offline, then restore connectivity and retry.
- [ ] Confirm repeated taps cannot start overlapping purchase, restore, or activation operations.
- [ ] Open Apple subscription management from PumpSync.
- [ ] Verify expired or revoked entitlement handling does not leave a stale connected session.

### Self-Hosted and Demo Connection

Use the controlled demo configuration:

- Server URL: `https://demo.pumpsync.ericslutz.dev/api`
- Username: `demo@pumpsync.app`
- Password: `PumpSyncDemo123!`
- Region: United States

- [ ] Switch from PumpSync to Self-hosted.
- [ ] Verify Self-hosted enrollment and renewal use the Secure Enclave proof and succeed without an Apple Account, StoreKit entitlement, or App Attest service.
- [ ] Connect to the demo URL and verify the UI identifies a demo service.
- [ ] Verify missing `/api`, unreachable hosts, invalid TLS, and malformed URLs produce understandable errors.
- [ ] Verify non-loopback HTTP URLs are rejected.
- [ ] Save valid demo credentials.
- [ ] Verify invalid credentials produce an actionable error.
- [ ] Change the username, password, and region individually and verify save behavior.
- [ ] Switch between PumpSync and Self-hosted and verify sessions are not reused across modes.
- [ ] Confirm switching modes does not delete credentials without an explicit removal action.

### Tandem Credentials

- [ ] With no password entered, verify Show password is disabled, Save is shown, and Remove is hidden.
- [ ] While entering a password, verify Show password becomes enabled and accurately reveals and hides the value.
- [ ] With unchanged saved credentials, verify Remove is shown instead of Save and the saved password cannot be exposed.
- [ ] After changing username, password, or region, verify Save replaces Remove.
- [ ] Save changed credentials and verify they are validated.
- [ ] Verify credential removal requires confirmation.
- [ ] Cancel removal and verify nothing changes.
- [ ] Confirm removal clears all credentials and blocks syncing.
- [ ] Verify credentials and full email addresses do not appear in diagnostics or support bundles.

### Apple Health

- [ ] Verify the Health permission button copy, capitalization, contrast, and layout.
- [ ] Grant both insulin-delivery and carbohydrate write permission.
- [ ] Grant only one permission and verify the incomplete state is clear.
- [ ] Deny access and verify PumpSync explains how to change it later.
- [ ] Follow the displayed Settings instructions and confirm they are accurate.
- [ ] Revoke access after a successful sync and verify the next sync fails safely.
- [ ] Confirm PumpSync does not request unrelated Health data.
- [ ] Confirm demo samples use sensible dates, units, and source attribution.
- [ ] Remove synthetic samples from Apple Health after testing on a personal device.

### Initial and Subsequent Syncing

- [ ] Select 2 days and verify the action reads `Sync past 2 days`.
- [ ] Select 7 days and verify the action reads `Sync past 7 days`.
- [ ] Select 14 days and verify the action reads `Sync past 14 days`.
- [ ] Start the initial sync and verify the action disables and progress animates.
- [ ] Verify returned and imported counts and completion time.
- [ ] Verify insulin and carbohydrate samples in Apple Health.
- [ ] Run a second sync and confirm records are not duplicated.
- [ ] Confirm the action changes appropriately after the initial sync.
- [ ] Force-quit during a sync, reopen, and verify safe recovery.
- [ ] Lose connectivity during a sync and verify retry behavior.
- [ ] Tap repeatedly and verify concurrent syncs cannot start.
- [ ] Verify app-open and background checks do not duplicate records or block normal navigation.

### Data Handling, Diagnostics, and Errors

- [ ] Review every Data Handling screen for plain-language accuracy.
- [ ] Verify Data deletion request creates a correctly addressed email with the required installation identifier.
- [ ] Confirm deletion and support emails contain no credentials, tokens, health samples, or sensitive logs.
- [ ] Verify Privacy Policy, Terms of Use, deletion, and support links.
- [ ] Export a support bundle and confirm it is useful and redacted.
- [ ] Exercise these error states: no connection, no credentials, invalid credentials, missing Health permission, backend unavailable, subscription unavailable, subscription verification timeout, sync timeout, and malformed self-hosted URL.
- [ ] Confirm each error is short, actionable, recorded in diagnostics, recoverable, and free of internal exception text or secrets.

### Accessibility and Presentation

- [ ] Verify logical VoiceOver reading order and useful labels and hints.
- [ ] Verify controls remain reachable at accessibility text sizes.
- [ ] Verify text does not clip in portrait or landscape.
- [ ] Verify tap targets remain usable.
- [ ] Verify status is not communicated by color alone.
- [ ] Verify readable contrast in light and dark mode.
- [ ] Verify Reduce Motion does not remove essential progress feedback.
- [ ] Verify subscription and system sheets can always be dismissed.

### Internal Exit Criteria

- [ ] Complete a clean-device path: install, connect to demo, save credentials, grant Health access, select a history range, sync, verify Health samples, sync again without duplicates, export support data, force-quit, and recover state.
- [ ] Resolve all crashes, data-loss risks, duplicate Health writes, credential leaks, subscription failures, and blocking usability issues.
- [ ] Repeat all checks affected by fixes.
- [ ] Freeze feature work for the release candidate.
- [ ] Verify the frontend worktree, `HEAD`, upstream, and ahead/behind state.
- [ ] Resolve the untracked `CLAUDE.md` intentionally by committing it or excluding it.
- [ ] Verify the backend worktree, `HEAD`, upstream, and ahead/behind state.

## Gate 2: External TestFlight

### Create an External-Capable Build

An Xcode Cloud build labeled **Internal** cannot be submitted for external testing.

- [ ] Keep **PumpSync Internal Beta** for internal-only development builds.
- [ ] Create a separate manual **PumpSync External Beta** Xcode Cloud workflow.
- [ ] Use the `PumpSync Beta` scheme and `Beta` archive configuration.
- [ ] Keep the complete test action and archive action.
- [ ] Upload a normal App Store Connect/TestFlight build; do not select TestFlight Internal Only.
- [ ] Confirm the Beta configuration uses the nonproduction backend and sandbox App Store environment.
- [ ] Increment the build number.
- [ ] Run the workflow from the validated release-candidate commit.
- [ ] Confirm the processed build does not show an **Internal** badge.
- [ ] Resolve **Missing Compliance** if present and confirm `ITSAppUsesNonExemptEncryption` remains accurate.

### Verify Test Information

- [ ] Beta description is current.
- [ ] Feedback email is `support@ericslutz.dev`.
- [ ] Marketing URL is `https://pumpsync.ericslutz.dev/`.
- [ ] Privacy Policy URL is `https://pumpsync.ericslutz.dev/privacy/`.
- [ ] Review contact information is current.
- [ ] Demo credentials and review notes are current.
- [ ] Review notes explain synthetic Health samples, Health permissions, and that PumpSync is not a medical device.

### Create External Testing Group

- [ ] Create an External Testing group named **PumpSync External Beta**.
- [ ] Add the external-capable build.
- [ ] Add What to Test notes covering connection setup, purchase and restore, self-hosting, credentials, Health permissions, history range, syncing, duplicate prevention, relaunch recovery, diagnostics, and deletion.
- [ ] Decide whether testers should be notified automatically after approval.
- [ ] Submit the build for TestFlight App Review.
- [ ] Resolve any Beta App Review questions or rejection.
- [ ] Confirm the build status becomes approved for external testing.
- [ ] Invite a small controlled group by email first.
- [ ] Verify an external tester can accept the invitation, install the app, purchase in sandbox, sync, and submit feedback.
- [ ] Review external crash, feedback, and session data.
- [ ] Enable a public link only if broader testing is warranted; set device/OS criteria and a tester limit.

### External Exit Criteria

- [ ] Resolve all release-blocking external feedback.
- [ ] Publish another external build for any material fix.
- [ ] Repeat affected internal and external checks.
- [ ] Select and record the final release-candidate commit.
- [ ] Confirm the final production build will contain no code changes that were not externally tested, except explicitly accepted release-only configuration.

## Gate 3: Production Infrastructure Preparation

### Deploy the Intended Backend

- [ ] Deploy the intended backend commit to the `prod` GitHub environment.
- [ ] Confirm the deployed image uses the immutable commit SHA.
- [ ] Confirm the resource group is `rg-pumpsync-prod`.
- [ ] Confirm `PumpSync__BackendMode=Hosted`.
- [ ] Confirm the real Tandem source is enabled; production must not use SyntheticDemo.
- [ ] Confirm `AppStore__Environment=Production`.
- [ ] Confirm bundle ID `dev.ericslutz.PumpSync`.
- [ ] Confirm subscription product ID `dev.ericslutz.PumpSync.subscription.monthly`.
- [ ] Confirm the production signing key exists in Key Vault.
- [ ] Confirm managed identities, storage tables, and container pull access.
- [ ] Confirm `https://api.pumpsync.ericslutz.dev` resolves and serves valid TLS.

### Production Smoke and Security Validation

- [ ] Verify `/health` succeeds.
- [ ] Verify `/api/v1/capabilities` returns the expected service mode, billing mode, data-source mode, and version.
- [ ] Verify unauthenticated `/api/v1/status` returns `401`.
- [ ] Verify malformed, expired, wrong-audience, and wrong-issuer tokens are rejected.
- [ ] Verify malformed requests and incorrect product or bundle identities are rejected.
- [ ] Verify nonproduction subscription transactions are rejected by production.
- [ ] Verify rate limiting with a small controlled request set.
- [ ] Restart or replace a revision and confirm healthy recovery.
- [ ] Confirm logs contain no startup errors, credentials, tokens, email addresses, or health data.

Do not configure production to accept sandbox transactions. Run full sandbox subscription and sync testing against nonproduction; reserve production for configuration, health, negative-security, and post-release canary checks.

### Observability and Recovery

- [ ] Confirm request, error, dependency, and latency telemetry is available.
- [ ] Confirm alerts for unhealthy revisions, elevated 5xx responses, subscription-verification failures, Tandem failures, storage failures, Key Vault failures, and excessive latency.
- [ ] Confirm request correlation IDs appear across client diagnostics and backend logs without exposing sensitive data.
- [ ] Confirm deployments expose the backend commit SHA.
- [ ] Retain a known-good Container App revision.
- [ ] Document and test the backend rollback procedure.
- [ ] Confirm backup or recovery procedures for retained metadata.
- [ ] Prepare a launch dashboard and launch-day runbook.

### App Store Server Notifications

- [ ] Set the production notification URL to the production backend output.
- [ ] Set the sandbox notification URL to the nonproduction backend output.
- [ ] Confirm the configured notification version matches backend support.
- [ ] Send an App Store test notification to each environment.
- [ ] Verify signed-payload validation, logging, and idempotent handling.
- [ ] Verify invalid, duplicate, unknown, and out-of-order notifications are handled safely.
- [ ] Verify renewal, expiration, revocation, and refund behavior in sandbox.

## Gate 4: Production App Build

- [ ] Create a manual **PumpSync App Store Release** Xcode Cloud workflow.
- [ ] Use the `PumpSync` scheme and `Release` archive configuration.
- [ ] Run the complete automated test suite before archiving.
- [ ] Confirm Release points to `https://api.pumpsync.ericslutz.dev/api`.
- [ ] Confirm the subscription product ID is correct.
- [ ] Set `CFBundleVersion` to the next unused App Store Connect build number and confirm marketing version `1.0.0`.
- [ ] Regenerate `PumpSync.xcodeproj` from `project.yml` and verify no diff remains.
- [ ] Verify the frontend worktree is clean, the intended commit is pushed, and `HEAD` equals its upstream.
- [ ] Record the exact source commit for the archive; do not create the stable `v1.0.0` tag until Apple accepts this build.
- [ ] Archive and upload the App Store release build.
- [ ] Inspect the archived app's effective Info.plist, entitlements, signing, HealthKit capability, background modes, API URL, product ID, and encryption declaration.
- [ ] Confirm the archive has the production App Attest entitlement; confirm Debug alone uses the development App Attest environment.
- [ ] Confirm App Store Connect finishes processing the build without warnings or compliance blockers.

## Gate 5: App Store Submission

### Product Page and App Information

- [ ] Select the production build for version 1.0.0.
- [ ] Verify app name, subtitle, promotional text, description, keywords, version, and copyright.
- [ ] Verify marketing and support URLs.
- [ ] Verify the iPhone App Preview, screenshots, ordering, processing status, and poster frame.
- [ ] Verify the app icon in App Store Connect and the StoreKit purchase sheet.
- [ ] Complete and verify primary and secondary categories.
- [ ] Complete the age-rating questionnaire; the app must not remain Unrated.
- [ ] Complete content-rights questions.
- [ ] Complete the regulated-medical-device declaration if requested; ensure the answer matches PumpSync's non-medical-device status.
- [ ] Verify pricing, distribution method, and country/region availability.
- [ ] Complete Digital Services Act trader status and any required contact display.
- [ ] Verify export compliance.
- [ ] Verify App Privacy answers are published and match the app, backend metadata, subscription processing, SDKs, and operational telemetry.
- [ ] Verify accessibility declarations are accurate.
- [ ] Verify these public pages are accessible:
  - [ ] `https://pumpsync.ericslutz.dev/privacy/`
  - [ ] `https://pumpsync.ericslutz.dev/terms/`
  - [ ] `https://pumpsync.ericslutz.dev/privacy/data-deletion/`
  - [ ] `https://pumpsync.ericslutz.dev/support/`
- [ ] Confirm website and policy copy accurately describes app-open and background syncing and all retained backend metadata.

### App Review Information

- [ ] Verify review contact information.
- [ ] Verify the demo backend is healthy and will remain available throughout review.
- [ ] Verify demo credentials immediately before submission.
- [ ] Provide exact reviewer steps for Self-hosted demo connection, credentials, Health permissions, history selection, and initial sync.
- [ ] Explain that the demo creates deterministic synthetic samples in Apple Health and never contacts Tandem.
- [ ] Explain that PumpSync provides no diagnosis, treatment, dosing advice, or other medical recommendation.
- [ ] Explain the PumpSync subscription flow and how to restore or manage it.

### First Subscription Submission

The first auto-renewable subscription must be reviewed with version 1.0.0.

- [ ] Verify subscription group and localization.
- [ ] Verify product name, description, ID, $2.99 monthly price, renewal period, availability, and review screenshot.
- [ ] Add the subscription to the version 1.0.0 App Review submission.
- [ ] Add the unapproved subscription group if App Store Connect requires it.
- [ ] Confirm both the app version and subscription appear in the same submission.

### Submit for Review

- [ ] Select **Manually release this version** instead of automatic release.
- [ ] Save all version metadata.
- [ ] Add version 1.0.0 and the subscription items for review.
- [ ] Review the complete submission one final time.
- [ ] Submit for App Review.
- [ ] Monitor App Review messages and respond promptly.
- [ ] Resolve any rejection and repeat affected validation before resubmission.
- [ ] Confirm both the app and subscription are approved.
- [ ] Confirm version 1.0.0 reaches **Pending Developer Release**.
- [ ] Reconcile the accepted build number to its recorded source commit, and confirm that commit is clean, pushed, and matches its upstream.
- [ ] Confirm `v1.0.0` does not exist locally or remotely, then create the annotated tag on the accepted commit and push it without ever moving it:

```sh
git status --short
git rev-list --left-right --count HEAD...@{upstream}
git tag --list v1.0.0
git ls-remote --tags origin refs/tags/v1.0.0
git tag -a v1.0.0 <accepted-source-commit> -m "PumpSync v1.0.0"
git push origin v1.0.0
gh release create v1.0.0 --verify-tag --title "PumpSync v1.0.0" --notes-from-tag
```

## Gate 6: Production Release

### Final Go/No-Go

- [ ] App and subscription are both approved.
- [ ] Production backend is deployed from the recorded commit and revision.
- [ ] The hosted backend accepts only session protocol `3`, App Attest enrollment and refresh telemetry are healthy, and the current iOS build completes foreground and system-launched background renewal.
- [ ] Production health, capabilities, authorization, DNS, and TLS checks pass.
- [ ] Production and sandbox notification URLs point to the correct environments.
- [ ] Alerts and rollback procedures are operational.
- [ ] Privacy, terms, support, and deletion pages are live.
- [ ] No unresolved critical or high-severity defects remain.
- [ ] Client and backend use the same bundle ID and subscription product ID.
- [ ] Demo service remains available in case App Review follows up.
- [ ] Support inbox is monitored.
- [ ] A physical device and controlled Apple Account are ready for the production canary.
- [ ] Someone is available to monitor the release and execute rollback decisions.
- [ ] Record the go/no-go decision and time: `________________________`

### Release and Production Canary

- [ ] Click **Release This Version** and confirm the manual release.
- [ ] Wait until version 1.0.0 is publicly available in the intended storefront.
- [ ] Download the public App Store build using the controlled canary account.
- [ ] Complete one real $2.99 subscription purchase; record the charge and receipt context.
- [ ] Verify the production backend accepts the production entitlement and creates a session.
- [ ] Connect a controlled real Tandem account.
- [ ] Grant insulin-delivery and carbohydrate write permission.
- [ ] Run the smallest appropriate initial range.
- [ ] Verify correct Apple Health samples and source attribution.
- [ ] Run a second sync and verify duplicate prevention.
- [ ] Force-quit, relaunch, and verify subscription and connection recovery.
- [ ] Reinstall and restore the real purchase.
- [ ] Review production logs, entitlement metadata, latency, errors, and alerts.
- [ ] Cancel the canary subscription if it should not remain active.

### Post-Launch Monitoring

- [ ] Monitor availability, 5xx rate, latency, subscription verification, Tandem upstream errors, storage, Key Vault, crashes, and support mail continuously during the staffed launch window.
- [ ] Review App Store and TestFlight diagnostics after data becomes available.
- [ ] Confirm no unexpected health data or credentials appear in logs or retained storage.
- [ ] Record launch incidents and decisions.
- [ ] Classify issues:
  - [ ] Backend regression: roll back the Container App revision.
  - [ ] Subscription verification failure: correct or roll back the backend; remove from sale if the core paid flow is unusable.
  - [ ] Duplicate or incorrect Health writes: remove from sale and prepare a corrected build.
  - [ ] App crash or severe client defect: prepare version 1.0.1 and request expedited review if warranted.
  - [ ] Cosmetic or minor copy issue: record for version 1.0.1.
- [ ] Complete a 24-hour launch review.
- [ ] Complete a 7-day launch review.
- [ ] Close the release only after monitoring is stable and all release records are complete.
