# App Store App Preview

The iPhone App Preview uses six genuine Simulator recordings in this order:

1. `status.mov`
2. `sync-active.mov`
3. `subscription.mov`
4. `self-hosted.mov`
5. `privacy.mov`
6. `close.mov`

Place the raw clips in `/tmp/pumpsync-app-preview`, then run:

```sh
scripts/ios/create-iphone-app-preview.sh
```

Static Simulator screens may contain only a few encoded frames because `simctl` records display changes. The assembly script deliberately extends the final genuine frame to create the approved static holds.

Captions are rendered separately from the app footage. Every caption uses the app's native San Francisco system font at regular weight, medium-dark gray `#5F6066` text, and a tight white veil at 82% opacity. Veils have no shadow and only enough padding to preserve legibility. The opening transitions from the ready state to a genuine disabled, spinning Sync action; the closing title and tagline fade in over veils in the top third of the screen.

The output is `pumpsync-iphone-app-preview.mp4`: a silent, 30-second, portrait H.264 High-profile video at 886 × 1920 and 30 fps, targeting 11 Mbps. Upload it to the English (U.S.) iPhone App Preview slot for App Store version 1.0. Do not upload it to the iPad media set.
