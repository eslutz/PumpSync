# PumpSync Agent Notes

## Repo Scope

- This repository is frontend-only. Do not add backend API projects, backend infrastructure, backend deploy workflows, log drains, model-cost updaters, or data-deletion tooling here.
- Backend implementation and operations belong in `eslutz/PumpSync-Backend`.
- Hosted backend container images and Azure Container Apps infrastructure are owned by `eslutz/PumpSync-Backend`. The current direction is private GitHub Container Registry images for the hosted backend, pulled by Azure Container Apps with a backend Key Vault-stored read-only package token, and public GitHub Container Registry images for self-host/demo use.
- Do not add Dockerfiles, container publishing, Azure Bicep, data deletion CLI code, or backend runbooks to this repo. If an iOS change requires backend behavior or URL changes, update the backend repo and then update `project.yml`/docs here with the resulting base URL.

## Documentation

- `docs/legal/` points to the website (https://pumpsync.ericslutz.dev/privacy/, /terms/, and /privacy/data-deletion/) as the canonical Privacy Policy, Terms of Use, and Account/Data Deletion text — do not restore local copies of that content here.
- `docs/legal/app-store-privacy.md` is repo-local App Store Connect worksheet material and is not published elsewhere; keep it here.
- `docs/app-store/` (screenshots, accessibility answers, submission evidence) is repo-local App Store Connect material, not documentation duplicated from the wiki.
- User-facing self-hosting/demo setup content lives in the wiki (https://github.com/eslutz/PumpSync/wiki/Self-Hosting, .../Demo-Mode), not this repo.

## Hosted Subscription Builds

- Local Xcode installs use the `PumpSync` scheme with the `Debug` configuration. They must point at the nonprod backend and use Apple's sandbox App Store transaction environment.
- TestFlight uploads use the `PumpSync Beta` scheme with the `Beta` archive configuration. They must point at the nonprod backend and use Apple's sandbox App Store transaction environment.
- App Store release uploads use the `PumpSync` scheme with the `Release` archive configuration. They must point at the prod backend and use Apple's production App Store transaction environment.
- Hosted backend base URLs include `/api`; the app appends `/v1/...` endpoint paths. Do not switch hosted builds to root `/v1/...` URLs.
- Self-hosted users may enter their own backend URL in app settings. See the Documentation section above for where user-facing self-host setup content lives.
- Do not add a hosted-subscription bypass or production allowlist unless the user explicitly asks for it.
- Do not add an In-App Purchase entitlement key to `PumpSync.entitlements`; StoreKit access comes from enabling the In-App Purchase capability in Apple Developer and App Store Connect.

## iOS Validation

- `project.yml` is the XcodeGen source of truth.
- Regenerate the project with `xcodegen generate` after editing `project.yml`.
- Prefer destination strings that include `OS=latest`, for example `platform=iOS Simulator,name=iPhone 17,OS=latest`, to avoid ambiguous-destination warnings.
- GitHub-hosted macOS runners may not have the same pre-created simulator models as local machines. CI should create/select an available simulator dynamically rather than relying on a hard-coded runner device.
- Keep validation output unfiltered. Raw `xcodebuild` may print Xcode/simulator runtime warnings such as `IDELaunchParametersSnapshot`, AppIntents metadata extraction notices, CA event messages, or duplicate `UIAccessibilityLoaderWebShared` messages during simulator UI tests.
