#!/usr/bin/env bash
set -euo pipefail

preview_file="${1:?Usage: verify-app-preview-media.sh <preview.mp4>}"
[[ -s "${preview_file}" ]] || { echo "Missing or empty App Preview: ${preview_file}" >&2; exit 1; }

video_metadata="$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,profile,width,height,r_frame_rate,pix_fmt \
  -show_entries format=duration,size,bit_rate -of default=nw=1 "${preview_file}")"

value_for() {
  awk -F= -v key="$1" '$1 == key { print $2; exit }' <<<"$2"
}

[[ "$(value_for codec_name "${video_metadata}")" == "h264" ]] || { echo "Output codec is not H.264" >&2; exit 1; }
[[ "$(value_for profile "${video_metadata}")" == "High" ]] || { echo "Output profile is not High" >&2; exit 1; }
[[ "$(value_for width "${video_metadata}")" == "886" && "$(value_for height "${video_metadata}")" == "1920" ]] || {
  echo "Output resolution is not 886x1920" >&2
  exit 1
}
[[ "$(value_for r_frame_rate "${video_metadata}")" == "30/1" ]] || { echo "Output frame rate is not 30 fps" >&2; exit 1; }
[[ "$(value_for pix_fmt "${video_metadata}")" == "yuv420p" ]] || { echo "Output pixel format is not yuv420p" >&2; exit 1; }

duration="$(value_for duration "${video_metadata}")"
awk -v duration="${duration}" 'BEGIN { exit !(duration >= 25 && duration <= 30.01) }' || {
  echo "Output duration ${duration}s is outside 25-30 seconds" >&2
  exit 1
}

size="$(value_for size "${video_metadata}")"
(( size < 500000000 )) || { echo "Output exceeds 500 MB" >&2; exit 1; }

bit_rate="$(value_for bit_rate "${video_metadata}")"
(( bit_rate >= 10000000 && bit_rate <= 12000000 )) || {
  echo "Output bitrate ${bit_rate} is outside 10-12 Mbps" >&2
  exit 1
}

audio_streams="$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "${preview_file}" | wc -l | tr -d ' ')"
[[ "${audio_streams}" == "1" ]] || {
  echo "Output must contain exactly one enabled stereo AAC audio stream; found ${audio_streams}" >&2
  exit 1
}

audio_metadata="$(ffprobe -v error -select_streams a:0 \
  -show_entries stream=codec_name,profile,sample_rate,channels,channel_layout,bit_rate:stream_disposition=default \
  -of default=nw=1 "${preview_file}")"
[[ "$(value_for codec_name "${audio_metadata}")" == "aac" ]] || { echo "Audio codec is not AAC" >&2; exit 1; }
[[ "$(value_for profile "${audio_metadata}")" == "LC" ]] || { echo "Audio profile is not AAC-LC" >&2; exit 1; }
sample_rate="$(value_for sample_rate "${audio_metadata}")"
[[ "${sample_rate}" == "44100" || "${sample_rate}" == "48000" ]] || { echo "Audio sample rate must be 44.1 or 48 kHz" >&2; exit 1; }
[[ "$(value_for channels "${audio_metadata}")" == "2" ]] || { echo "Audio must contain two channels" >&2; exit 1; }
[[ "$(value_for channel_layout "${audio_metadata}")" == "stereo" ]] || { echo "Audio channel layout is not stereo" >&2; exit 1; }
[[ "$(value_for DISPOSITION:default "${audio_metadata}")" == "1" ]] || { echo "Audio stream is not enabled by default" >&2; exit 1; }
audio_bit_rate="$(value_for bit_rate "${audio_metadata}")"
(( audio_bit_rate >= 220000 && audio_bit_rate <= 280000 )) || {
  echo "Audio bitrate ${audio_bit_rate} is not near the required 256 kbps" >&2
  exit 1
}

echo "Verified: H.264 High, 886x1920, 30 fps, ${duration}s, AAC-LC stereo ${sample_rate} Hz at ${audio_bit_rate} bps, ${size} bytes"
