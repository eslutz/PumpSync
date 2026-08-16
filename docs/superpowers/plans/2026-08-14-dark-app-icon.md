# Dark App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace PumpSync's iOS dark-appearance app icon with the approved Apple-style dark variant.

**Architecture:** Use the current 1024-pixel dark icon as the edit target so the established pump-and-arrows composition remains recognizable. Generate one restrained recolor/restyle, validate it visually and mechanically, then replace only the dark appearance PNG already referenced by the asset catalog.

**Tech Stack:** Xcode asset catalog, PNG, built-in image generation, macOS `sips` and image inspection.

## Global Constraints

- Output must be a PNG exactly 1024 by 1024 pixels.
- Preserve the existing pump-and-circular-arrows composition, scale, orientation, and meaning.
- Use a near-black navy foundation, a soft cool-white pump, and restrained teal-to-blue arrows.
- Add no text, watermark, border, drop shadow, glow, bevel, or ornamental detail.
- Do not change the default icon, tinted icon, asset-catalog metadata, app UI, or branding elsewhere.

---

### Task 1: Generate and Validate the Dark Icon

**Files:**
- Modify: `PumpSync/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark-1024.png`
- Reference: `PumpSync/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`

**Interfaces:**
- Consumes: the current `AppIcon-Dark-1024.png` as the edit target and the approved design specification.
- Produces: a replacement `AppIcon-Dark-1024.png` selected automatically for the asset catalog's `luminosity = dark` appearance.

- [x] **Step 1: Inspect the current source asset**

Open the existing PNG and confirm it is the intended PumpSync pump-and-arrows icon.

- [x] **Step 2: Generate the approved visual edit**

Edit only the palette and luminosity treatment. Preserve the composition and symbol geometry while applying the approved near-black navy, cool-white, teal, and blue palette.

- [x] **Step 3: Install the generated PNG**

Copy the accepted generated output over `PumpSync/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark-1024.png` without changing `Contents.json`.

- [x] **Step 4: Verify dimensions and appearance**

Run:

```bash
sips -g format -g pixelWidth -g pixelHeight PumpSync/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark-1024.png
```

Expected: PNG, 1024-pixel width, and 1024-pixel height. Inspect the full-size result and a 120-pixel downsample for recognizable geometry, appropriate contrast, and subdued Home Screen weight.

- [x] **Step 5: Verify repository scope**

Run:

```bash
git status --short
git diff --check
git diff --stat
```

Expected: the planned dark icon and plan documentation are the only task-related changes; pre-existing unrelated untracked files remain untouched.

- [ ] **Step 6: Commit the asset**

```bash
git add PumpSync/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark-1024.png docs/superpowers/plans/2026-08-14-dark-app-icon.md
git commit -m "Refresh dark app icon"
```
