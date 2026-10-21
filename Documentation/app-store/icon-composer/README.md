# Layered PumpSync icon

Open `../../../PumpSync/Resources/AppIcon.icon` in Apple Icon Composer. The pump and tubing are one foreground group; both sync arrows are individually editable in a second group. The transparent SVG silhouettes trace the approved option 2 refinement: a larger pump, shorter tubing, and two clean sync arrows. Each layer retains its position on a 1024-point canvas.

The artwork contains no painted glow, reflection, bevel, or shadow. Composer supplies Liquid Glass with restrained translucency and neutral shadows. The installed Composer was checked in Design Generation 27, with default, dark, and mono previews. The background uses a native automatic teal gradient rather than the old flattened teal-to-blue background.

The app uses `PumpSync/Resources/AppIcon.icon` as its primary `AppIcon`. Xcode compiles the layers into native icon appearances. `project.yml` remains the project source of truth. The preview PNG is for review only and is not shipped. Physical-device appearance has not been validated.
