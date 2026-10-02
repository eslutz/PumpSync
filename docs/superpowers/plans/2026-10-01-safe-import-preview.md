# Safe Import Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retain meaningful public-demo review access while making synthetic Health writes impossible and preserving the user's real PumpSync setup and data.

**Architecture:** Add an authenticated preview endpoint and batch provenance to the existing backend normalization pipeline. The app shares pure conversion and preview UI across real/demo data, but permits HealthKit commit only for an eligible real batch whose captured context still matches the live session. Demo access runs in a separate foreground-only context with no real credential, ledger, metadata, preference, Health, or scheduler dependency.

**Tech Stack:** Swift 6, SwiftUI/Observation, HealthKit, CryptoKit Secure Enclave, XCTest/XCUIAutomation; .NET 10/xUnit; Eleventy/Nunjucks and Node tests; GitHub wiki Markdown.

**Spec:** [Approved design and App Review access plan](</Users/ericslutz/Developer/Code/Side Projects/PumpSync/PumpSync.wiki/App-Review-Access-Plan.md>). Executor must read both documents. Architecture and implementation authorized 2026-10-01. Local implementation and source review are complete; physical acceptance and external rollout require their stated gates.

## Global Constraints

- Minimum iOS 26.0; Swift 6.0. Retain Debug/Beta/Release endpoint and App Attest environment mapping.
- Existing live Keychain records, ledger HMAC key/digests, sync metadata, concentration, and Health records must be preserved. No reset or destructive migration.
- No new deployed test hooks, fixture launch switches, software-key simulator fallback, subscription bypass, or simulated import-success message.
- Synthetic, missing, unknown, inconsistent, or stale provenance makes zero HealthKit save calls and never updates real import history.
- Demo preview credentials and session tokens stay in memory. Any persistent device-proof identity is isolated from live import identity.
- Optional real preview must not introduce a confirmation requirement into manual/automatic real sync.
- Demo infrastructure remains in service. No teardown is planned.
- Use the owning repository for each change. Generate Xcode files from project.yml, never hand-edit them.
- Preserve all current local changes, including the completed six UI-review remediations. Record a new execution baseline; do not assume HEAD represents the current implementation.
- Do not commit unrelated work, publish, deploy, submit, send Apple messages, use private credentials, or write real Health data without task-specific authorization. Each task's commit step means a scoped local commit only if execution authorization includes commits.

## Review Focus

- A backend switches provider after session creation: mismatched response provenance must block the entire batch (Tasks 1–3).
- Missing provenance on an older server: never silently treat records as real or fall back from preview to import (Tasks 2 and 4).
- A configuration/credential change occurs during an await: stale work must not commit or reappear in the preview (Tasks 3–4).
- Opening demo with real permissions already granted and a background task pending: no synthetic save, real-state overwrite, or demo scheduled job (Tasks 3–5).
- Empty, overlapping, duplicate, partially authorized, and oversized downloads: accurate preview counts and preserved real import/deduplication behavior (Tasks 2, 3, 5–7).

---

## Execution baseline and boundaries

Current frontend HEAD: f1539c716b760a9c2a4f359ed37b23a2aace392f; backend HEAD: d4fa7cbeba8df6dda6444e2f3dc016429c176ed3.
The frontend and website contain uncommitted UI remediation; the wiki and release checklist contain this planning work. Reinspect status/hashes at execution time. Prefer an explicitly approved isolated checkout containing the needed baseline; a default-branch worktree would omit these fixes.

These are coupled API/client changes, not independent speculative subsystems. Execute contract → commit safety → orchestration → UI → documentation → evidence. A reviewer can approve each task independently at its stated test gate.

Proposed names/signatures below are implementation decisions, not existing APIs. Keep existing source behavior unless a task explicitly changes it. Do not expand this into a general authentication rewrite or clinical-data attestation project.

## File and responsibility map

Backend:
- Modify src/PumpSync.ApiContracts/TandemContracts.cs: batch provenance on TandemSyncResponse.
- Modify src/PumpSync.ApiContracts/AuthContracts.cs and src/PumpSync.Application/UseCases/GetCapabilitiesUseCase.cs: advertise supportsImportPreview.
- Create src/PumpSync.Application/UseCases/TandemBatchLoader.cs: shared window resolution, event fetching, normalization, and provenance.
- Create src/PumpSync.Application/UseCases/PreviewTandemUseCase.cs: authorized/rate-limited preview download, no import-success repository update.
- Modify src/PumpSync.Application/UseCases/SyncTandemUseCase.cs: synthetic rejection and shared loader; preserve actual server download-attempt tracking.
- Modify src/PumpSync.Application/DependencyInjection.cs and src/PumpSync.Api/PumpSyncApiEndpoints.cs: register/map the protected preview path.
- Modify src/PumpSync.Application/Abstractions/OperationalAbstractions.cs: clarify provider/provenance guarantees; existing IBackendModeProvider is the source.
- Modify tests/PumpSync.Tests/{SyncTandemUseCaseTests,PumpSyncApiIntegrationTests,GetCapabilitiesUseCaseTests,TandemContractsTests}.cs; create PreviewTandemUseCaseTests.cs.

Frontend:
- Modify PumpSync/Sources/Networking/{APIModels,PumpSyncAPIClient}.swift: batch source and preview contract.
- Create PumpSync/Sources/Sync/{ImportPlan,HealthImportPolicy,ImportPreviewController}.swift: pure conversion, eligible commit boundary, cancellable read-only preview.
- Create PumpSync/Sources/App/DemoPreviewSession.swift: isolated production networking/proof/auth context, in-memory session/credentials.
- Modify PumpSync/Sources/Auth/AuthService.swift: ephemeral BackendConfigurationStore factory and reject synthetic sessions in live-import connection purpose.
- Modify PumpSync/Sources/Tandem/TandemCredentialStore.swift: credential revision for commit invalidation; do not change persisted key names.
- Modify PumpSync/Sources/Health/HealthKitService.swift: consume converted eligible batches and recheck live context immediately before HKHealthStore.save.
- Modify PumpSync/Sources/Sync/SyncCoordinator.swift and PumpSync/Sources/App/AppServices.swift: same guarded pipeline for every real import, transient demo-preview activity gate.
- Modify PumpSync/Sources/UI/{SyncView,SettingsView}.swift; create ImportPreviewView.swift and DemoPreviewConnectionView.swift: accessible common list and explicit entry points.
- Modify PumpSync/Sources/UI/PrivacyView.swift and PumpSync/Sources/App/SupportBundleBuilder.swift: accurate preview handling and summary-only diagnostics.
- Add test files for plan/policy/controller/demo isolation and extend existing API/Health/coordinator/credential/UI tests. All fakes remain in test targets.
- Regenerate PumpSync.xcodeproj from project.yml when new files require it.

Documentation and website: Task 6 provides the exact inventory. Do not create competing privacy policy text in the wiki.

### Task 1: Protected backend preview and provenance contract

**Interfaces:** Add required JSON dataSourceMode (tandemSource | syntheticDemo) to TandemSyncResponse; add supportsImportPreview: true to capabilities. Use existing TandemSyncRequest fields. New POST /api/v1/preview/tandem returns TandemSyncResponse. Old POST /api/v1/sync/tandem on synthetic deployments returns HTTP 409, error code synthetic_preview_only, with no samples.

Shared signature: TandemBatchLoader.LoadAsync(AuthenticatedUser user, TandemSyncRequest request, CancellationToken cancellationToken) -> Task<TandemSyncResponse>. It resolves the effective window and calls the existing event client/normalizer once; derives mode from IBackendModeProvider. PreviewTandemUseCase.ExecuteAsync has the same input/return signature as SyncTandemUseCase.ExecuteAsync. Import/preview share the existing aggregate sync-tandem limit of 12 downloads per hour; alternating routes must not double the allowance. Preview does not call ISyncStateRepository.MarkSucceededAsync or describe server fetch as a confirmed client import.

- [x] Add failing serialization/use-case tests: real and synthetic batches emit the configured source; empty batches still emit provenance; request fields cannot select source; synthetic import throws a new SyntheticPreviewOnlyException before event fetching (create src/PumpSync.Domain/Sync/SyntheticPreviewOnlyException.cs and map it to the specified 409 in PumpSyncErrorMiddleware); preview uses the same normalizer/window and never writes raw payloads or import-success state.
- [x] Add failing route tests: both preview modes require normal authorization/access; unauthenticated request returns 401; synthetic old-import route returns 409/no samples; real old-import route still succeeds; alternating preview/import exhaust the same limit; capabilities advertises preview.
- [x] Run focused xUnit tests and confirm failures correspond to the new behavior: dotnet test PumpSync.Backend.slnx --configuration Release --filter "FullyQualifiedName~PreviewTandemUseCaseTests|FullyQualifiedName~SyncTandemUseCaseTests|FullyQualifiedName~PumpSyncApiIntegrationTests|FullyQualifiedName~GetCapabilitiesUseCaseTests|FullyQualifiedName~TandemContractsTests".
- [x] Implement the shared loader, use-case wrappers, injected mode source, error mapping, and endpoint registrations. Keep Session protocol 3 and /api/v1 paths; add no unprotected synthetic route. Preserve cancellation, access/entitlement checks, and payload non-retention. Update exact contract documentation in docs/synthetic-demo.md alongside this task.
- [x] Rerun focused tests, then dotnet build PumpSync.Backend.slnx --configuration Release and dotnet test PumpSync.Backend.slnx --configuration Release. Expected: all pass, warnings treated as errors. Run git diff --check.
- [ ] Review the scoped diff and make a focused local commit if authorized; keep deployment separate. Deliverable: new authenticated download preview and old-client synthetic import protection, without changing app authentication.
### Task 2: Pure import plan and final Health write policy

**Interfaces:** DataSourceMode is a Swift enum with tandemSource, syntheticDemo, and unknown decoding behavior. ImportSessionSnapshot contains canonical backend identity, configurationRevision, credentialRevision, sessionFamilyId, and dataSourceMode; ImportContextProvider.currentSnapshot() -> ImportSessionSnapshot? derives these from the live auth/configuration/credential stores; it contains no tokens/passwords. ImportPlan captures that snapshot, concentration, effective window, and [PlannedImportSample]. PlannedImportSample carries original SampleDTO and convertedValue: Decimal.

ImportPlanner.makePlan(response: TandemSyncResponse, context: ImportSessionSnapshot, concentration: InsulinConcentration) throws -> ImportPlan. HealthImportPolicy.authorize(plan: ImportPlan, current: ImportSessionSnapshot) throws -> HealthImportBatch. HealthImportBatch has immutable plan/context and no freely usable initializer outside the policy. HealthImportPolicy.validate(batch: HealthImportBatch, current: ImportSessionSnapshot?) throws is called again by the final Health adapter. SyncHealthWriting.save(batch: HealthImportBatch) async throws -> [SampleDTO] replaces the raw sample-array write API.

- [x] Add failing ImportPlanTests and HealthImportPolicyTests: synthetic/synthetic, missing source, unknown source, mismatched session/response, changed endpoint/revision/credentials/session family all reject Health authorization. Synthetic plans remain displayable. Empty real batch is valid but makes no save call. U100/U200/U500 conversion uses factors 1/2/5 exactly once.
- [x] Add failing validation tests for nonfinite/negative values, inverted dates, unsupported types/units. Supported wire types are insulin.bolus, insulin.basal (IU), and nutrition.carbohydrates (g); zero values remain valid. Invalid input blocks the batch with an actionable reason rather than silently claiming a complete import. Preserve source IDs and metadata. Add a test that duplicate IDs with inconsistent values reject rather than arbitrarily choosing one.
- [x] Add Health adapter tests with a recording persistence boundary: already-granted permissions do not admit synthetic/unknown/stale batches; validation occurs immediately before save; per-type denial omits only that authorized-type subset and returns exactly confirmed written samples; concentration is not reapplied by the adapter. Keep recording implementations in PumpSyncTests.
- [x] Run the new focused tests with xcodebuild test -project PumpSync.xcodeproj -scheme PumpSync -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:PumpSyncTests/ImportPlanTests -only-testing:PumpSyncTests/HealthImportPolicyTests -only-testing:PumpSyncTests/HealthAccessTests and confirm the intended failures.
- [x] Implement these types and signatures. Inject a production current-context provider into HealthKitService from AppServices so the final guard checks live state. Remove raw save(samples:concentration:) call paths; retain Health metadata/units and exact confirmed-write return behavior. Use a same-actor last check with no intervening suspension before submitting HKHealthStore.save.
- [ ] Rerun focused tests and source-search all HKHealthStore/save and SyncHealthWriting call sites. Expected: no production path can submit a bare batch without the policy; all tests pass. Run git diff --check and review/commit the scoped change if authorized.
### Task 3: Preserve existing real sync through the guarded pipeline

**Interfaces:** Existing sync(reason:) and refreshIfStale(reason:) remain entry points. SyncCoordinator captures ImportSessionSnapshot and concentration once per coalesced operation, builds ImportPlan, filters already-imported records, authorizes HealthImportBatch, and updates the ledger/watermark only from returned confirmed writes. Retry within an operation preserves its inputs; a new operation captures new inputs. Add TandemCredentialStore.revision, incremented on in-memory credential/validation changes without rewriting persisted key names.

Live AuthService rejects a synthetic session for live-import use before persisting it, with message This service supplies sample data. Open Sample Preview instead. Missing/unknown source produces an upgrade/source-verification error. A dedicated preview auth context in Task 4 may admit synthetic sessions normally; it never supplies live importer context.

- [x] Extend SyncCoordinatorTests with suspended download, config switch, credential edit/removal, session refresh/re-enrollment, and concentration mutation. Assert stale/synthetic responses make zero writer calls and preserve watermark/ledger. Ensure a coalesced caller cannot change the captured concentration.
- [x] Extend real regression tests for repeated/overlapping downloads, retries, partial Health permissions, cancellations before/after save submission, lookback clamp, and existing ledger digests. Assert confirmed writes are ledgered even when cancellation follows an already-submitted save, but abandoned work does not publish success.
- [x] Add entry-point tests for manual, appOpen, granted background, retry-after-subscription, and Open PumpSync followed by foreground recovery. No sync App Intent currently exists; protect any future entry by the same coordinator policy rather than inventing a new intent here.
- [x] Run focused coordinator/auth/credential tests and confirm newly specified failures, then integrate Task 2 APIs. Ordinary token refresh within the same session family/source does not invalidate an otherwise matching batch; re-enrollment into a new family does. Credential revision changes only when credentials/validation change, not on a read or refresh of identical state. Do not clear or repartition the user's existing ledger or watermark to make tests pass.
- [x] Handle synthetic/unknown eligibility before recording live sync attempts/errors in persistent SyncMetadataStore. Report refusal in transient operation state/summary diagnostics; never advance real success. On configuration changes, invalidate work through operation identities, not merely cancellation of a view task.
- [ ] Rerun focused tests, inspect all coordinator call sites and current default-backed record keys, then run git diff --check. Review/commit the scoped change if authorized. Deliverable: unchanged legitimate sync behavior with a guarded final destination.
### Task 4: Read-only fetch controller and isolated demo session

**Interfaces:** PumpSyncAPIClient.previewTandem(_:accessToken:) async throws -> TandemSyncResponse uses only /preview/tandem. PumpSyncAPIClient.capabilities() async throws -> BackendCapabilitiesResponse decodes dataSourceMode and supportsImportPreview (missing flag means false); preserve warmup() as activation-only. ImportPreviewController.init(apiClient: PumpSyncAPIClient, authService: AuthService) uses the current authenticated token internally; load(request: TandemSyncRequest, context: ImportSessionSnapshot, concentration: InsulinConcentration) async and cancel() own request identity and publish idle/loading/ready(ImportPlan)/failed state. Preview performs no Health authorization/save and holds no ImportedSampleLedger or SyncMetadataStore dependency.

DemoPreviewSession.make(baseURL: URL) creates a separate API client, normal DeviceSessionProofProvider, AuthService without a sessionStore, and BackendConfigurationStore.ephemeral(selfHostedBaseURL: URL, installationId: String). The factory uses the existing demo URL including /api; inputs/credentials stay in memory. Store only the separate preview installation identity/device-proof key under a distinct demo-preview namespace, never the live identity or real credential accounts. connect() uses ordinary secure session enrollment; validate(credentials: TandemCredentials) async throws uses ordinary credential validation. close() cancels work, clears tokens/credentials and unregisters this foreground context; it never calls AppServices.live(), registers a background handler, or starts StoreKit listeners.

- [x] Add failing API tests for required provenance decoding, protected preview request/path, 401/409/429/timeouts, missing supportsImportPreview, malformed response, and rejection of redirect-induced endpoint/context changes. Unknown/missing mode must become non-importable. Do not fall back to /sync/tandem on unsupported servers.
- [x] Add ImportPreviewControllerTests: no Health permission needed; zero authorization/writer/ledger/metadata calls; late/canceled/replaced results discarded; backgrounding clears fetched payload; captured concentration stays stable; effective window shown; empty result remains a genuine preview.
- [x] Add DemoPreviewSessionTests seeding live session/configuration/credential/ledger/metadata/concentration records. Compare those records byte-for-byte before and after demo connect, validation, load, retry, failure, close, and interruption. Assert no real Tandem credentials are submitted to the demo endpoint and no demo credentials are persisted in live Keychain.
- [x] Run these test classes with -only-testing, confirm intended failures, then implement ephemeral configuration persistence (optional backing store with existing live defaults behavior retained), isolated auth-purpose handling, production hardware proofs, and controller. All server stubs remain in test targets.
- [x] Add AppServices.beginDemoPreview() -> Bool and endDemoPreview() to own a transient demo-preview activity lease, released on dismissal, cancellation, and backgrounding. The guard is shared by the same live AppServices/coordinator instance used by the registered background handler. Add a skippedPreviewActive SyncRunOutcome so deferral is not reported as a successful import or a persisted error. Add AppServices demo-preview activity state. Opening demo while live sync runs is disabled; acquiring the activity state and checking sync status occurs atomically on the main actor. Foreground/granted-background import entry points defer while active without modifying existing scheduled requests or live metadata. Opening demo never cancels an already-submitted real save. Closing clears the activity state; normal real-sync policy can resume afterward.
- [x] Test concurrent demo opening/live sync start, a background callback during demo, resume after close, app suspension, expiration, and quit/relaunch. Expected: no demo background work, no real-state mutation attributable to preview, and no permanently stuck live-sync gate.
- [ ] Run focused tests and git diff --check, then review/commit if authorized. Deliverable: authenticated isolated sample preview without shipping mocks or changing the personal real setup.
### Task 5: Shared accessible product preview

**Interfaces:** ImportPreviewView renders an ImportPreviewController's immutable ImportPlan with stable row identity (source/type/external ID), accessible details, converted Health values, captured concentration, and effective date range. DemoPreviewConnectionView owns demo-only input/range/concentration and the isolated session. No preview view has an Import/Save-to-Health action.

SyncView adds Preview Import next to the normal Sync action; enabled for authenticated validated real data even if Health write permission is denied. Use the same request-range calculation as SyncCoordinator without persisting a new range. SettingsView adds Sample Preview without changing the live connection selector or real credential form. Demo range defaults to Past 2 days; its local concentration defaults to U100 and is clearly shown. Close returns to the existing live setup.

- [x] Add failing presentation/controller tests for exact copy: Sample data — nothing is saved to Apple Health; Preview only — nothing has been saved to Apple Health; No records in this range. Counts mean downloaded records, including previously imported ones; never claim new/imported counts or fake success.
- [x] Add UI tests for real preview with denied Health permission, demo discovery without replacing live settings, invalid credentials/endpoint/timeout feedback, loading cancellation, close/back, and retry. Use actual disconnected/system screens where safely reachable; any synthetic UI setup stays external/test-target only and is labeled as such.
- [x] Implement screens using existing GlassSection/adaptive layout conventions. Use lazy lists for large ranges, localized formatting, deterministic ordering, readable basal intervals/time zones, and row detail disclosure. Never dump raw payloads/tokens into logs or support bundles. Do not add export of preview records in this scope.
- [x] Add summary-only diagnostic events: purpose, declared source, sample count, operation state and sanitized failure; no usernames, values, timestamps, source IDs, or preview payloads. Real subscription flow remains separately available and never bypassed by preview.
- [ ] Exercise standard text/AX5, light/dark, Increase Contrast, Reduce Motion, small iPhone/iPad layouts, dismissal and keyboard reachability. Perform actual device VoiceOver on real/demo preview rows, local validation, loading outcomes, and modal transitions. Accept only inspected settled screenshots with numbered flow health.
- [ ] Run focused UI/presentation tests and git diff --check. Review/commit if authorized. Deliverable: genuine readable preview, safe demo access, and unchanged normal real-import affordances.
### Task 6: Documentation, policy, and review instructions

**Files:**
- Wiki: App-Review-Access-Plan.md, Demo-Mode.md, Features-and-Modes.md, Architecture.md, Testing-and-Verification.md, Getting-Started.md, Backend-Operations.md, App-Store-and-Privacy.md, _Sidebar.md.
- Backend: docs/synthetic-demo.md, docs/configuration.md, docs/docker-self-host.md, docs/security-and-privacy.md, docs/backend-observability.md, docs/azure-container-apps.md, README.md; touch only statements affected by preview/provenance/rollout.
- Frontend: docs/app-store/release-preparation.md, docs/app-store/accessibility.md, docs/legal/app-store-privacy.md, docs/connection-recovery.md, docs/reviews/2026-10-01-ui/report.md; capture updated listing/preview assets only where they show changed UI or claims.
- Website: src/support/index.njk, src/privacy/index.njk, src/terms/index.njk where affected; test/site.test.mjs. Inspect shared src/_data claims before changing duplicated sentences.

- [x] Update Demo Mode from an import/delete walkthrough to the separate authenticated Sample Preview flow. Remove the simulator-connect promise because hardware proofs remain required; distinguish local backend integration tests from actual iPhone demo authentication.
- [ ] Document exact endpoint/error/provenance/capability changes in backend-owned references, stable release requirements for self-hosters, and immutable demo image deployment procedure. Explain server download success does not prove a Health commit.
- [x] Update public support/FAQ to say sample data never enters Health after this release; remove the test-device/delete-fake-data advice. Update privacy to cover credentials sent for preview, in-memory payload lifetime/clear-on-dismissal, operational metadata, and unchanged legitimate Health writes. Preserve validation wording from UI-06. Do not claim changed server retention without implementing and verifying it.
- [x] Add site content invariants for preview/no-synthetic-Health messaging and unchanged validation/sync/preview credential triggers. Run npm test from PumpSync.website; expected all Node and HTML checks pass.
- [x] Update release/accessibility checklist and report with new preview flows, protection tests, real-data device acceptance, and explicit remaining Apple confirmation. Preserve the original six audit findings and evidence; append this architecture's acceptance status rather than rewriting original observations.
- [x] Prepare reviewer steps covering demo auth/validation/download/preview plus normal hosted subscription purchase/restore, and attach planned real-device evidence. State explicitly what the preview cannot do. Do not send notes, upload media, or claim Apple's acceptance during documentation work.
- [x] Search all four repositories for synthetic Health write/delete advice, public-demo removal plans, outdated route/source claims, and wording that presents preview as imported data. Reconcile affected narrative in the wiki and public policy only in the website. Add wiki links using page names, check anchors/local links, and run git diff --check in each changed repo.
- [ ] Review/commit focused documentation changes if authorized, coordinated with the implementation's publication timing. Existing unsafe behavior must remain identified until deployed; never publish future safety guarantees ahead of protection.
### Task 7: Automated and physical acceptance

- [ ] Run backend full Release build/tests, then docker build -t pumpsync-backend:preview-local .; smoke protected real/synthetic preview in isolated test deployments. Expected: valid provenance; authenticated preview works; unauthenticated 401; synthetic old-import 409/no payload; normal real endpoint retains behavior. No production writes/deployments.
- [x] Run bash scripts/ios/validate-tests.sh from PumpSync.frontend. Expected: all unit/UI tests pass, zero warning matches, raw log retained. Verify Beta and Release builds with unchanged signing/endpoint configuration; inspect built app artifacts for new test-target classes, credentials or hooks rather than mistaking test-only source files for deployed code.
- [x] Run npm test from PumpSync.website and git diff --check in all touched repositories. Update exact tested commits/dirty baseline and test counts in acceptance evidence.
- [ ] On an authorized physical iPhone with real data already present, record non-secret before/after fingerprints of live credential/configuration/ledger/metadata state through test-target tooling, plus Health source totals/representative records visible to the user. Do not add broad Health read permission merely to collect acceptance evidence.
- [ ] With insulin/carbohydrate write access already enabled, exercise demo connection/validation/preview/retry/background/close. Verify no synthetic source appears and existing real records/settings remain intact. Automated zero-writer tests and call-site audit complement the manual observation; do not claim screenshots alone prove absence of writes.
- [ ] Separately exercise legitimate real imports, partial permissions, repeat-sync duplicate prevention, interruption/recovery, preview with no permission, actual VoiceOver, and Reduce Motion. Do not revoke permissions needed by the user's regular workflow without restoring them afterward. Any genuine writes require explicit session authorization.
- [ ] Capture numbered screenshot evidence, outcome logs and privacy-safe support summaries. Record blocked conditions candidly; scheduled background requests are not proof of execution. Evidence from new UI must correspond to the candidate build under review.
- [ ] Review all cross-repo diffs and acceptance evidence. Gate release on zero synthetic saves, preserved real state, contract compatibility, successful real device flow, and required manual accessibility checks.
### Task 8: Review agreement and coordinated rollout

- [x] Prepare a concrete Apple question explaining Tandem account constraints and the preview/video arrangement; request confirmation under guideline 2.1 and ask what extra access is required. Obtain authorization before sending/booking or submitting.
- [ ] Record Apple's response in App-Review-Access-Plan.md without private contact/account information. Do not equate local implementation approval with Apple review approval.
- [ ] Before deployment, record current immutable backend/demo image revisions and frontend candidate, affected routes, verification commands, and rollback procedure. Protection-first rollback rule: do not restore a synthetic /sync/tandem route that supplies samples to legacy clients.
- [ ] Deploy the protected preview-capable demo backend first when authorized. Ensure all old serving replicas are drained or protected before declaring zero synthetic import delivery. Old demo clients should stop receiving synthetic import data; verify unauthenticated protection, normal challenge/proof enrollment, preview dataSourceMode, and legacy 409. Publish compatible reviewer instructions only when the new app is available.
- [ ] Deploy provenance-capable nonproduction/production real backends before distributing the new client when authorized. Older clients tolerate the added JSON field; new clients block missing fields and offer an upgrade message. Self-host release notes state the minimum preview-capable backend version determined by the release tag; do not invent a numeric version during planning.
- [ ] Distribute the candidate through the existing Beta/TestFlight path when authorized and rerun the authenticated acceptance affected by distribution/App Attest/StoreKit.
- [ ] Submit only after the agreed reviewer path is working, backend remains reachable, and review notes/video match the exact candidate. Keep the demo service running through review; no decommission task exists.

## Completion and execution handoff

The user authorized this architecture implementation on 2026-10-01. The original UI remediation remains part of the preserved working baseline.
Execution: task-by-task subagent implementation/review, because the API contract, async session isolation, and final Health boundary need independent checks. An executor must preserve all existing local work and follow repository authorization boundaries.
No automatic push, publish, deployment, App Review message, private-credential use, or Health write is included in plan approval alone.

## Execution status — 2026-10-02

Tasks 1–6 are implemented locally and independently reviewed. Final review found one backend provider/provenance inconsistency for padded synthetic configuration and one in-app privacy-copy omission; both are fixed and approved in scoped re-review. Checkboxes mark completed implementation and automated evidence; steps combining review with a conditional commit remain unchecked because no commits were authorized or made.

The full iOS warning gate passed 290 unit and 14 UI tests; the site passed 19 tests and HTML validation. Unsigned Beta/Release builds passed. After the final safety fix, the backend Release build passed with zero warnings/errors, all 301 tests passed, and the rebuilt local image passed a padded-synthetic configuration smoke. Standard/AX5 rendering and the actual simulator Sample Preview form were inspected; the complete manual accessibility matrix and authenticated physical flows remain pending. USB pairing and Developer Mode were verified on the connected iPhone on 2026-10-02. No device app replacement or Health write was performed.

Task 7 physical checks and Task 8 rollout/Apple actions remain gates. The Apple question is drafted and unsent. See [candidate acceptance](../../reviews/2026-10-01-preview/acceptance.md) for exact evidence and limits.
