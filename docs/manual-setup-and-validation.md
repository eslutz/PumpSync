# Manual Setup and Validation

These items require account access, production credentials, a physical Apple device, or product feedback. Everything else should be automated in the repo.

## Apple Developer

- Create the App ID for `com.ericslutz.PumpSync`.
- Enable HealthKit and Sign in with Apple capabilities.
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
  - `AZURE_LOCATION`
  - `AZURE_RESOURCE_GROUP`
  - `AZURE_FUNCTION_APP_NAME`
- Add deployment-time secret values:
  - `APPLE_CLIENT_ID`
  - `PUMPSYNC_SERVICE_TOKEN_SIGNING_KEY`
  - `AZURE_SQL_ADMIN_LOGIN`
  - `AZURE_SQL_ADMIN_PASSWORD`
  - `LogDrain__SharedSecret`
- Run the `Deploy Backend` workflow for `nonprod`, then `prod` after validation.
- Apply `infra/sql/001_initial_schema.sql` to the deployed Azure SQL database.

## GitHub

- Enable branch protection or rulesets once the initial CI runs have created stable status check names.
- Require pull request review for `main` if the repo will have multiple contributors.
- Confirm repository visibility before adding real deployment secrets.

## Product and Legal

- Write and publish the privacy policy.
- Write terms of use and account/data deletion instructions.
- Complete App Store privacy nutrition labels.
- Review HealthKit wording and Tandem credential disclosure text.

## End-to-End Release Gate

The release gate is not complete until a signed iPhone build:

- signs in with Apple against the deployed backend;
- saves Tandem credentials only in device Keychain;
- fetches real Tandem data over HTTPS;
- writes insulin and carbohydrate samples to Apple Health;
- purges raw and normalized Tandem payloads after write;
- refreshes on app open, manual sync, and a scheduled background task when iOS grants execution;
- emits no Tandem credentials, tokens, raw events, or normalized samples to backend durable storage or logs.
