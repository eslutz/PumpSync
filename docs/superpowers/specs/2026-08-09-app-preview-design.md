# PumpSync App Preview Design

## Objective

Create one portrait iPhone App Preview that explains PumpSync's complete value proposition in 25–30 seconds: review pump data, sync it to Apple Health, choose a PumpSync subscription or a self-hosted deployment, and understand the privacy model.

## Audience and Tone

The preview is for prospective users who already understand insulin pumps but may not understand PumpSync. It should feel like a concise product demonstration rather than an advertisement. Captions must be brief, factual, readable without audio, and consistent with the current terminology.

## Storyboard

1. **Status (0–4 seconds):** Open on the status overview and recent pump data. Caption: “Keep your pump data in view.”
2. **Sync (4–11 seconds):** Demonstrate the sync workflow and its Apple Health result. Caption: “Sync insulin and carbohydrates to Apple Health.”
3. **PumpSync subscription (11–17 seconds):** Show Settings with PumpSync selected and present the subscription screen. Caption: “Subscribe to PumpSync—no server to manage.”
4. **Self-hosted (17–23 seconds):** Close the subscription screen, select Self-hosted, and show its connection settings. Caption: “Or connect to your own self-hosted backend.”
5. **Privacy (23–28 seconds):** Open Data Handling and show the privacy summary. Caption: “Your Health data stays under your control.”
6. **Close (28–30 seconds):** Return to the status overview. Caption: “PumpSync.”

Transitions should be direct cuts or short dissolves. Avoid decorative animation, narration, music, or claims that are not visible in the app.

## Capture and Composition

- Capture genuine app UI from an iPhone simulator in portrait orientation.
- Use deterministic demo data and avoid displaying personal information, credentials, or production tokens.
- Keep important controls away from caption overlays.
- Use the existing PumpSync visual language for captions: high-contrast, restrained typography and colors.
- The default poster frame should clearly show the app’s status overview and the PumpSync name.

## Delivery Contract

- One portrait H.264 `.mp4` or `.mov`.
- Resolution: 886 × 1920 pixels.
- Duration: 25–30 seconds; never outside Apple’s 15–30 second limit.
- Progressive scan, maximum 30 fps, High Profile Level 4.0 or lower.
- Target video bitrate: 10–12 Mbps.
- No audio track unless a valid 256 kbps stereo AAC track is deliberately added. This design uses no audio.
- Maximum file size: 500 MB.
- Upload to the English (U.S.) iPhone App Preview slot for version 1.0.

## Validation and Acceptance

- Watch the exported file from beginning to end and inspect representative frames.
- Verify resolution, duration, frame rate, codec/profile, bitrate, pixel format, and absence of unintended audio with media metadata tools.
- Confirm every caption uses “PumpSync subscription,” “PumpSync,” “Self-hosted,” or “PumpSync-hosted backend” according to the terminology convention.
- Confirm no old hosted-subscription product wording appears.
- Upload successfully to App Store Connect and verify processing completes without an asset error.
- Verify the preview occupies the first media position and uses an intentional poster frame.

## Scope Boundaries

This work creates only the iPhone preview. It does not create an iPad preview, add narration or music, change app behavior, submit the app for review, or complete a subscription purchase.
