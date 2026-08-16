# PumpSync Dark App Icon Design

## Goal

Replace only the iOS dark-appearance app icon with a variant that feels at home beside Apple system icons and other dark Home Screen icons while remaining immediately recognizable as PumpSync.

## Approved Direction

Use the existing PumpSync pump-and-circular-arrows composition without changing its geometry, scale, orientation, or meaning.

- Replace the saturated full-tile teal-to-blue treatment with a near-black navy foundation.
- Render the pump in a softer cool white instead of a glaring pure white.
- Apply restrained teal-to-blue color to the circular arrows so the brand palette remains identifiable without dominating the tile.
- Keep the design clean and flat enough to work with iOS-provided icon effects; avoid added text, borders, drop shadows, glows, bevels, and ornamental detail.
- Maintain strong separation between the pump, arrows, and background at small Home Screen sizes.

## Scope

The only project asset to replace is:

`PumpSync/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark-1024.png`

The default and tinted icons, asset-catalog metadata, app UI, and branding elsewhere remain unchanged.

## Production Constraints

- PNG, exactly 1024 by 1024 pixels.
- Preserve the existing icon's rounded-square-safe composition and generous edge clearance.
- No text or watermark.
- Preserve the original symbol rather than introducing a newly interpreted pump or arrow shape.

## Verification

- Inspect the finished 1024-pixel asset directly.
- Downsample it to representative Home Screen size and check symbol recognition, contrast, and visual weight.
- Confirm the asset-catalog entry still resolves the dark appearance to the replacement file.
- Confirm only the approved dark icon and this design record changed.
