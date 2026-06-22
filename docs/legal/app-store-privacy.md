# App Store Privacy Answers

Effective date: 2026-06-18

These answers are the intended App Store Connect privacy nutrition label inputs for the current PumpSync MVP. Re-check this file before every App Store or TestFlight submission if dependencies, telemetry, subscriptions, analytics, crash reporting, or backend retention change.

Apple requires developers to disclose collected data in App Store Connect, including data collected by integrated third-party partners. Apple also treats data transmitted off device and retained beyond real-time request servicing as collected data.

Reference sources:

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Apple App Review Guidelines, Privacy: https://developer.apple.com/app-store/review/guidelines/#privacy
- Apple App Review Guidelines, Health and Health Research: https://developer.apple.com/app-store/review/guidelines/#health-and-health-research

## Tracking

- Data used to track the user: No.
- Third-party advertising: No.
- Developer advertising or marketing: No.
- Data broker sharing: No.

## Data Linked To The User

Declare these as linked to the user and used for App Functionality:

- Identifiers: User ID, consisting of the PumpSync internal ID, App Store original transaction ID, and app installation ID.
- Purchases: Purchase History, for the PumpSync Hosted subscription.

Declare these as linked to the user and used for App Functionality and diagnostics/service operation if retained in backend telemetry:

- Diagnostics: Crash Data, Performance Data, or Other Diagnostic Data, only if collected by App Store Connect, Apple diagnostics, Azure Application Insights, or another configured telemetry provider.

## Health And Fitness Data

PumpSync handles Tandem health data and writes insulin/carbohydrate samples to Apple Health. For the MVP backend contract, raw Tandem events and normalized samples are transmitted to the backend only to service the active sync request and are not retained after the response.

If App Store Connect asks whether Health data is collected, answer based on the current implementation and Apple's current definition of collection. For the current MVP design:

- Health data is processed to service a real-time sync request.
- Health data is not retained on PumpSync servers.
- Health data is not used for tracking, advertising, marketing, or data mining.
- Health data is written to Apple Health only with user permission.

If any future telemetry, logging, analytics, support workflow, backup, database table, or third-party SDK retains health data beyond real-time request servicing, update this answer and the privacy policy before release.

## Data Not Collected By PumpSync

Do not declare these unless the implementation changes:

- Precise Location or Coarse Location.
- Contacts.
- Photos or Videos.
- Audio Data.
- Browsing History.
- Search History.
- Advertising Data.
- Device ID for tracking or advertising.
- Sensitive Info beyond the Health data handling described above.

## Privacy Links

Use the public URL for `docs/legal/privacy-policy.md` as the required Privacy Policy URL after it is published on the product website or another public support page.

Use the public URL for `docs/legal/data-deletion-request.md` as the optional Privacy Choices URL after it is published.

## HealthKit Submission Wording

Use this wording in App Review notes and public support material:

PumpSync writes Tandem insulin and carbohydrate samples to Apple Health after the user connects PumpSync Hosted or a self-hosted backend, stores Tandem credentials on device, grants Health permission, and starts sync. PumpSync does not provide medical advice, diagnosis, treatment, or dosing recommendations. PumpSync does not use HealthKit data for advertising, marketing, or data mining.

## Required Review Before Submission

Before App Store submission, verify:

- The privacy policy URL is publicly accessible.
- The data deletion URL is publicly accessible.
- App Store Connect answers match the shipped build and all SDKs.
- HealthKit purpose strings match the app's actual data use.
- Tandem disclosure wording matches the final Tandem terms review.
