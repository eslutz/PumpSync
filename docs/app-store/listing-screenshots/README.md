# App Store Listing Screenshots

Each capture script archives the existing screenshots for its platform before replacing them. Archives are written to `archive/` in this directory with timestamped names.

The iPhone screenshots are captured from the iPhone 17 Pro Max simulator using the screenshot UI-test fixture, then normalized to `1284 x 2778` for App Store Connect. Run:

```sh
scripts/ios/capture-iphone-app-store-screenshots.sh
```

- `iphone-6-7-app-store-listing-01-status-overview.png`: App Store listing screenshot for the Status tab overview.
- `iphone-6-7-app-store-listing-02-sync-workflow.png`: App Store listing screenshot for the Sync tab workflow.
- `iphone-6-7-app-store-listing-03-settings-pumpsync-hosted.png`: App Store listing screenshot for PumpSync Hosted connection settings.
- `iphone-6-7-app-store-listing-04-hosted-subscription-benefits.png`: App Store listing screenshot for the hosted subscription benefits screen.
- `iphone-6-7-app-store-listing-05-settings-self-hosted-connection.png`: App Store listing screenshot for self-hosted connection settings.
- `iphone-6-7-app-store-listing-06-tandem-account.png`: App Store listing screenshot for Tandem account setup.
- `iphone-6-7-app-store-listing-07-apple-health.png`: App Store listing screenshot for Apple Health access.
- `iphone-6-7-app-store-listing-08-data-handling.png`: App Store listing screenshot for data handling.
- `iphone-6-7-app-store-listing-09-developer.png`: App Store listing screenshot for diagnostics and support export.

The iPad screenshots are captured from the iPad Pro 13-inch simulator using the screenshot UI-test fixture. Run:

```sh
scripts/ios/capture-ipad-app-store-screenshots.sh
```

- `ipad-pro-13-app-store-listing-01-status-overview.png`: App Store listing screenshot for the Status split-view overview.
- `ipad-pro-13-app-store-listing-02-sync-workflow.png`: App Store listing screenshot for the Sync workflow.
- `ipad-pro-13-app-store-listing-03-settings-pumpsync-hosted.png`: App Store listing screenshot for PumpSync Hosted connection settings.
- `ipad-pro-13-app-store-listing-04-hosted-subscription-benefits.png`: App Store listing screenshot for the hosted subscription benefits screen.
- `ipad-pro-13-app-store-listing-05-settings-self-hosted-connection.png`: App Store listing screenshot for self-hosted connection settings.
- `ipad-pro-13-app-store-listing-06-tandem-account.png`: App Store listing screenshot for Tandem account setup.
- `ipad-pro-13-app-store-listing-07-apple-health.png`: App Store listing screenshot for Apple Health access.
- `ipad-pro-13-app-store-listing-08-data-handling.png`: App Store listing screenshot for data handling.
- `ipad-pro-13-app-store-listing-09-developer.png`: App Store listing screenshot for diagnostics and support export.
