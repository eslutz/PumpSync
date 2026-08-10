# PumpSync App Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce, validate, and upload one 25–30 second portrait iPhone App Preview that demonstrates PumpSync's status, sync, subscription, self-hosted, and privacy flows.

**Architecture:** Capture short genuine UI segments from the deterministic iPhone simulator fixture, then assemble them with a focused FFmpeg script that owns timing, captions, format normalization, and poster-frame selection. Store only the final App Store asset and its reproducible assembly script in the repository; keep intermediate simulator recordings in `/tmp`.

**Tech Stack:** XcodeBuildMCP, iOS Simulator, `xcrun simctl io recordVideo`, Bash, FFmpeg/FFprobe, App Store Connect.

## Global Constraints

- Create only one iPhone portrait preview; do not create an iPad preview.
- Use genuine app UI and deterministic demo data; expose no personal information, credentials, or production tokens.
- Use “PumpSync subscription,” “PumpSync,” “Self-hosted,” and “PumpSync-hosted backend” according to the approved terminology.
- Deliver H.264 at exactly 886 × 1920, progressive scan, no more than 30 fps, 10–12 Mbps target video bitrate, and 25–30 seconds duration.
- Deliver no audio track.
- Keep the output below 500 MB and upload it to the English (U.S.) iPhone App Preview slot for version 1.0.
- Do not submit the app for review or complete a subscription purchase.

---

## File Map

- Create `scripts/ios/create-iphone-app-preview.sh`: validate six named raw clips, trim and normalize each scene, add captions, join scenes, encode the Apple-compliant final asset, and verify its media contract.
- Create `docs/app-store/app-previews/README.md`: document capture order, source clip names, creation command, output properties, and upload destination.
- Create `docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4`: final upload-ready App Preview.
- Modify `docs/superpowers/plans/2026-08-09-app-preview.md`: mark completed tasks as execution progresses.

### Task 1: Capture the six simulator scenes

**Files:**
- Create temporarily: `/tmp/pumpsync-app-preview/status.mov`
- Create temporarily: `/tmp/pumpsync-app-preview/sync.mov`
- Create temporarily: `/tmp/pumpsync-app-preview/subscription.mov`
- Create temporarily: `/tmp/pumpsync-app-preview/self-hosted.mov`
- Create temporarily: `/tmp/pumpsync-app-preview/privacy.mov`
- Create temporarily: `/tmp/pumpsync-app-preview/close.mov`

**Interfaces:**
- Consumes: `PumpSync.xcodeproj`, scheme `PumpSync`, the booted iPhone 17 simulator, and deterministic UI-test/demo state.
- Produces: six portrait QuickTime recordings with the exact basenames consumed by Task 2.

- [ ] **Step 1: Build and launch the app on the booted iPhone simulator**

Use XcodeBuildMCP session defaults with project `PumpSync.xcodeproj`, scheme `PumpSync`, configuration `Debug`, and the booted iPhone simulator, then run `build_run_sim`. Confirm the status overview is visible with `snapshot_ui` and `screenshot`.

- [ ] **Step 2: Prepare a clean raw-capture directory**

Run:

```bash
mkdir -p /tmp/pumpsync-app-preview
find /tmp/pumpsync-app-preview -maxdepth 1 -type f -name '*.mov' -delete
```

Expected: `/tmp/pumpsync-app-preview` exists and contains no stale `.mov` files.

- [ ] **Step 3: Record the status and sync scenes**

Record `status.mov` for at least 5 seconds while showing the status overview. Record `sync.mov` for at least 9 seconds while tapping Sync, showing the configured date range, and initiating or demonstrating the deterministic sync flow. Stop each `simctl io <UDID> recordVideo` process cleanly with `SIGINT`.

- [ ] **Step 4: Record the subscription and self-hosted scenes**

Record `subscription.mov` for at least 8 seconds while opening Settings, confirming PumpSync is selected, and presenting the subscription sheet. Confirm the sheet contains “PumpSync Subscription” and does not contain “PumpSync Hosted Service.” Then record `self-hosted.mov` for at least 8 seconds while closing the sheet, selecting Self-hosted, and showing its connection fields.

- [ ] **Step 5: Record the privacy and closing scenes**

Record `privacy.mov` for at least 7 seconds while opening Data Handling and revealing the privacy summary. Record `close.mov` for at least 4 seconds after returning to the status overview.

- [x] **Step 6: Verify all raw clips**

Run:

```bash
for clip in status sync subscription self-hosted privacy close; do
  test -s "/tmp/pumpsync-app-preview/${clip}.mov"
  ffprobe -v error -show_entries stream=codec_type,width,height -show_entries format=duration -of json "/tmp/pumpsync-app-preview/${clip}.mov"
done
```

Expected: six non-empty portrait video clips. Static status and closing clips may contain only a few encoded frames because `simctl` records display changes; Task 2 extends their final genuine frames to the planned duration.

### Task 2: Build the reproducible preview assembly pipeline

**Files:**
- Create: `scripts/ios/create-iphone-app-preview.sh`
- Create: `docs/app-store/app-previews/README.md`

**Interfaces:**
- Consumes: the six `.mov` files from Task 1 and macOS FFmpeg/FFprobe.
- Produces: `docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4` and a nonzero exit status for any invalid source or output.

- [ ] **Step 1: Write the assembly script with strict input validation**

The script must use `set -euo pipefail`, accept `SOURCE_DIR` and `OUTPUT_FILE` overrides, require `ffmpeg` and `ffprobe`, and verify these exact files exist and are non-empty: `status.mov`, `sync.mov`, `subscription.mov`, `self-hosted.mov`, `privacy.mov`, and `close.mov`.

- [ ] **Step 2: Encode the approved storyboard**

Use one FFmpeg filter graph to trim scenes to 4, 7, 6, 6, 5, and 2 seconds respectively; reset timestamps; scale/crop to 886 × 1920; normalize to 30 fps and `yuv420p`; overlay the exact captions from the approved design; apply short video-only fades; concatenate to exactly 30 seconds; and encode with `libx264`, High profile, Level 4.0, 11 Mbps target bitrate, 12 Mbps maximum rate, 24 Mbps buffer, fast-start metadata, and no audio.

- [ ] **Step 3: Add hard output assertions**

Use FFprobe to assert: H.264 video; 886 × 1920; 30 fps or lower; duration from 25.0 through 30.0 seconds inclusive; no audio stream; and file size below 500,000,000 bytes. Print a concise success summary only after every assertion passes.

- [ ] **Step 4: Document capture and regeneration**

In `docs/app-store/app-previews/README.md`, list the six raw filenames in storyboard order, the `scripts/ios/create-iphone-app-preview.sh` invocation, the exact output path, the Apple media contract, and the English (U.S.) iPhone version 1.0 upload target.

- [ ] **Step 5: Validate shell syntax before rendering**

Run:

```bash
bash -n scripts/ios/create-iphone-app-preview.sh
```

Expected: exit code 0 and no output.

### Task 3: Render and visually review the final asset

**Files:**
- Create: `docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4`

**Interfaces:**
- Consumes: Task 1 raw clips and Task 2 assembly script.
- Produces: one validated upload-ready MP4.

- [ ] **Step 1: Render the preview**

Run:

```bash
scripts/ios/create-iphone-app-preview.sh
```

Expected: the output file is created and the script reports every media assertion passed.

- [ ] **Step 2: Inspect authoritative media metadata**

Run:

```bash
ffprobe -v error -show_entries stream=index,codec_name,profile,width,height,r_frame_rate,pix_fmt -show_entries format=duration,size,bit_rate -of json docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4
```

Expected: one H.264 High-profile 886 × 1920 video stream at no more than 30 fps, no audio stream, duration 25–30 seconds, bitrate near 11 Mbps, and size below 500 MB.

- [ ] **Step 3: Generate and inspect representative frames**

Run:

```bash
mkdir -p /tmp/pumpsync-app-preview/review
ffmpeg -y -i docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4 -vf "select='eq(n,90)+eq(n,240)+eq(n,420)+eq(n,600)+eq(n,780)'" -vsync 0 /tmp/pumpsync-app-preview/review/frame-%02d.png
```

Inspect every frame for correct UI, caption text, legibility, safe placement, privacy, and absence of old subscription wording.

- [ ] **Step 4: Watch the entire exported preview**

Play the MP4 from beginning to end. Confirm pacing, cuts, fades, UI continuity, caption duration, the intended silent experience, and a useful frame at 5 seconds for the default poster frame.

- [ ] **Step 5: Run repository checks and commit**

Run:

```bash
git diff --check
rg -n -i 'PumpSync Hosted|hosted subscription|hostedSubscription|HOSTED_SUBSCRIPTION|dev\.ericslutz\.PumpSync\.hosted\.monthly' scripts/ios/create-iphone-app-preview.sh docs/app-store/app-previews
git add scripts/ios/create-iphone-app-preview.sh docs/app-store/app-previews docs/superpowers/plans/2026-08-09-app-preview.md
git commit -m "assets: add PumpSync App Store preview"
```

Expected: the terminology search returns no matches, checks pass, and the signed commit is created directly on `main`.

### Task 4: Revise the caption system and regenerate the preview

**Files:**
- Modify: `scripts/ios/render-app-preview-caption.swift`
- Modify: `scripts/ios/create-iphone-app-preview.sh`
- Modify: `docs/app-store/app-previews/README.md`
- Modify: `docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4`

**Interfaces:**
- Consumes: the existing validated `status.mov`, `subscription.mov`, `self-hosted.mov`, `privacy.mov`, and `close.mov` fixture captures in `/tmp/pumpsync-app-preview`.
- Produces: a 30-second preview with five scenes, contextual light callouts, and an unboxed two-stage closing title.

- [ ] **Step 1: Add a failing renderer contract check**

Render representative callout and closing-title overlays into `/tmp/pumpsync-app-preview/review`. Assert that each output is exactly 886 × 1920 with alpha, then composite it over the relevant source frame and inspect placement. The current renderer should fail because it exposes only one fixed dark lower-third layout.

- [ ] **Step 2: Generalize the caption renderer**

Change `render-app-preview-caption.swift` to accept a style (`callout` or `closing`), text, output path, and explicit panel rectangle. The `callout` style must render dark `#1D1D1F` text on a white panel at approximately 94% opacity with a restrained corner radius and shadow. The `closing` style must render centered dark text without a panel so FFmpeg can place it over a white veil.

- [ ] **Step 3: Encode the revised five-scene storyboard**

Update `create-iphone-app-preview.sh` to use these exact scene durations and copy:

```text
0–8s   status         Sync insulin and carbohydrates from your pump to Apple Health.
8–11s  subscription   Managed by PumpSync
11–14s subscription   No server to manage
14–20s self-hosted    Prefer your own server? Connect a self-hosted backend.
20–26s privacy        Your Health data stays under your control.
26–30s close          PumpSync / Your pump data. Your choice.
```

The first two duplicate status segments must become one continuous eight-second scene. Every contextual callout must fade and move slightly upward over 0.3 seconds. The closing scene must apply a subtle white veil, fade in “PumpSync,” and fade in “Your pump data. Your choice.” 0.4 seconds later with no panel.

- [ ] **Step 4: Verify overlay placement before the final encode**

Export frames at 2, 9, 12, 16, 22, 27, and 29 seconds. Confirm the opening caption sits below Last Sync, subscription callouts do not overlap Subscribe, the self-hosted callout avoids the form, the privacy callout does not obscure privacy details, and the closing title is centered and legible.

- [ ] **Step 5: Regenerate and validate the MP4**

Run:

```bash
bash -n scripts/ios/create-iphone-app-preview.sh
scripts/ios/create-iphone-app-preview.sh
ffprobe -v error -show_entries stream=index,codec_name,profile,width,height,r_frame_rate,pix_fmt -show_entries format=duration,size,bit_rate -of json docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4
```

Expected: H.264 High profile, 886 × 1920, 30 fps, exactly 30 seconds, 10–12 Mbps, no audio, and less than 500 MB.

- [ ] **Step 6: Update documentation and commit**

Update `docs/app-store/app-previews/README.md` with the five-scene order and contextual overlay behavior. Run `git diff --check` and the prohibited-terminology search, then commit directly to `main`:

```bash
git add scripts/ios/render-app-preview-caption.swift scripts/ios/create-iphone-app-preview.sh docs/app-store/app-previews docs/superpowers/plans/2026-08-09-app-preview.md
git commit -m "assets: refine App Preview captions"
```

### Task 5: Upload and verify in App Store Connect

**Files:**
- Read: `docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4`

**Interfaces:**
- Consumes: Task 3’s validated MP4 and the existing App Store Connect version 1.0 page.
- Produces: one processed English (U.S.) iPhone App Preview in the first media position with a verified poster frame.

- [ ] **Step 1: Reconfirm the target before upload**

In App Store Connect, open PumpSync version 1.0, English (U.S.), iPhone media. Confirm the existing eight screenshots are still present and correctly ordered, and that no App Preview is already occupying the target slot.

- [ ] **Step 2: Upload the final MP4**

Upload `docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4` to the iPhone App Preview area. Do not modify the iPad media set and do not submit the version for review.

- [ ] **Step 3: Wait for processing and inspect the result**

Wait until App Store Connect finishes processing. Confirm there is no video, resolution, codec, duration, or localization error and that the preview appears before the screenshot sequence.

- [ ] **Step 4: Set and verify the poster frame**

Choose the clear status/sync frame near 5 seconds as the poster frame. Confirm the selected frame is readable, visually clean, and contains no transition or caption overlap.

### Task 6: Stage the closing frosted surface

**Files:**
- Modify: `scripts/ios/create-iphone-app-preview.sh`
- Modify: `docs/superpowers/specs/2026-08-09-app-preview-design.md`
- Modify: `docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4`

**Interfaces:**
- Consumes: the existing closing title/tagline overlays and `close.mov` fixture.
- Produces: a closing scene whose upper material appears with “PumpSync” and whose complementary lower extension fades with the tagline into one continuous rounded surface.

- [x] **Step 1: Split the closing material into overlapping masks**

Render an upper full-width rounded mask at `x=115, y=1360, width=656, height=270` and a lower full-width rounded mask at `x=115, y=1110, width=656, height=300`. Their 50-pixel overlap must exceed the 24-pixel corner radius so the final union has no seam or inward corners.

- [x] **Step 2: Synchronize each material fade with its caption**

Fade the upper material and “PumpSync” from 0.45–1.35 seconds. Fade the lower material and “Your pump data. Your choice.” from 1.35–2.25 seconds. Composite the upper material first and the lower extension second using identical blur and tint settings.

- [x] **Step 3: Regenerate and inspect the transition**

Render the complete preview, then export closing frames before the tagline, halfway through its fade, and after it is fully visible. Confirm the first bubble is rounded, the lower surface appears only with the tagline, the completed background is continuous, and neither text line is clipped.

- [x] **Step 4: Validate and commit**

Run the pipeline's media assertions, `git diff --check`, and inspect the final repository state. Commit only the pipeline, specification, plan, and regenerated MP4 directly to `main`.

- [ ] **Step 5: Final state verification**

Reload the version page and verify one English (U.S.) iPhone App Preview, eight correctly ordered iPhone screenshots, eight correctly ordered iPad screenshots, and no unintended submission-state change. Record the frontend `HEAD`, worktree status, and ahead/behind state for handoff.

### Task 6: Make every caption a native, accessible text overlay

**Files:**
- Modify: `scripts/ios/render-app-preview-caption.swift`
- Modify: `scripts/ios/create-iphone-app-preview.sh`
- Modify: `docs/app-store/app-previews/README.md`
- Modify: `docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4`

**Interfaces:**
- Consumes: the five raw Simulator clips in `/tmp/pumpsync-app-preview` and the renderer CLI `render-app-preview-caption.swift <style> <text> <output.png> <x> <y> <width> <height> <font-size>`.
- Produces: transparent, system-font caption layers with no panel or shadow, assembled into a 30-second App Preview.

- [x] **Step 1: Make the renderer text-only**

Remove panel, shadow, inset, and style-dependent font weight rendering. Preserve the current CLI for compatibility. Render every caption with `NSFont.systemFont`, `.medium` weight, `#6B6B70`, centered multiline alignment, and transparent surrounding pixels.

- [x] **Step 2: Update caption geometry and sizes**

Set feature captions to 40–44 pt in clear screen areas. Keep subscription captions clear of Subscribe. Use “Connect a self-hosted backend.” directly below Connect, place privacy in the top third clear of Back, and place both closing lines in the top third over the existing white veil.

- [x] **Step 3: Regenerate and inspect all scenes**

Run `bash -n scripts/ios/create-iphone-app-preview.sh` and `bash scripts/ios/create-iphone-app-preview.sh`. Export frames at 2, 9, 12, 16, 22, 27, and 29 seconds. Confirm all captions are gray, backgroundless, legible, and do not cover the specified controls.

- [ ] **Step 4: Validate and commit on main**

Verify H.264 High, 886 × 1920, 30 fps, 25–30 seconds, no audio, and size below 500 MB. Run `git diff --check`; update the preview README; commit the pipeline, documentation, and MP4 directly on `main`.

### Task 7: Record an active sync and refine caption hierarchy

**Files:**
- Create temporarily: `/tmp/pumpsync-app-preview/sync-active.mov`
- Modify: `scripts/ios/render-app-preview-caption.swift`
- Modify: `scripts/ios/create-iphone-app-preview.sh`
- Modify: `docs/app-store/app-previews/README.md`
- Modify: `docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4`

**Interfaces:**
- Consumes: genuine Simulator status and active-sync recordings, the five existing storyboard recordings, and the existing caption renderer.
- Produces: one Apple-compliant preview with visible Sync action feedback, regular-weight large captions, and tight translucent veils where footage would otherwise reduce legibility.

- [x] **Step 1: Record the active sync state**

Build and launch PumpSync on the iPhone simulator using the deterministic active-sync preview fixture, record `sync-active.mov`, and preserve at least one second where the action is disabled and the sync icon is spinning. Inspect a recorded frame before using it.

- [x] **Step 2: Render regular-weight veiled captions**

Use SF system regular at `#5F6066`. Render a tight white `82%` veil behind caption text, with no shadow, approximately 48–50 pt feature text, 72 pt closing title, and 50 pt closing tagline.

- [x] **Step 3: Recompose the storyboard**

Use active-sync footage in the opening scene. Put its caption in the top third. Return subscription captions to their related benefits, use “Connect to your own backend that you host and manage.” below Connect, place the Data Handling caption over Credentials, and put closing copy in the top third. Use thin veils for all of these captions.

- [x] **Step 4: Regenerate, inspect, validate, and commit**

Inspect frames at 2, 5, 9, 12, 16, 22, 27, and 29 seconds. Verify visible active sync feedback, legibility, caption placement, no Subscribe overlap, H.264 High, 886 × 1920, 30 fps, 25–30 seconds, no audio, and size below 500 MB. Commit directly on `main`.

### Task 8: Use transparent, lightweight high-impact captions

**Files:**
- Modify: `scripts/ios/render-app-preview-caption.swift`
- Modify: `scripts/ios/create-iphone-app-preview.sh`
- Modify: `docs/app-store/app-previews/README.md`
- Modify: `docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4`

- [x] **Step 1: Remove caption veils**

Render captions on fully transparent layers with no veil, shadow, or padding.

- [x] **Step 2: Increase type and reduce weight**

Use the San Francisco system light weight in black, with a 72 pt base size for every caption. Expand transparent layout areas to accommodate natural multiline wrapping.

- [x] **Step 3: Regenerate and inspect**

Regenerate the preview, inspect all six caption scenes, validate the required App Preview media characteristics, and commit directly on `main`.

### Task 9: Smooth storyboard transitions and apply background blur

**Files:**
- Modify: `scripts/ios/render-app-preview-caption.swift`
- Modify: `scripts/ios/create-iphone-app-preview.sh`
- Modify: `docs/app-store/app-previews/README.md`
- Modify: `docs/app-store/app-previews/pumpsync-iphone-app-preview.mp4`

- [ ] **Step 1: Add rounded background-blur layers**

Blur only the app pixels beneath each caption. The final scene uses one shared rounded blur region behind its title and tagline.

- [ ] **Step 2: Revise copy and placement**

Use “PumpSync runs the backend.” above Managed connection, move the other captions to their specified sections, and make the closing PumpSync title larger than the 72 pt feature-caption base.

- [ ] **Step 3: Cross-dissolve scenes**

Replace direct concatenation with 0.35-second cross-dissolves. Caption fade timing must leave the outgoing copy gone before the incoming screen is fully visible.

- [ ] **Step 4: Regenerate, inspect, validate, and commit**

Inspect all scenes and transition boundaries; validate App Preview metadata, run `git diff --check`, and commit directly on `main`.
