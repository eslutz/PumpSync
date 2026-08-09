#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DIR="${SOURCE_DIR:-/tmp/pumpsync-app-preview}"
OUTPUT_FILE="${OUTPUT_FILE:-${ROOT_DIR}/docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4}"
WORK_DIR="$(mktemp -d /tmp/pumpsync-app-preview-build.XXXXXX)"
CAPTION_RENDERER="${ROOT_DIR}/scripts/ios/render-app-preview-caption.swift"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

for command_name in ffmpeg ffprobe swift; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Missing required command: ${command_name}" >&2
    exit 1
  }
done

SCENES=(status sync subscription self-hosted privacy close)
DURATIONS=(4 7 6 6 5 2)
CAPTIONS=(
  "Keep your pump data in view."
  "Sync insulin and carbohydrates to Apple Health."
  "Subscribe to PumpSync—no server to manage."
  "Or connect to your own self-hosted backend."
  "Your Health data stays under your control."
  "PumpSync."
)

for scene in "${SCENES[@]}"; do
  input_file="${SOURCE_DIR}/${scene}.mov"
  if [[ ! -s "${input_file}" ]]; then
    echo "Missing or empty source clip: ${input_file}" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "${OUTPUT_FILE}")"

for index in "${!SCENES[@]}"; do
  scene="${SCENES[$index]}"
  duration="${DURATIONS[$index]}"
  caption_file="${WORK_DIR}/${scene}-caption.png"
  segment_file="${WORK_DIR}/${scene}.mp4"

  swift "${CAPTION_RENDERER}" "${CAPTIONS[$index]}" "${caption_file}"

  ffmpeg -hide_banner -loglevel error -y \
    -i "${SOURCE_DIR}/${scene}.mov" \
    -loop 1 -i "${caption_file}" \
    -filter_complex \
      "[0:v]reverse,trim=duration=${duration},reverse,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=${duration},trim=duration=${duration},scale=886:1920:force_original_aspect_ratio=increase,crop=886:1920,fps=30,format=yuv420p[base];[1:v]format=rgba[caption];[base][caption]overlay=0:0:shortest=1,fade=t=in:st=0:d=0.18,fade=t=out:st=$(awk -v d="${duration}" 'BEGIN { printf "%.2f", d - 0.18 }'):d=0.18[out]" \
    -map "[out]" -t "${duration}" -an \
    -c:v libx264 -profile:v high -level:v 4.0 -preset medium -crf 15 -pix_fmt yuv420p \
    "${segment_file}"

  printf "file '%s'\n" "${segment_file}" >>"${WORK_DIR}/segments.txt"
done

ffmpeg -hide_banner -loglevel error -y \
  -f concat -safe 0 -i "${WORK_DIR}/segments.txt" \
  -an -c:v libx264 -profile:v high -level:v 4.0 -preset slow \
  -b:v 11M -minrate 11M -maxrate 11M -bufsize 22M \
  -x264-params "nal-hrd=cbr:force-cfr=1:filler=1" -r 30 -pix_fmt yuv420p \
  -movflags +faststart "${OUTPUT_FILE}"

metadata="$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,profile,width,height,r_frame_rate,pix_fmt \
  -show_entries format=duration,size,bit_rate -of default=nw=1 "${OUTPUT_FILE}")"

value_for() {
  awk -F= -v key="$1" '$1 == key { print $2; exit }' <<<"${metadata}"
}

[[ "$(value_for codec_name)" == "h264" ]] || { echo "Output codec is not H.264" >&2; exit 1; }
[[ "$(value_for profile)" == "High" ]] || { echo "Output profile is not High" >&2; exit 1; }
[[ "$(value_for width)" == "886" && "$(value_for height)" == "1920" ]] || {
  echo "Output resolution is not 886x1920" >&2
  exit 1
}
[[ "$(value_for r_frame_rate)" == "30/1" ]] || { echo "Output frame rate is not 30 fps" >&2; exit 1; }
[[ "$(value_for pix_fmt)" == "yuv420p" ]] || { echo "Output pixel format is not yuv420p" >&2; exit 1; }

duration="$(value_for duration)"
awk -v duration="${duration}" 'BEGIN { exit !(duration >= 25 && duration <= 30.01) }' || {
  echo "Output duration ${duration}s is outside 25–30 seconds" >&2
  exit 1
}

size="$(value_for size)"
(( size < 500000000 )) || { echo "Output exceeds 500 MB" >&2; exit 1; }

bit_rate="$(value_for bit_rate)"
(( bit_rate >= 10000000 && bit_rate <= 12000000 )) || {
  echo "Output bitrate ${bit_rate} is outside 10–12 Mbps" >&2
  exit 1
}

audio_streams="$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "${OUTPUT_FILE}" | wc -l | tr -d ' ')"
[[ "${audio_streams}" == "0" ]] || { echo "Output unexpectedly contains audio" >&2; exit 1; }

echo "Created ${OUTPUT_FILE}"
echo "Verified: H.264 High, 886x1920, 30 fps, ${duration}s, no audio, ${size} bytes"
