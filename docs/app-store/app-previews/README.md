# App Store App Preview

The iPhone App Preview uses five genuine Simulator recordings in this order:

1. `status.mov`
2. `subscription.mov`
3. `self-hosted.mov`
4. `privacy.mov`
5. `close.mov`

Place the raw clips in `/tmp/pumpsync-app-preview`, then run:

```sh
scripts/ios/create-iphone-app-preview.sh
```

Static Simulator screens may contain only a few encoded frames because `simctl` records display changes. The assembly script deliberately extends the final genuine frame to create the approved static holds.

Captions are rendered separately from the app footage. Every caption uses the app's native San Francisco system font, medium-gray `#6B6B70` text, and a transparent surrounding layer—there are no caption panels or shadows. The closing title and tagline fade in over a subtle white veil in the top third of the screen.

The output is `pumpsync-iphone-app-preview.mp4`: a silent, 30-second, portrait H.264 High-profile video at 886 × 1920 and 30 fps, targeting 11 Mbps. Upload it to the English (U.S.) iPhone App Preview slot for App Store version 1.0. Do not upload it to the iPad media set.
