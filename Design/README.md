# PumpSync designs

Open **PumpSync.fig** in OpenPencil. This is the canonical editable design file: 284 screen/state designs across 71 families, each in iPhone/iPad and Light/Dark. The latest additions are on **10 · Complete Screen Coverage**. The `.fig` extension is intentional; it is the saved and verified editable format.

## Review

Open [the interactive preview](Exports/Preview/Preview.html). Use the Screen menu, linked controls, and vertical scrolling. If your browser restricts local files, serve it from the repository root:

```sh
python3 -m http.server 8769 --bind 127.0.0.1 --directory Design/Exports/Preview
```

Then open <http://127.0.0.1:8769/Preview.html>. The preview contains 284 designs, 1,072 links and 216 scroll regions. Its PNG assets are required for the standalone review; they are generated exports, not editable design sources. All data is synthetic and all assets are local.

## Contents and maintenance

- `PumpSync.fig`: one canonical editable document with text, vectors, auto-layout, components and variables.
- `SCREEN-COVERAGE.md`: the complete screen/state and device/theme matrix, including editable node IDs.
- `References/Original-Figma-Export.fig`: original Figma migration reference; do not edit it as the current design.
- `References/*-acceptance.json` and `coverage-audit.json`: retained validation records from the October 20, 2026 completion pass.
- `References/file-manifest.json`: SHA-256 checksums recorded during migration into this repository.
- `Exports/Preview/`: self-contained browser review and its required images.

The designs use frontend commit `e922b0e` as their source checkpoint. Current SwiftUI source governs copy and hierarchy when older runtime screenshots differ. After editing the canonical document, update affected exports, coverage and validation records together. The manifest describes this handoff and must be refreshed when those files change. Historical generation scripts and intermediate copies are not retained; the preview is a saved export, not a reproducible build from this repository.

## Interaction and fidelity boundaries

OpenPencil pages 06–09 contain 12 live control instances for main tabs, connection selection and source-record expansion. All passed 24 transitions in the earlier native desktop review. The final saved bindings were checked headlessly. General screen navigation and scrolling are provided by the browser companion, rather than by every editable artboard.

File structure, complete four-variant coverage, component references, fonts and saved-file roundtrip were checked. Prior artboards and native master visuals were preserved. These checks do not establish pixel-perfect runtime equivalence or accessibility compliance. Source/library styles, small native labels and static glass approximations remain intentional fidelity limitations.

Apple-owned StoreKit product and purchase sheets, Health authorization, sharing and Mail composition require runtime captures. Dynamic Type, keyboards, focus and assistive behavior require runtime acceptance. The preview does not perform authentication, configuration changes, purchases or Health writes.

`Design/` is repository documentation and is outside the XcodeGen app source/resource paths; it is not bundled into the app.
