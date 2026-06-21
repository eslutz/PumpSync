# Manual Setup and Validation

These items require account access, production credentials, a physical Apple device, or product feedback. Everything else should be automated in the repo.

## Apple Developer And App Store Connect

- Create the App ID for `dev.ericslutz.PumpSync`.
- Enable HealthKit.
- Enable In-App Purchase for the App ID and app record.
- Remove Sign in with Apple from the App ID unless another future feature reintroduces account login.
- Create the PumpSync Hosted auto-renewable subscription product, currently `dev.ericslutz.PumpSync.hosted.monthly`.
- Configure App Store Server Notifications to call:
  - nonprod: `https://func-pumpsync-nonprod-flex-api.azurewebsites.net/api/v1/app-store/notifications`
  - prod: `https://func-pumpsync-prod-flex-api.azurewebsites.net/api/v1/app-store/notifications`
- Create the App Store Server API key used by backend settings `AppStore__IssuerId`, `AppStore__KeyId`, and `AppStore__PrivateKey`.
- Configure `AppStore__RootCertificatePem` with the Apple root certificate used to pin signed App Store payload verification.
- Create signing certificates and provisioning profiles for local device testing and App Store/TestFlight builds.
- Use the iOS build routing matrix:
  - local Xcode installs: `PumpSync` scheme, `Debug` configuration, nonprod backend, sandbox App Store transactions;
  - TestFlight uploads: `PumpSync Beta` scheme, `Beta` archive configuration, nonprod backend, sandbox App Store transactions;
  - App Store releases: `PumpSync` scheme, `Release` archive configuration, prod backend, production App Store transactions.
- Validate the iOS app on a physical iPhone with HealthKit authorization enabled.
- Validate iPad layout on the iPad Pro 13-inch simulator in portrait and landscape, including Status, Sync, Settings, Tandem Account, Apple Health, Data Handling, Developer, and hosted subscription presentation.
- Regenerate iPad App Store listing screenshots with `scripts/ios/capture-ipad-app-store-screenshots.sh` before submission.

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
  - `APPSTORE_BUNDLE_ID`
  - `APPSTORE_ENVIRONMENT` (`Sandbox` for nonprod, `Production` for prod)
  - `APPSTORE_SUBSCRIPTION_PRODUCT_ID`
  - `APPSTORE_ISSUER_ID`
  - `APPSTORE_KEY_ID`
  - `APPSTORE_ROOT_CERTIFICATE_PEM`
  - `PUMPSYNC_MODEL_COST_UPDATER_SCHEDULE` if the default daily schedule is not desired
  - `PUMPSYNC_MODEL_COST_CATALOG_URL` when the updater should call a real catalog
- Add deployment-time secret values:
  - `APPSTORE_PRIVATE_KEY`
  - `PUMPSYNC_SERVICE_TOKEN_SIGNING_KEY`
  - `PUMPSYNC_LOG_DRAIN_SHARED_SECRET`
- Run the `Deploy Backend` workflow for `nonprod`, then `prod` after validation.
- Confirm the deployed Function Apps are the Flex Consumption apps named `func-pumpsync-<environment>-flex-api`, `func-pumpsync-<environment>-flex-log`, and `func-pumpsync-<environment>-flex-cost`; do not recreate the old classic Consumption plan.
- Confirm the storage account contains the Table Storage tables output by the Bicep deployment.

## Self-Hosted Package

- Document the minimum required settings for a self-hosted backend:
  - `PumpSync__BackendMode=SelfHosted`
  - `PumpSync__ServiceTokenIssuer`
  - `PumpSync__ServiceTokenAudience`
  - `PumpSync__ServiceTokenSigningKey`
  - `AzureStorage__ConnectionString` or `AzureStorage__AccountName`
  - Table name settings from `AzureStorage__*TableName`
- Provide a deployment example for users who want to host the backend in their own Azure subscription.
- Validate the iOS self-hosted URL field against a backend deployed with `PumpSync__BackendMode=SelfHosted`.

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

- buys or restores a hosted subscription against the deployed backend with a matching App Store environment, or connects to a self-hosted backend URL;
- saves Tandem credentials only in device Keychain;
- validates Tandem credentials through the selected backend;
- fetches real Tandem data over HTTPS;
- writes insulin and carbohydrate samples to Apple Health;
- purges raw and normalized Tandem payloads after write;
- refreshes on app open, manual sync, and a scheduled background task when iOS grants execution;
- emits no Tandem credentials, tokens, raw events, or normalized samples to backend durable storage or logs.

The iPad release gate is not complete until the iPad simulator layout pass and App Store screenshot capture both pass without clipped text, broken navigation, or missing screenshot assets.

For subscription test behavior, use Apple's current guidance:

- Sandbox testing: https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox/
- TestFlight in-app purchases and subscriptions: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/
- StoreKit Testing in Xcode: https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox
