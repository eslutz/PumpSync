# PumpSync iOS

The iOS app owns Tandem credential storage, sync initiation, and Apple Health writes.

## Sync Behavior

- App open: refreshes when the last successful sync is stale.
- Manual: the user can start sync from the Today or Sync tab.
- Background: schedules a `BGProcessingTaskRequest` at least daily, subject to iOS background execution policy.

## Data Handling

- Tandem credentials are saved in Keychain using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Tandem credentials are sent to the backend only during an active sync request.
- Raw and normalized Tandem payloads are not persisted after HealthKit confirms the write.
- Duplicate prevention uses a rolling HMAC ledger of imported external IDs.
- Tandem credentials are not synced through iCloud in v1; each device must be configured separately.

## Generate Project

```sh
cd client/ios
xcodegen generate
```

## Build Routing

Use these schemes and configurations for hosted subscription builds:

| Purpose | Scheme | Configuration | Backend |
| --- | --- | --- | --- |
| Local Xcode install | `PumpSync` | `Debug` | nonprod sandbox backend |
| TestFlight upload | `PumpSync Beta` | `Beta` archive | nonprod sandbox backend |
| App Store release | `PumpSync` | `Release` archive | prod production backend |

TestFlight and development-signed purchases use Apple's sandbox and do not charge real money. App Store release builds use the production App Store transaction environment.

## Validation

Use raw `xcodebuild` for local validation. The output is intentionally unfiltered:

```sh
xcodebuild test -project PumpSync.xcodeproj -scheme PumpSync -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```
