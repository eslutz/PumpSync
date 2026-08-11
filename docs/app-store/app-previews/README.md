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

Captions are rendered separately from the app footage. Every caption uses the app's native San Francisco system font at light weight and 72 pt black text. A tight rounded blur of the underlying app footage supports each caption; the closing title and tagline share one blur region. The opening transitions from the ready state to a genuine disabled, spinning Sync action, and scenes use 0.35-second cross-dissolves.

The output is `pumpsync-iphone-app-preview.mp4`: an effectively silent, 25–30 second portrait H.264 High-profile video at 886 × 1920 and 30 fps, targeting 11 Mbps. It includes one enabled 256 kbps AAC-LC stereo track at 48 kHz with an inaudible noise floor, as required by App Store Connect. Upload it to the English (U.S.) iPhone App Preview slot for App Store version 1.0. Do not upload it to the iPad media set.
