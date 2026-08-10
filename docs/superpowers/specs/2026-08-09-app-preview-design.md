# PumpSync App Preview Design

## Objective

Create one portrait iPhone App Preview that explains PumpSync's complete value proposition in 25–30 seconds: review pump data, sync it to Apple Health, choose a PumpSync subscription or a self-hosted deployment, and understand the privacy model.

## Audience and Tone

The preview is for prospective users who already understand insulin pumps but may not understand PumpSync. It should feel like a concise product demonstration rather than an advertisement. Captions must be brief, factual, readable without audio, and consistent with the current terminology.

## Storyboard

1. **Sync overview (0–8 seconds):** Show the ready status, then a genuine in-progress sync with the Sync action disabled and its icon spinning. Caption: “Sync insulin and carbohydrates from your pump to Apple Health.” Place it in the top third with no veil and fade it in after 0.4 seconds.
2. **PumpSync subscription (8–14 seconds):** Present the subscription benefits. Show “Managed by PumpSync” beside the Managed connection benefit, then replace it with “No server to manage” beside the No server setup benefit. Neither may cover Subscribe.
3. **Self-hosted (14–20 seconds):** Show the Self-hosted connection settings. Caption: “Connect to your own backend that you host and manage.” Position it immediately below Connect.
4. **Privacy (20–26 seconds):** Show Data Handling. Caption: “Your Health data stays under your control.” Position it over the Credentials card; the card details do not need to remain readable.
5. **Close (26–30 seconds):** Return to the sync overview. Fade in “PumpSync,” then fade in “Your pump data. Your choice.” 0.4 seconds later. Position both lines in the top third.

Transitions should be direct cuts or short dissolves. Avoid decorative animation, narration, music, or claims that are not visible in the app.

## Capture and Composition

- Capture genuine app UI from an iPhone simulator in portrait orientation.
- Use deterministic demo data and avoid displaying personal information, credentials, or production tokens.
- Keep important controls away from caption overlays, including the Subscribe button and tab bar.
- Use the app's native San Francisco system font for every caption, with light weight and black text on fully transparent layers.
- Use a 72 pt base size for every caption. Animate each caption with a 0.3-second opacity fade and a slight upward movement.
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
