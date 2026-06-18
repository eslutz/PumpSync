# Manual Setup and Validation

These items require account access, production credentials, a physical Apple device, or product feedback. Everything else should be automated in the repo.

## Apple Developer

- Create the App ID for `dev.ericslutz.PumpSync`.
- Enable HealthKit and Sign in with Apple capabilities.
- Configure Sign in with Apple as a primary App ID and enter the server-to-server notification endpoint URL:
  - nonprod: `https://func-pumpsync-nonprod-flex-api.azurewebsites.net/api/v1/auth/apple/notifications`
  - prod: `https://func-pumpsync-prod-flex-api.azurewebsites.net/api/v1/auth/apple/notifications`
- Create/configure the Sign in with Apple Services ID used by the backend `Apple__ClientId` setting.
- Create signing certificates and provisioning profiles for local device testing and App Store/TestFlight builds.
- Validate the iOS app on a physical iPhone with HealthKit authorization enabled.

## Tandem

- Validate Tandem Source authentication against real US and EU accounts.
- Confirm current Tandem endpoint behavior, rate limits, MFA behavior, and schema drift handling.
- Confirm whether Tandem terms allow this sync workflow and what user-facing disclosures are required.

## Azure

- Create the Azure subscription/resource group deployment identity.
- Add GitHub environment secrets:
  - `AZURE_CLIENT_ID`
  - `AZURE_TENANT_ID`
  - `AZURE_SUBSCRIPTION_ID`
- Add GitHub environment variables:
  - `AZURE_LOCATION` (`eastus2` for the currently deployed nonprod environment)
  - `AZURE_RESOURCE_GROUP` (`rg-pumpsync-nonprod` or `rg-pumpsync-prod`)
  - `AZURE_SQL_SERVER` (`ericslutz-dev-db.database.windows.net` for the shared SQL server)
  - `AZURE_SQL_DATABASE` (`ericslutz.dev.db` for the shared SQL database)
  - `PUMPSYNC_MODEL_COST_UPDATER_SCHEDULE` if the default daily schedule is not desired
  - `PUMPSYNC_MODEL_COST_CATALOG_URL` when the updater should call a real catalog
- Add deployment-time secret values:
  - `APPLE_CLIENT_ID`
  - `PUMPSYNC_SERVICE_TOKEN_SIGNING_KEY`
  - `PUMPSYNC_LOG_DRAIN_SHARED_SECRET`
- Run the `Deploy Backend` workflow for `nonprod`, then `prod` after validation.
- Confirm the deployed Function Apps are the Flex Consumption apps named `func-pumpsync-<environment>-flex-api`, `func-pumpsync-<environment>-flex-log`, and `func-pumpsync-<environment>-flex-cost`; do not recreate the old classic Consumption plan.
- Apply `infra/sql/001_initial_schema.sql` to the shared Azure SQL database.
- Create a SQL contained user for the backend managed identity and grant only the schema permissions PumpSync needs.

## GitHub

- Enable branch protection or rulesets once the initial CI runs have created stable status check names.
- Require pull request review for `main` if the repo will have multiple contributors.
- Confirm repository visibility before adding real deployment secrets.

## Product and Legal

- Publish the privacy policy from `docs/legal/privacy-policy.md` to the public App Store privacy policy URL.
- Publish the terms of use and account/data deletion instructions from `docs/legal/terms-of-use.md` and `docs/legal/data-deletion.md`.
- Enter the App Store privacy nutrition labels from `docs/legal/app-store-privacy.md`.
- Review HealthKit wording and Tandem credential disclosure text against the final shipped build and Tandem terms review.

## End-to-End Release Gate

The release gate is not complete until a signed iPhone build:

- signs in with Apple against the deployed backend;
- saves Tandem credentials only in device Keychain;
- fetches real Tandem data over HTTPS;
- writes insulin and carbohydrate samples to Apple Health;
- purges raw and normalized Tandem payloads after write;
- refreshes on app open, manual sync, and a scheduled background task when iOS grants execution;
- emits no Tandem credentials, tokens, raw events, or normalized samples to backend durable storage or logs.
