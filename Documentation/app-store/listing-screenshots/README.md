# App Store Listing Screenshots

Each capture script archives the existing screenshots for its platform before replacing them. Archives are written to `archive/` in this directory with timestamped names.

The iPhone screenshots are captured in light mode from the iPhone 18 Pro Max simulator using the screenshot UI-test fixture at its native `1320 x 2868` resolution. Set the selected simulator's appearance to light before capture and verify the output; the script does not change the simulator's appearance. Captures are not cropped or stretched. The historical `iphone-6-7` filename prefix is retained for upload continuity. Run:

```sh
Scripts/ios/capture-iphone-app-store-screenshots.sh
```

- `iphone-6-7-app-store-listing-01-status-overview.png`: App Store listing screenshot for the initial Sync screen.
- `iphone-6-7-app-store-listing-02-sync-workflow.png`: App Store listing screenshot for the Sync tab workflow.
- `iphone-6-7-app-store-listing-03-settings-pumpsync.png`: App Store listing screenshot for PumpSync connection settings.
- `iphone-6-7-app-store-listing-04-subscription-benefits.png`: App Store listing screenshot for the subscription benefits screen.
- `iphone-6-7-app-store-listing-05-settings-self-hosted-connection.png`: App Store listing screenshot for self-hosted connection settings.
- `iphone-6-7-app-store-listing-06-tandem-account.png`: App Store listing screenshot for Tandem account setup.
- `iphone-6-7-app-store-listing-07-apple-health.png`: App Store listing screenshot for Apple Health access.
- `iphone-6-7-app-store-listing-08-data-handling.png`: App Store listing screenshot for data handling.
- `iphone-6-7-app-store-listing-09-developer.png`: App Store listing screenshot for diagnostics and support export.

The iPad screenshots are captured from the iPad Pro 13-inch simulator using the screenshot UI-test fixture. Run:

```sh
Scripts/ios/capture-ipad-app-store-screenshots.sh
```

- `ipad-pro-13-app-store-listing-01-status-overview.png`: App Store listing screenshot for the initial Sync screen on iPad.
- `ipad-pro-13-app-store-listing-02-sync-workflow.png`: App Store listing screenshot for the Sync workflow.
- `ipad-pro-13-app-store-listing-03-settings-pumpsync.png`: App Store listing screenshot for PumpSync connection settings.
- `ipad-pro-13-app-store-listing-04-subscription-benefits.png`: App Store listing screenshot for the subscription benefits screen.
- `ipad-pro-13-app-store-listing-05-settings-self-hosted-connection.png`: App Store listing screenshot for self-hosted connection settings.
- `ipad-pro-13-app-store-listing-06-tandem-account.png`: App Store listing screenshot for Tandem account setup.
- `ipad-pro-13-app-store-listing-07-apple-health.png`: App Store listing screenshot for Apple Health access.
- `ipad-pro-13-app-store-listing-08-data-handling.png`: App Store listing screenshot for data handling.
- `ipad-pro-13-app-store-listing-09-developer.png`: App Store listing screenshot for diagnostics and support export.

## November 5, 2026 refresh

iPhone source: frontend `3bf79a6` plus a DEBUG-only policy-test seam, iPhone 18 Pro Max / iOS 27.0 in light mode, using the current Debug screenshot fixture. `testIPhoneAppStoreScreenshots` passed on November 5; result `/tmp/PumpSyncLightIPhone-20261105.xcresult`. Screenshots use isolated fixture data; they do not demonstrate real HealthKit writes, App Attest, or subscription purchase acceptance. Capture acceptance is separate from the pinned release preflight.

iPad source: frontend commit `e5398db`, iPad Pro 13-inch (M5) / iOS 27.0 in light mode, native `2064 x 2752` capture. `testIPadAppStoreScreenshots` passed with no reported build warnings. The nine light-mode iPhone images replaced the dark listing set on November 5; the required medium-display assets inherit the large Dynamic Island set. The nine iPad images remain in their existing order. The old preview video was permanently deleted from Apple's Asset Library with explicit confirmation.
