# PumpSync App Preview Design

## Objective

Create one portrait iPhone App Preview that explains PumpSync's complete value proposition in 25–30 seconds: review pump data, sync it to Apple Health, choose a PumpSync subscription or a self-hosted deployment, and understand the privacy model.

## Audience and Tone

The preview is for prospective users who already understand insulin pumps but may not understand PumpSync. It should feel like a concise product demonstration rather than an advertisement. Captions must be brief, factual, readable without audio, and consistent with the current terminology.

## Storyboard

1. **Sync overview (0–8 seconds):** Show the ready status, then a genuine in-progress sync with the Sync action disabled and its icon spinning. Caption: “Sync insulin and carbohydrates from your pump to Apple Health” with no terminal punctuation. Position it directly below the Sync heading and fade it in after 0.4 seconds.
2. **PumpSync subscription (8–14 seconds):** Present the subscription benefits. Show “PumpSync runs the backend” above the Managed connection heading, then replace it with “No server to manage” below the No server setup detail with clear separation. Neither feature caption uses terminal punctuation or may cover Subscribe.
3. **Self-hosted (14–20 seconds):** Show the Self-hosted connection settings. Caption: “Or connect to a backend you host and manage” with no terminal punctuation. Position it below Connect with the same separation used beneath No server setup. “Or” explicitly presents Self-hosted as the alternative to the PumpSync subscription shown in the preceding scene.
4. **Privacy (20–26 seconds):** Show Data Handling. Caption: “Your Health data stays under your control” with no terminal punctuation. Position it over the Stored on this device section; the card details do not need to remain readable.
5. **Close (26–30 seconds):** Return to the sync overview. Fade in “PumpSync” with a compact upper frosted surface, then fade in “Your pump data. Your choice.” 0.4 seconds later while a complementary lower frosted extension appears at the same rate. The two surfaces overlap sufficiently to eliminate seams and form one continuous rounded background after the second transition. Position both lines in the top third. The PumpSync title is larger than feature caption text.

Use 0.35-second cross-dissolves between every scene. Fade the outgoing caption during the dissolve and fade the incoming caption in after the destination screen settles. Avoid decorative animation, narration, music, or claims that are not visible in the app.

## Capture and Composition

- Capture genuine app UI from an iPhone simulator in portrait orientation.
- Use deterministic demo data and avoid displaying personal information, credentials, or production tokens.
- Keep important controls away from caption overlays, including the Subscribe button and tab bar.
- Use the app's native San Francisco system font for every caption, with light weight and black text. The feature-caption base size is 72 pt.
- Use a tight rounded background blur behind each caption. The closing title begins on an upper frosted surface; a lower extension fades in with the tagline and joins it into one continuous background rather than leaving two separate panels. Animate each caption with a 0.3-second opacity fade and a slight upward movement.
- The default poster frame should clearly show the app’s status overview and the PumpSync name.

## Delivery Contract

- One portrait H.264 `.mp4` or `.mov`.
- Resolution: 886 × 1920 pixels.
- Duration: 25–30 seconds; never outside Apple’s 15–30 second limit.
- Progressive scan, maximum 30 fps, High Profile Level 4.0 or lower.
- Target video bitrate: 10–12 Mbps.
- One enabled 256 kbps AAC-LC stereo track at 48 kHz. The track uses an inaudible noise floor, so the preview remains effectively silent while satisfying App Store Connect's media requirements.
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
