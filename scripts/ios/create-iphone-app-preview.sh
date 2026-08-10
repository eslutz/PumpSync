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

SCENES=(status sync-active subscription self-hosted privacy close)
for scene in "${SCENES[@]}"; do
  input_file="${SOURCE_DIR}/${scene}.mov"
  [[ -s "${input_file}" ]] || {
    echo "Missing or empty source clip: ${input_file}" >&2
    exit 1
  }
done

mkdir -p "$(dirname "${OUTPUT_FILE}")"

render_overlay() {
  local style="$1" text="$2" output="$3" x="$4" y="$5" width="$6" height="$7" font_size="$8"
  swift "${CAPTION_RENDERER}" "${style}" "${text}" "${output}" \
    "${x}" "${y}" "${width}" "${height}" "${font_size}"
}

render_blur_mask() {
  local output="$1" x="$2" y="$3" width="$4" height="$5"
  render_overlay blur "" "${output}" "${x}" "${y}" "${width}" "${height}" 1
}

encode_segment() {
  local input_file="$1" duration="$2" overlay_file="$3" mask_file="$4" x="$5" y="$6" width="$7" height="$8" fade_start="$9" output_file="${10}"
  local fade_end video_y
  fade_end="$(awk -v d="${duration}" 'BEGIN { printf "%.2f", d - 0.35 }')"
  video_y="$((1920 - y - height))"

  ffmpeg -hide_banner -loglevel error -y \
    -i "${input_file}" -loop 1 -i "${overlay_file}" -loop 1 -i "${mask_file}" \
    -filter_complex \
      "[0:v]reverse,trim=duration=${duration},reverse,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=${duration},trim=duration=${duration},scale=886:1920:force_original_aspect_ratio=increase,crop=886:1920,fps=30,format=yuv420p[base];[base]split=2[clean][blur-source];[blur-source]crop=${width}:${height}:${x}:${video_y},boxblur=4:1,format=rgb24,geq=r='r(X,Y)*0.15+255*0.85':g='g(X,Y)*0.15+255*0.85':b='b(X,Y)*0.15+255*0.85'[blur];[2:v]crop=${width}:${height}:${x}:${video_y},format=gray[mask];[blur][mask]alphamerge[masked-blur];[clean][masked-blur]overlay=${x}:${video_y}:format=auto[blurred-base];[1:v]format=rgba,fade=t=in:st=${fade_start}:d=0.3:alpha=1,fade=t=out:st=${fade_end}:d=0.35:alpha=1[caption];[blurred-base][caption]overlay=x=0:y='if(lt(t,${fade_start}+0.3),12*(1-(t-${fade_start})/0.3),0)':shortest=1[out]" \
    -map "[out]" -t "${duration}" -an \
    -c:v libx264 -profile:v high -level:v 4.0 -preset medium -crf 15 -pix_fmt yuv420p \
    "${output_file}"
}

render_overlay callout \
  "Sync insulin and carbohydrates from your pump to Apple Health." \
  "${WORK_DIR}/status-caption.png" 45 1470 796 260 72
render_blur_mask "${WORK_DIR}/status-blur.png" 45 1470 796 260
ffmpeg -hide_banner -loglevel error -y \
  -i "${SOURCE_DIR}/status.mov" \
  -i "${SOURCE_DIR}/sync-active.mov" \
  -loop 1 -i "${WORK_DIR}/status-caption.png" -loop 1 -i "${WORK_DIR}/status-blur.png" \
  -filter_complex \
    "[0:v]reverse,trim=duration=2,reverse,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=2,trim=duration=2,scale=886:1920:force_original_aspect_ratio=increase,crop=886:1920,fps=30,format=yuv420p[ready];[1:v]trim=duration=6,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=6,trim=duration=6,scale=886:1920:force_original_aspect_ratio=increase,crop=886:1920,fps=30,format=yuv420p[active];[ready][active]concat=n=2:v=1:a=0[base];[base]split=2[clean][blur-source];[blur-source]crop=796:260:45:190,boxblur=4:1,format=rgb24,geq=r='r(X,Y)*0.15+255*0.85':g='g(X,Y)*0.15+255*0.85':b='b(X,Y)*0.15+255*0.85'[blur];[3:v]crop=796:260:45:190,format=gray[mask];[blur][mask]alphamerge[masked-blur];[clean][masked-blur]overlay=45:190:format=auto[blurred-base];[2:v]format=rgba,fade=t=in:st=0.4:d=0.3:alpha=1,fade=t=out:st=7.65:d=0.35:alpha=1[caption];[blurred-base][caption]overlay=x=0:y='if(lt(t,0.7),12*(1-(t-0.4)/0.3),0)':shortest=1[out]" \
  -map "[out]" -t 8 -an \
  -c:v libx264 -profile:v high -level:v 4.0 -preset medium -crf 15 -pix_fmt yuv420p \
  "${WORK_DIR}/01-status.mp4"

render_overlay callout "PumpSync runs the backend." \
  "${WORK_DIR}/subscription-managed.png" 43 1280 800 180 72
render_overlay callout "No server to manage" \
  "${WORK_DIR}/subscription-server.png" 43 620 800 120 72
render_blur_mask "${WORK_DIR}/subscription-managed-blur.png" 43 1280 800 180
render_blur_mask "${WORK_DIR}/subscription-server-blur.png" 43 620 800 120
ffmpeg -hide_banner -loglevel error -y \
  -i "${SOURCE_DIR}/subscription.mov" \
  -loop 1 -i "${WORK_DIR}/subscription-managed.png" \
  -loop 1 -i "${WORK_DIR}/subscription-server.png" \
  -loop 1 -i "${WORK_DIR}/subscription-managed-blur.png" \
  -loop 1 -i "${WORK_DIR}/subscription-server-blur.png" \
  -filter_complex \
    "[0:v]reverse,trim=duration=6,reverse,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=6,trim=duration=6,scale=886:1920:force_original_aspect_ratio=increase,crop=886:1920,fps=30,format=yuv420p[base];[base]split=2[clean][managed-source];[managed-source]crop=800:180:43:460,boxblur=4:1,format=rgb24,geq=r='r(X,Y)*0.15+255*0.85':g='g(X,Y)*0.15+255*0.85':b='b(X,Y)*0.15+255*0.85'[managed-blur];[3:v]crop=800:180:43:460,format=gray[managed-mask];[managed-blur][managed-mask]alphamerge[masked-managed];[clean][masked-managed]overlay=43:460:format=auto[managed-base];[managed-base]split=2[clean-two][server-source];[server-source]crop=800:120:43:1180,boxblur=4:1,format=rgb24,geq=r='r(X,Y)*0.15+255*0.85':g='g(X,Y)*0.15+255*0.85':b='b(X,Y)*0.15+255*0.85'[server-blur];[4:v]crop=800:120:43:1180,format=gray[server-mask];[server-blur][server-mask]alphamerge[masked-server];[clean-two][masked-server]overlay=43:1180:format=auto[blurred-base];[1:v]format=rgba,fade=t=in:st=0.3:d=0.3:alpha=1,fade=t=out:st=2.65:d=0.3:alpha=1[managed];[2:v]format=rgba,fade=t=in:st=3.1:d=0.3:alpha=1,fade=t=out:st=5.65:d=0.35:alpha=1[server];[blurred-base][managed]overlay=x=0:y='if(lt(t,0.6),12*(1-(t-0.3)/0.3),0)':shortest=1[first];[first][server]overlay=x=0:y='if(lt(t,3.4),12*(1-(t-3.1)/0.3),0)':shortest=1[out]" \
  -map "[out]" -t 6 -an \
  -c:v libx264 -profile:v high -level:v 4.0 -preset medium -crf 15 -pix_fmt yuv420p \
  "${WORK_DIR}/02-subscription.mp4"

render_overlay callout \
  "Connect to your own backend that you host and manage." \
  "${WORK_DIR}/self-hosted-caption.png" 43 660 800 370 72
render_blur_mask "${WORK_DIR}/self-hosted-blur.png" 43 660 800 370
encode_segment "${SOURCE_DIR}/self-hosted.mov" 6 "${WORK_DIR}/self-hosted-caption.png" "${WORK_DIR}/self-hosted-blur.png" 43 660 800 370 0.3 "${WORK_DIR}/03-self-hosted.mp4"

render_overlay callout \
  "Your Health data stays under your control." \
  "${WORK_DIR}/privacy-caption.png" 43 1250 800 220 72
render_blur_mask "${WORK_DIR}/privacy-blur.png" 43 1250 800 220
encode_segment "${SOURCE_DIR}/privacy.mov" 6 "${WORK_DIR}/privacy-caption.png" "${WORK_DIR}/privacy-blur.png" 43 1250 800 220 0.3 "${WORK_DIR}/04-privacy.mp4"

render_overlay closing "PumpSync" \
  "${WORK_DIR}/closing-title.png" 43 1450 800 170 96
render_overlay closing "Your pump data. Your choice." \
  "${WORK_DIR}/closing-tagline.png" 43 1190 800 200 72
render_blur_mask "${WORK_DIR}/closing-blur.png" 43 1180 800 460
ffmpeg -hide_banner -loglevel error -y \
  -i "${SOURCE_DIR}/close.mov" \
  -loop 1 -i "${WORK_DIR}/closing-title.png" \
  -loop 1 -i "${WORK_DIR}/closing-tagline.png" \
  -loop 1 -i "${WORK_DIR}/closing-blur.png" \
  -filter_complex \
    "[0:v]reverse,trim=duration=4,reverse,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=4,trim=duration=4,scale=886:1920:force_original_aspect_ratio=increase,crop=886:1920,fps=30,format=yuv420p[base];[base]split=2[clean][blur-source];[blur-source]crop=800:460:43:280,boxblur=4:1,format=rgb24,geq=r='r(X,Y)*0.15+255*0.85':g='g(X,Y)*0.15+255*0.85':b='b(X,Y)*0.15+255*0.85'[blur];[3:v]crop=800:460:43:280,format=gray[mask];[blur][mask]alphamerge[masked-blur];[clean][masked-blur]overlay=43:280:format=auto[blurred-base];[1:v]format=rgba,fade=t=in:st=0.45:d=0.9:alpha=1[title];[2:v]format=rgba,fade=t=in:st=1.35:d=0.9:alpha=1[tagline];[blurred-base][title]overlay=shortest=1[titled];[titled][tagline]overlay=shortest=1[out]" \
  -map "[out]" -t 4 -an \
  -c:v libx264 -profile:v high -level:v 4.0 -preset medium -crf 15 -pix_fmt yuv420p \
  "${WORK_DIR}/05-close.mp4"

for segment in \
  "${WORK_DIR}/01-status.mp4" \
  "${WORK_DIR}/02-subscription.mp4" \
  "${WORK_DIR}/03-self-hosted.mp4" \
  "${WORK_DIR}/04-privacy.mp4" \
  "${WORK_DIR}/05-close.mp4"; do
  printf "file '%s'\n" "${segment}" >>"${WORK_DIR}/segments.txt"
done

ffmpeg -hide_banner -loglevel error -y \
  -i "${WORK_DIR}/01-status.mp4" -i "${WORK_DIR}/02-subscription.mp4" -i "${WORK_DIR}/03-self-hosted.mp4" -i "${WORK_DIR}/04-privacy.mp4" -i "${WORK_DIR}/05-close.mp4" \
  -filter_complex "[0:v][1:v]xfade=transition=fade:duration=0.35:offset=7.65[v01];[v01][2:v]xfade=transition=fade:duration=0.35:offset=13.30[v02];[v02][3:v]xfade=transition=fade:duration=0.35:offset=18.95[v03];[v03][4:v]xfade=transition=fade:duration=0.35:offset=24.60[out]" \
  -map "[out]" \
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
