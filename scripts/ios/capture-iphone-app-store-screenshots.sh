#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro Max}"
RESULT_BUNDLE="${RESULT_BUNDLE:-/tmp/PumpSync-iPhone-App-Store-Screenshots.xcresult}"
ATTACHMENTS_DIR="${ATTACHMENTS_DIR:-/tmp/PumpSync-iPhone-App-Store-Screenshots-Attachments}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/docs/app-store/listing-screenshots}"
TARGET_WIDTH="${TARGET_WIDTH:-1284}"
TARGET_HEIGHT="${TARGET_HEIGHT:-2778}"

SCREENSHOTS=(
  "iphone-6-7-app-store-listing-01-status-overview.png"
  "iphone-6-7-app-store-listing-02-sync-workflow.png"
  "iphone-6-7-app-store-listing-03-settings-pumpsync-hosted.png"
  "iphone-6-7-app-store-listing-04-hosted-subscription-benefits.png"
  "iphone-6-7-app-store-listing-05-settings-self-hosted-connection.png"
  "iphone-6-7-app-store-listing-06-tandem-account.png"
  "iphone-6-7-app-store-listing-07-apple-health.png"
  "iphone-6-7-app-store-listing-08-data-handling.png"
  "iphone-6-7-app-store-listing-09-developer.png"
)

archive_existing_screenshots() {
  local existing=()
  local screenshot

  for screenshot in "${SCREENSHOTS[@]}"; do
    if [[ -f "${OUTPUT_DIR}/${screenshot}" ]]; then
      existing+=("${screenshot}")
    fi
  done

  if (( ${#existing[@]} == 0 )); then
    echo "No existing iPhone App Store screenshots to archive."
    return
  fi

  local archive_dir archive_name
  archive_dir="${OUTPUT_DIR}/archive"
  archive_name="iphone-app-store-screenshots-$(date -u +%Y%m%dT%H%M%SZ).zip"
  mkdir -p "${archive_dir}"

  (
    cd "${OUTPUT_DIR}"
    zip -q "${archive_dir}/${archive_name}" "${existing[@]}"
  )

  echo "Archived ${#existing[@]} existing iPhone App Store screenshots to ${archive_dir}/${archive_name}"
}

rm -rf "${RESULT_BUNDLE}" "${ATTACHMENTS_DIR}"
mkdir -p "${ATTACHMENTS_DIR}" "${OUTPUT_DIR}"
archive_existing_screenshots

xcodebuild test \
  -project "${ROOT_DIR}/client/ios/PumpSync.xcodeproj" \
  -scheme PumpSync \
  -destination "platform=iOS Simulator,name=${DEVICE_NAME},OS=latest" \
  -only-testing:PumpSyncUITests/PumpSyncUITests/testIPhoneAppStoreScreenshots \
  -resultBundlePath "${RESULT_BUNDLE}"

xcrun xcresulttool export attachments \
  --path "${RESULT_BUNDLE}" \
  --output-path "${ATTACHMENTS_DIR}"

normalize_screenshot() {
  local source_file="$1"
  local output_file="$2"
  local cropped_file
  cropped_file="$(mktemp -t pumpsync-iphone-screenshot-crop).png"

  local source_width source_height crop_height
  source_width="$(sips -g pixelWidth "${source_file}" | awk '/pixelWidth/ {print $2}')"
  source_height="$(sips -g pixelHeight "${source_file}" | awk '/pixelHeight/ {print $2}')"

  crop_height="$(
    ruby -e 'puts ((ARGV[0].to_f * ARGV[2].to_f) / ARGV[1].to_f).floor' \
      "${source_width}" "${TARGET_WIDTH}" "${TARGET_HEIGHT}"
  )"

  if (( crop_height > source_height )); then
    crop_height="${source_height}"
  fi

  sips -c "${crop_height}" "${source_width}" "${source_file}" --out "${cropped_file}" >/dev/null
  sips -z "${TARGET_HEIGHT}" "${TARGET_WIDTH}" "${cropped_file}" --out "${output_file}" >/dev/null
  rm -f "${cropped_file}"

  local final_width final_height
  final_width="$(sips -g pixelWidth "${output_file}" | awk '/pixelWidth/ {print $2}')"
  final_height="$(sips -g pixelHeight "${output_file}" | awk '/pixelHeight/ {print $2}')"

  if [[ "${final_width}" != "${TARGET_WIDTH}" || "${final_height}" != "${TARGET_HEIGHT}" ]]; then
    echo "Wrong output dimensions for ${output_file}: ${final_width}x${final_height}" >&2
    exit 1
  fi
}

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

  normalize_screenshot "${ATTACHMENTS_DIR}/${source_path}" "${OUTPUT_DIR}/${screenshot}"
  sips -g pixelWidth -g pixelHeight "${OUTPUT_DIR}/${screenshot}"
done

echo "iPhone App Store screenshots exported to ${OUTPUT_DIR}"
