# App Store App Preview

The iPhone App Preview uses six genuine Simulator recordings in this order:

1. `status.mov`
2. `sync.mov`
3. `subscription.mov`
4. `self-hosted.mov`
5. `privacy.mov`
6. `close.mov`

Place the raw clips in `/tmp/pumpsync-app-preview`, then run:

```sh
scripts/ios/create-iphone-app-preview.sh
```

Static Simulator screens may contain only a few encoded frames because `simctl` records display changes. The assembly script deliberately extends the final genuine frame to create the approved static holds.

The output is `pumpsync-iphone-app-preview.mp4`: a silent, 30-second, portrait H.264 High-profile video at 886 × 1920 and 30 fps, targeting 11 Mbps. Upload it to the English (U.S.) iPhone App Preview slot for App Store version 1.0. Do not upload it to the iPad media set.
