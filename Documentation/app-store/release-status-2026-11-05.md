# Release preparation status — November 5, 2026

**Preparation advanced; neither external TestFlight nor App Store review has been submitted.**

Source inspected and captured: frontend `e5398db`, backend `07a8dce`. The frontend was clean and aligned with its recorded upstream before these documentation/assets changes. The latest live internal TestFlight build is 51; local marketing/build configuration is 1.0.0 (37). Do not infer Cloud build/source equivalence from these numbers; record the actual Cloud revision before selecting a candidate.

## Changes saved in App Store Connect

| Area | Change |
| --- | --- |
| External TestFlight | Created **PumpSync External Beta**, group `8469793e-c98e-4433-853a-ebf1dbc4f860`. Eric was subsequently added using his existing internal tester record. Membership verified: one tester, zero builds. No build invitation or public link was enabled. |
| Beta description | Replaced obsolete demo-service copy with the normal Tandem-account workflow, sandbox purchase explanation, and current testing scope. |
| Beta review notes | Withdrew the instructions to write synthetic data to real Apple Health. Explicitly recorded reviewer access as unresolved; no demonstration approval is claimed. Existing credential fields were not changed and must be reconciled with the final arrangement. |
| Version 1.0.0 | Changed automatic publication to **Manually release this version** and added preparation notes describing the unresolved reviewer-access and sandbox-routing gates. No build selected. |
| iPhone screenshots | Uploaded all nine refreshed native 1320 × 2868 screenshots into the large Dynamic Island slot. Confirmed nine images; the required medium-display slot inherits the new images. |
| Superseded iPhone media | Removed the old Face ID large-display override and old app-preview video from the version. Apple explicitly retains these in the Asset Library; local prior screenshots are archived in the ignored screenshot archive directory. No replacement video is claimed. |
| iPad screenshots | Replaced the prior eight-image set with nine refreshed native 2064 × 2752 screenshots. Confirmed nine images in the required 13-inch slot. |
| Subscription review | Uploaded the current subscription-entry screenshot and saved corrected review notes covering hosted/self-hosted access, App Attest, and retained metadata. Apple still displayed **Processing** for this review image at the last check; final readiness is unconfirmed. |
| Cloud external workflow | Created **PumpSync External Beta**, workflow `62e8529f-3823-4866-ba93-0f7a82d14eac`. Manual start, required full tests, `PumpSync Beta` archive, App Store Connect distribution preparation, no automatic distribution post-action. |
| Cloud production workflow | Created **PumpSync App Store Release**, workflow `752ce628-544a-43dc-b9f0-08b041e2ae9e`. Manual start, required full tests, `PumpSync` archive, App Store Connect distribution preparation, no automatic distribution post-action. |

Both new workflows retain Xcode 27.1 (27A9275), cached derived data, and the inherited single test destination. Neither was started. Existing Internal Beta and Validation workflows were preserved. The production scheme was explicitly corrected and saved after duplication; its archive must use `PumpSync`, not `PumpSync Beta`.

## Local changes

- Regenerated nine iPhone and nine iPad screenshots from current committed source, using isolated Debug presentation fixtures.
- Refreshed the local subscription-review JPG from the current subscription-entry capture.
- Changed the iPhone capture script's default device to iPhone 18 Pro Max and removed screenshot cropping/stretching; capture output now preserves native device geometry.
- Updated asset documentation, this status record, workflow reference, and the reviewer-access inquiry draft.
- Subsequent implementation adds typed StoreKit environment routing and session isolation in the frontend, an explicit bootstrap guard in the backend workflow, and cross-repository release guidance in the wiki. No production deployment, DNS, subscription price, privacy answers, or published website change was made.
- Changes are staged on local branch `codex/release-preparation-2026-11-05`. The commit attempt failed because the sandbox could not access the configured GPG signing agent. Signing was not disabled; no commit, push, or PR was created.

## Verification performed

| Check | Result |
| --- | --- |
| iPhone screenshot UI test | Passed: 1 test, 0 failures/skips; iPhone 18 Pro Max, iOS 27.0. No build warnings reported. Result `/tmp/PumpSyncReleaseIPhone.xcresult`. |
| iPad screenshot UI test | Passed: 1 test, 0 failures/skips; iPad Pro 13-inch (M5), iOS 27.0. No build warnings reported. Result `/tmp/PumpSyncReleaseIPad.xcresult`. |
| Screenshot visual review | Reviewed contact sheets for all 18 captures, including subscription, account, Health, data handling, and diagnostics screens. No real health imports or live credentials were used. |
| Script syntax | `bash -n Scripts/ios/capture-iphone-app-store-screenshots.sh` passed. |
| Pinned release preflight | Blocked before tests: selected Xcode 27.1 build 27A9275, but shell sandbox denied CoreSimulator service/log access. The Xcode-tool screenshot tests used the default installed toolchain; they do not satisfy the pinned full-suite/Dynamic Type gate. |
| Backend suite | Command exited 1 without producing a test summary (log only contains first-run CLI output). Do not count it as a pass. No backend change was made. |
| Beta metadata persistence | Reloaded and confirmed the corrected description and review notes. |
| Version persistence | Later navigation confirmed manual release and saved preparation notes. |
| Workflow persistence | Reloaded Manage Workflows and confirmed both new workflow records. |
| Production DNS | Browser returned name-not-resolved for `api.pumpsync.ericslutz.dev`. Cloudflare's complete PumpSync DNS result contained the website and demo records, but no production API record. |

Screenshot tests are not physical-device authentication, Health-import, subscription, background-sync, or accessibility acceptance evidence.

## Other live settings inspected

- Version 1.0.0 and the monthly subscription/group remain Prepare for Submission.
- Internal build 51 is marked Internal Only; it cannot be promoted to external distribution.
- App availability is United States only; the app price schedule is free. Existing Mac and Vision Pro availability are off.
- Monthly subscription is $2.99 in the United States, with localized pricing configured across 175 storefronts. Subscription availability is broader than app availability; no expansion was made.
- App Information has Health & Fitness, 4+ with regional ratings, third-party content rights, standard EULA, non-trader status, and a declaration that the app is not a regulated medical device.
- Published privacy disclosures include User ID, Device ID, and Purchase History, linked to identity for App Functionality. A full telemetry/data-retention reconciliation remains required.
- Accessibility declarations exist as iPhone/iPad drafts for VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, and Reduced Motion. These were not republished or treated as fresh manual acceptance evidence.
- Server notification URLs still reference the legacy production/nonproduction Azure Functions hosts. Their reachability and forwarding were not established; do not replace them using guessed Container App destinations.

## Remaining submission blockers

1. **Developer agreement:** Account Holder acceptance is reserved to Eric; not accepted by the agent.
2. **Reviewer access:** Apple inquiry is drafted in the signed-in contact form and in `reviewer-access-request-2026-11-05.md`, but not sent. No approval/case exists; replacement demonstration mode is not implemented. A valid authorized account arrangement is the alternative.
3. **Production endpoint:** verify deployed production Container App/revision, TLS/custom-domain binding, then configure the missing API DNS record and smoke-test. Azure CLI management access was blocked because it attempted to write its session file outside the permitted workspace. No production destination was guessed.
4. **Release purchase routing:** Release currently targets production, while App Review uses sandbox purchases. Backend JWS verification enforces its configured environment. The client requires a verified transaction/environment-aware route to an isolated sandbox service, including persistence, purchase/restore/update/recovery, and background behavior. Client implementation is now present in the working tree, with focused isolation tests; complete post-review regression and deployment validation remain pending. Do not simply allow sandbox entitlements in production or use a review-only subscription bypass.
5. **Notifications:** verify current environment outputs, set the correct production/sandbox URLs, send Apple's test notifications, and verify signed/idempotent handling.
6. **Release evidence:** pinned complete local preflight plus physical-device App Attest, legitimate Health imports, deduplication, subscription lifecycle, natural background execution, and applicable accessibility checks remain unverified.
7. **Final candidate:** reconcile exact source revisions, run required checks, choose unused build numbers, then start external/release workflows. Review the final processed build and image statuses before adding for review.
8. **Privacy/deletion assessment:** confirm whether the installation/subscription model triggers Apple's in-app account-deletion rule; the current email request flow must not be assumed sufficient merely because the app is health related.

## Official references

- [External TestFlight testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)
- [Internal-only build restriction](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)
- [Review access and HealthKit rules](https://developer.apple.com/app-store/review/guidelines/)
- [Configure purchases for review in sandbox](https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases)
- [First subscription submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)

## Implementation continuation — November 5

### Saved changes

- Frontend branch `codex/release-preparation-2026-11-05`, based on `e5398db`: verified typed entitlement, fixed production/sandbox URL selection, persisted environment, legacy binding foreground recovery, serialized route switching with durable invalidation, policy downgrade checks, coalesced routing transitions, and environment-scoped inactive transaction handling. See `hosted-environment-routing.md`.
- Removed the obsolete tracked MP4; history retains the artifact. Apple Asset Library reported no usage. Eric confirmed permanent deletion; the asset was deleted and the library count changed from 35 to 34. Evidence: `evidence/2026-11-05/obsolete-preview-deleted.png`. Replacement preview remains deferred.
- Added Eric to PumpSync External Beta using the existing tester identity. Screenshot evidence is in `evidence/2026-11-05/external-beta-membership.png`.
- Backend branch `codex/release-bootstrap-2026-11-05`, based on `07a8dce`: default-off workflow bootstrap input plus fail-closed missing-resource preflight and nine shell regression cases, called from deployment validation. Production stable-tag requirement and strict server verification remain unchanged.
- Wiki branch `codex/release-routing-2026-11-05`: release boundary and review gate documentation. Website unchanged.

### Validation and limitations

- Initial routing/authentication run: 110 passed. Expanded environment-switch/missing-binding run: 112 passed, zero failures/skips; `/tmp/PumpSyncRoutingIsolation.xcresult`.
- Those passes precede the two final review fixes. Fresh review identified and implementation corrected missing routing-transition propagation for coalesced recovery and cross-environment inactive-transaction invalidation. Concurrent migration, scoped revocation, relaunch, and failed-invalidation tests were added. Static follow-up review found no further serious defect; that is not runtime acceptance.
- Full suite attempt `/tmp/PumpSyncReleaseFull.xcresult` timed out in the hosted contract test. Its fixture used the live initializer without a persisted route and reached foreground StoreKit recovery. The fixture now models a persisted sandbox binding. Follow-up `/tmp/PumpSyncRoutingReviewFix.xcresult` also timed out after 300 seconds before producing test results; do not reuse the earlier 112-test count as validation of final source.
- Exact pinned preflight selected Xcode 27.1 build 27A9275, then failed before tests because CoreSimulator service/log access was denied. Actual Dynamic Type checks have not run for this candidate.
- Backend bootstrap guard: nine cases passed (healthy, missing group/app, denied, network, unhealthy, empty ingress). Backend version guard passed. Backend full build produced no output and was canceled; no backend build/test pass. Azure Bicep validation failed before execution on denied CLI session-file access.
- Required remaining targeted coverage includes switching during a suspended renewable refresh, policy downgrade during mutation-lease waiting, and incompatible background reenrollment, followed by final full suite and shipping configuration compilation.

### Production finding

The authenticated Azure portal lists 13 resource groups across the inspected directories/subscriptions; only `rg-pumpsync-nonprod` is a PumpSync group. Direct lookup of configured production group in Personal Subscription returned **404 ResourceGroupNotFound**, distinct from an authorization failure. Evidence: `evidence/2026-11-05/production-resource-group-not-found.png`. No production deployment, image, secrets, ingress, certificate, DNS target, notification URL, telemetry, alert, or rollback has therefore been verified. Do not guess these values from nonproduction naming.

Azure CLI remains blocked before authentication by sandbox denial writing `/Users/ericslutz/.config/azure-cli-profiles/personal/az.sess`. GPG signing remains blocked by access to the configured home-directory agent. Signing was not disabled. There are no new signed commits, pushes, PRs, release tags, or build candidates. Build 51 remains the last observed internal-only build; no new build number was allocated or workflow started because validation gates did not pass.

### Privacy and physical-device gates

Source policies describe retained installation/subscription/authentication metadata, encrypted receipts/risk outcomes, rate-limit/idempotency/audit records, and email-operated metadata deletion. Apple explicitly includes automatically generated guest accounts in its [account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/). Treat the installation-linked hosted identity as requiring an in-app deletion solution unless an authoritative applicability determination establishes otherwise; do not claim email alone satisfies the rule. No in-app deletion implementation or actual production retention reconciliation is complete.

No operation was performed on Eric's physical iPhone. Real App Attest, legitimate Health import units/timestamps/duplicate prevention, upgrade recovery, and natural background behavior are untested for this candidate. Never reinstall/reset the existing device or delete existing Health data to close these gates. Destructive checks require a separately agreed test device.

All 18 listing screenshots were refreshed earlier; final server processing/order and subscription image completion remain pending. Reviewer access, demonstration implementation/evidence, and replacement video remain deferred. Developer agreement remains Eric's task. No Beta App Review or App Store submission was made or represented as ready. Defaults remain United States, $2.99/month, and manual release.

### Signing and validation continuation

The configured GPG agent was accessible with authorized elevated execution. Signed commits were created and verified: frontend `a67e6fa` (routing) and `7b8e1c4` (assets and evidence), backend `7e6b213` (bootstrap), and wiki `61d8a64` (release guidance). These commits do not establish release readiness. No push, PR, tag, candidate, or deployment has been made.

Backend Release tests passed: 351 tests, zero failures or skips. The nine bootstrap guard cases and version guard passed. Both Bicep templates compiled; the local CI container image built and its version and revision labels matched. Azure CLI emitted an update-available notice. This is local validation, not deployment or live-service acceptance.

The pinned Xcode 27.1 preflight initially stopped before tests because the dedicated simulator's text-size query hung. After restarting that isolated simulator, the next run reached 409 unit tests and failed two assertions in `testFailedInvalidationPreventsCrossEnvironmentEnrollment`; its UI portion was stopped after the failure. Evidence: `TestResults/cloud-20261105T205149Z/full.log`. The test had failed optional session cleanup rather than both durable tombstone writes; its fixture was corrected to fail those writes and assert both were attempted. The corrected focused test passed under pinned Xcode: `/tmp/PumpSyncInvalidationFixture.xcresult`. Full validation remains required; the Dynamic Type checks did not run. The additional targeted routing cases, physical-device checks, deletion solution, production and review gates remain open unless subsequently verified.
