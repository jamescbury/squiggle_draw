# Squiggle Draw

A native Mac studio for turning photos into ordered pen drawings. macOS 14+, Apple silicon, Swift 6. The app header shows the running version and build; the release version is defined in `version.env`.

## Start a drawing

Choose **Open image** or **Try a sample**. Shell, apple, pear and pitcher, and mountain lake are bundled generated references, with provenance beside the sample files. Auto optimize chooses starting settings for the selected style. **Generate drawing** applies subsequent edits; stale previews are clearly marked. **Test the draw** animates the same order exported in SVG.

The main style picker contains six techniques:

| Style | Marks and intent |
| --- | --- |
| Form sketch | Strong contours, form-following shading, deeper shadows, then fine accents. The default. |
| Circular scribbles | Broad loops that bend along edges, with optional photo-guided shadow widths. |
| Continuous sketch | Long, freely crossing curves influenced by local surface directions. |
| Tonal cross-hatching | Crossing curved strokes that build remaining tone in stages. |
| Stipple dots | Relaxed dots concentrated by tone and features, with size based on actual ink mass. |
| 3D poly | A conforming triangle mesh with smaller faces at detailed features and simulated depth. |

The shared analysis estimates edges, local directions, and smooth connected backgrounds. **Background shading** leaves the background as paper at zero and restores it at one. Increase it if the estimate removes part of your subject. This is image analysis, not semantic object recognition or actual 3D reconstruction. Circular and continuous styles favor long paths, with lifts across sustained blank regions to protect highlights. The older wave and stipple-tour strategies remain in the core for compatibility, outside the main picker.

## Color and physical pens

Choose **RGB + Black**, then optionally enable **Alternate colors while drawing** under INKS. Switch frequency advances each ink in rounds. Leave it off for complete pen passes. Individual-pen exports preserve the original paths even when alternation is on. Changing these settings requires regeneration.

RGB + black is a stylized four-pen separation rather than full photographic color. Filled 3D poly uses photo colors and does not alternate pens. Wireframe poly exports outlines. Layer checkboxes affect preview and combined export. SVG, PNG, and simulated playback preserve the chosen drawing order.

For circular scribbles, **Bend loops along edges** keeps loops broad along contours while allowing them to flatten across ridges and turn back at strong tonal or color boundaries. It is enabled by default. Disable it for the earlier round-loop behavior. Sustained blank areas still allow pen lifts.

**Thicker lines in shadows** is on by default. **Shadow thickness** sets the darkest width relative to Pen width (default 4×), while highlights use finer lines. Auto optimize now recommends much larger loops. Disable shadow widths for a physical pen and regenerate: the engine recalibrates overlap for uniform ink. Width changes keep shared endpoints and do not add pen-lift pauses in Test the draw or BOOX 0.15. RGB alternation preserves the widths.

## BOOX Library

Save a completed drawing with **Add to BOOX Library**. A saved sketch is an independent snapshot of its visible inks, paths, and color order. Rename it, check whether it is **Available on BOOX**, or remove its library copy. Source photographs and existing exported files are kept.

Enable **Share library with BOOX**, connect the tablet by USB, and click **Pair connected BOOX**. Squiggle 0.16 or later stores the Wi-Fi address automatically. On BOOX, choose **Library → Sync now**. Sync prefers USB, then falls back to the saved Wi-Fi address when unplugged. The Mac app must stay open with sharing enabled. Starting in Mac 0.14.1, the sharing switch is remembered across app restarts. Saving a sketch on the Mac does not download it to the tablet: choose **Sync now** on BOOX to transfer the selected sketches. Wi-Fi requires both devices on the same local network. Android platform tools and an already-authorized USB debugging connection are required for cable pairing. Manual Wi-Fi pairing remains under its disclosure. Pair again over USB if the Mac’s network address changes. Downloaded sketches stay available offline. Deselection/removal takes effect on the tablet after the next successful sync. A failed transfer keeps the previous tablet library.

Sharing is opt-in and read-only. The private pairing address grants access to selected SVGs over local HTTP, so use a trusted network. Photographs and thumbnails are never served. The Mac library supports up to 64 sketches / 256 MiB. Each drawing must fit the player's 32 MiB, 28 million path-character, and 20,000-element limits. Reduce detail or select fewer inks if saving reports an oversized drawing.

## Export and playback

**Export SVG** produces plain paths/circles/polygons without external resources. **PNG** uses the same drawing geometry. The BOOX player recognizes circular shadow-width ratios in Studio SVGs; older and other imported drawings keep the uniform pen setting. Dots play as circle outlines. Each filled polygon gets its fill immediately after its outline. The simulation includes pen-lift pauses, but cannot simulate e-ink refresh, ghosting, or hardware delays. This app does not control an AxiDraw directly.

## Build and validate

```sh
swift test -c release
sh build-app.sh
```

Outputs: `dist/Squiggle Draw.app` and `dist/Squiggle-Draw-Mac.zip`. The script creates a fresh app bundle, includes sample resources, and verifies its local ad-hoc signature. Public binary distribution still requires signing/notarization. The drawing workspace is not restored after closing; saved library sketches persist.

`SquiggleSamples` generates repeatable PNG/SVG comparisons and geometry metrics from an explicit input image. Inputs apply orientation and composite transparency onto white; the app works at up to 1600 pixels on the longest side. Core generation is deterministic for a fixed seed, checks cancellation, and uses bounded geometry budgets. Tests cover tone/highlights, color order, coordinates, cancellation, export sizes, library transactions and HTTP routing.

## Research

Independent implementations inspired by [Circular Scribble Art (2015)](https://cgv.cs.nthu.edu.tw/projects/Recreational_Graphics/CircularScribbleArt), [thescribbler](https://github.com/ugocapeto/thescribbler), [Gregg Wygonik's SquiggleDraw](https://github.com/gwygonik/SquiggleDraw), and [StippleGen 2](https://www.evilmadscientist.com/2012/stipplegen2/). Upstream research code, lookup tables, example portraits, and paper figures are not bundled. Results are not claimed to match the paper's benchmarks.

## Crop an imported photo

Choose **Crop photo…**, drag a rectangle over the photo, then choose **Apply crop**. The workspace fits the new size and all drawing styles use the cropped pixels. With automatic optimization enabled, the drawing regenerates for that area; otherwise choose Generate drawing when ready. **Cancel** keeps the current image. **Reset crop** restores the original imported photo, and reopening the crop tool lets you choose a new region from the full photo. Source files and previously saved library sketches are unchanged.

## Sequential drawings

Open the **Sequential drawings** tab. Add two or more saved sketches from the gallery, use the up/down arrows to order them, and enter the number of minutes each takes to change into the next. Each entry defaults to 60 minutes; accepted durations are 1–1,440 minutes. Repeat a drawing by adding it again. Removing an entry here leaves its library sketch intact. BOOX availability does not affect this gallery.

**Play**, **Pause**, **Restart**, **Next**, and the progress slider control the current transition. Click a drawing’s title in the order list to start from it. **Actual timing** uses your saved minutes; the 60× and 120× previews run faster without changing them. The last drawing transitions into the first, without clearing the canvas. Changing tabs pauses playback. Order and timing are saved on this Mac, but playback position and preview speed reset after relaunch.

**Present** opens a separate resizable window; use its green window button for full screen. This is local Mac playback, with a 1,280 × 720 landscape canvas, not a TV app or video export. Photos with different proportions stay centered and retain their aspect ratio.

The player uses all saved vector strokes, including RGB colors and variable widths. Old strokes shorten along their own paths; new strokes grow from their endpoints in small, scattered visits. Matching color coverage remains throughout the transition. Dots use round pen marks. Filled polygon regions appear after their outlines complete and disappear when their erasure begins; pen drawing styles provide the gradual effect. Only the current pair of drawings is loaded, so the completed drawing briefly holds while the next transition prepares.

## Display presets and photo colors

The drawing workspace groups controls into Display, Source photo, Art style, Color, Photo tuning, and Save & share. Detailed geometry settings are under **Fine-tune strokes**; Generate drawing stays at the bottom of the inspector.

Choose **E-ink** for black strokes, **E-ink RGB** for RGB + black, **TV** for full color, **Monitor** for a 24-color photo palette, or **Pen plotter** for fixed-width monochrome strokes. Changing the destination applies its color, width, detail, and variable-width defaults; the technique and crop stay selected. Adjust any setting afterward. The destination is remembered across app restarts. These are rendering presets, not TV hardware calibration or native TV playback software.

**Photo palette** chooses 12 or 24 colors from the image. **Full color** samples local color along the drawing, retaining its contour and tonal geometry. Color runs meet at the same point, so a color change does not add a pen lift. Stroke pigments are darkened to compensate for white paper between lines. Photo colors are retained in the native preview, PNG/SVG exports, gallery, and sequential transitions. Filled 3D poly keeps its face colors, with optional palette reduction.

The **Gallery** tab replaces the BOOX Library label. Screen artwork saves locally without being selected for tablet sync. BOOX sharing controls and tablet playback warnings appear only for an e-ink destination. The gallery retains a 32 MB limit per SVG and a 256 MB total.

**Oil painting** and **Watercolor** are visible, disabled coming-soon choices. They do not apply filters or alter generated pen artwork.

Samples now include coffee, eyeglasses, a watch, sunflower, butterfly, goldfish, eye study, brass padlock, lemon, feather, chess knight, and mushroom, alongside the original four references. All sixteen are generated images; provenance is bundled.
