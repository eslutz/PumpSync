#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEVICE_NAME="${DEVICE_NAME:-iPad Pro 13-inch (M5)}"
RESULT_BUNDLE="${RESULT_BUNDLE:-/tmp/PumpSync-iPad-App-Store-Screenshots.xcresult}"
ATTACHMENTS_DIR="${ATTACHMENTS_DIR:-/tmp/PumpSync-iPad-App-Store-Screenshots-Attachments}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/docs/app-store/listing-screenshots}"

SCREENSHOTS=(
  "ipad-pro-13-app-store-listing-01-status-overview.png"
  "ipad-pro-13-app-store-listing-02-sync-workflow.png"
  "ipad-pro-13-app-store-listing-03-settings-pumpsync-hosted.png"
  "ipad-pro-13-app-store-listing-04-settings-self-hosted-connection.png"
  "ipad-pro-13-app-store-listing-05-hosted-subscription-benefits.png"
  "ipad-pro-13-ipad-specific-01-health-detail-sidebar.png"
  "ipad-pro-13-ipad-specific-02-data-handling-detail-sidebar.png"
  "ipad-pro-13-ipad-specific-03-developer-detail-sidebar.png"
)

rm -rf "${RESULT_BUNDLE}" "${ATTACHMENTS_DIR}"
mkdir -p "${ATTACHMENTS_DIR}" "${OUTPUT_DIR}"

xcodebuild test \
  -project "${ROOT_DIR}/client/ios/PumpSync.xcodeproj" \
  -scheme PumpSync \
  -destination "platform=iOS Simulator,name=${DEVICE_NAME}" \
  -only-testing:PumpSyncUITests/PumpSyncUITests/testIPadAppStoreScreenshots \
  -only-testing:PumpSyncUITests/PumpSyncUITests/testIPadSpecificScreenshots \
  -resultBundlePath "${RESULT_BUNDLE}"

xcrun xcresulttool export attachments \
  --path "${RESULT_BUNDLE}" \
  --output-path "${ATTACHMENTS_DIR}"

for screenshot in "${SCREENSHOTS[@]}"; do
  source_path="$(
    ruby -rjson -e '
      manifest = JSON.parse(File.read(ARGV[0]))
      expected = ARGV[1]
      stem = expected.sub(/\.png\z/, "")
      attachment = manifest.flat_map { |test| test.fetch("attachments", []) }.find do |entry|
        suggested = entry.fetch("suggestedHumanReadableName", "")
        suggested == expected || suggested.start_with?("#{stem}_")
      end
      puts attachment.fetch("exportedFileName", "") if attachment
    ' "${ATTACHMENTS_DIR}/manifest.json" "${screenshot}"
  )"

  if [[ -z "${source_path}" ]]; then
    echo "Missing exported attachment for ${screenshot}" >&2
    exit 1
  fi

  cp "${ATTACHMENTS_DIR}/${source_path}" "${OUTPUT_DIR}/${screenshot}"
  sips -g pixelWidth -g pixelHeight "${OUTPUT_DIR}/${screenshot}"
done

echo "iPad App Store screenshots exported to ${OUTPUT_DIR}"
