# Squiggle

An Android prototype for watching plotter artwork emerge on a BOOX Note Air5 C. Import SVG paths, then draw them gradually in their original order. The app generates a twenty-petal Spirograph curve internally, so you can draw immediately without an SVG. Tap Sample to reset this geometry. A matching `spirograph.svg` is included for use with your plotter.

## Install and try it

1. Copy `Squiggle-debug.apk` to the BOOX with USB or your normal file-transfer method.
2. Open it in the tablet's file manager. Allow that file manager to install the app when Android asks.
3. Launch **Squiggle**. Choose **Draw** to play the sample.
4. Move the speed slider while drawing. **Pause** keeps the ink; **Redraw** clears and plays it.
5. Choose **Library → Import SVG** to import your plotter artwork.

Version 0.17 attempts **Direct pen / 60 updates per second / Medium**. A compatibility library permits access to three BOOX framework types inside the app. Availability is checked from stroke responses, and playback recovers to Canvas when live ink fails. Choose **Options → Drawing method → Canvas** to use that renderer directly. For Canvas, compare System, Fast, Animation, and Quality at the same speed, or choose a per-app refresh mode in BOOX’s EinkWise menu. Color files, shadow widths, and filled polygons use Canvas playback. Direct-mode ink is absent from ordinary screenshots; physical observation is required to validate its output.

Direct pen support depends on the BOOX model and firmware. It remains experimental; Canvas is the reliable fallback. Version 0.17 has automated rendering and transfer checks, but still needs a fresh physical-tablet check for Wi-Fi pairing, flicker, ghosting, and direct ink.

**Clean screen** pauses playback and requests a cleanup refresh; it may flash. The app does not request automatic cleanup refreshes during playback; firmware may still perform its own refreshes. If cleanup is unsupported, use BOOX's own refresh control.

Speed runs from 1 to 500 Android density-independent screen units per second. It is measured along the curve, so unevenly spaced SVG points do not change speed. Each separate contour has a 0.2-second pen-lift pause. Update cadence controls how often the app adds ink, not the physical panel's guaranteed refresh rate.

## Wi-Fi library

On the Mac, open **BOOX Library**, add the generated sketches you want, and start Wi-Fi sharing. On the BOOX choose **Library → Pair / saved Macs → Pair a Mac**. Paste the complete pairing address shown by the Mac, then choose **Pair and sync**. Keep the Mac sharing and both devices on the same Wi-Fi during sync. Guest networks that isolate devices may prevent the connection.

Choose a downloaded title in Library to open it, then choose Draw. Downloads stay available after the app closes and without Wi-Fi. **Sync now** refreshes the currently paired Mac’s shared selection; deselected sketches disappear from that Mac’s managed cache after a successful sync. Pairing another Mac retains other libraries; select them under **Pair / saved Macs** for offline playback. The pairing address is saved only in the app’s private preferences and is never included in error messages or logs. Treat the address as a private access key; sharing is HTTP on your local network.

Each library permits up to 64 sketches, 32 MB per SVG, and 256 MB in total. Every download is size checked and SHA-256 verified. A failed or cancelled sync leaves the previous catalog and files available. Each sync stages a complete snapshot before committing a single atomic catalog pointer; enough temporary storage for the old and new snapshots is needed. Manual SVG imports remain separate. Opening Library pauses drawing, and syncing never automatically starts playback. Closing the app cancels an in-progress sync; network timeouts can take up to twelve seconds to release it.

## Supported artwork

- SVG paths, including Bézier curves, elliptical arcs, and multiple contours.
- Polyline, polygon, line, rectangle, circle, and ellipse outlines.
- Nested groups and matrix, translate, scale, rotate, and skew transforms.
- A root `viewBox`; otherwise the drawing fits its geometry bounds.
- Document order is playback order. Separate contours remain separate; no connecting ink is added.

This is a plotter-path player, not a general SVG picture renderer: closed polygon fills are applied after each polygon outline completes. SVG fill colors on polygons support group inheritance and inline overrides; fill="none" keeps wireframes empty. Completed fills survive pause and progress restoration on resize. Other shapes remain outlines, with optional Studio shadow-width ratios; CSS brush styles, opacity, and original stroke widths are not reproduced. SVG stroke colors are preserved from element attributes, inherited groups, and inline stroke declarations. Hex colors, rgb() colors, and common named colors are supported. Color drawings use Canvas playback and select Quality refresh. Export plain paths and flatten clipping, masks, text, referenced symbols, and nested SVG viewports before importing. Definitions, metadata, and groups explicitly marked `display:none` are skipped. CSS classes are not interpreted. Files are limited to 32 MB, 28 million path-data characters, and 20,000 elements/contours. Dense absolute M/L exports use a memory-efficient parser; large files may take tens of seconds to open.

No photo conversion is included: keep using your generator and import its SVG output. The app does not reorder paths to match an AxiDraw optimizer; export the desired order from your generator.

## What this prototype establishes

The renderer adds short curved segments to a persistent bitmap and requests redraws around the added ink. Existing marks remain in the bitmap. The controls stay static while drawing to avoid extra updates. Foreground playback holds a screen/CPU wake lock, renewed once a minute with a ten-minute safety lease, as well as the window keep-screen-on flag. Pause, completion, leaving the app, and closing it release the lock so normal sleep resumes. Playback pauses in the background and on resize; resize preserves drawing progress. Closing the app loses playback progress; downloaded Wi-Fi library files remain available.

The Canvas renderer uses BOOX **view-scoped refresh settings** with ordinary Android drawing. The experimental Direct pen renderer probes BOOX’s `startStroke` / `addStrokePoint` / `finishStroke` methods and falls back explicitly when unavailable. It retains the bitmap while sending subpixel samples directly, then restores the bitmap when paused. It does not inject stylus input events. Android and BOOX may enlarge or combine redraw regions, and the panel still updates in discrete steps. Device testing must establish whether the tip looks sufficiently continuous at your chosen speed. The computer's tests cannot verify flicker, ghosting, or firmware support.

## Build

Open this folder in Android Studio, or use JDK 17/21 and Android SDK platform 35:

```sh
./gradlew :app:assembleDebug
```

Output: `app/build/outputs/apk/debug/app-debug.apk`. Minimum Android version: 11. BOOX's repository is required to retrieve `onyxsdk-device:1.3.5.2` on a fresh build. The SDK's unrelated Wi-Fi, Bluetooth, and diagnostic permissions are removed from the merged app manifest. INTERNET and cleartext HTTP access support direct local Wi-Fi library sync; the client accepts only literal private/local IPv4 pairing addresses and refuses redirects. WAKE_LOCK is used only for active foreground drawing.

```sh
./tests/run.sh
./gradlew :app:testDebugUnitTest :app:lintDebug
```

The plain Java timing checks cover distance-based playback, speed changes, pen lifts, completion, restoration, and update batching. Android graphics tests cover SVG import, transform order, hidden geometry, malformed input, ink rendering, pause, and resize. Library tests cover offline reopening, verified reuse, failed transfers, cancellation, removals, separate Mac caches, manual-import preservation, schema/path/size bounds, a real local HTTP transfer, and redirect rejection. An optional live Mac fixture reads the private pairing URL from the file named by `SQUIGGLE_LIBRARY_URL_FILE` and downloads/imports the advertised SVGs, then reopens them offline. It expects one selected sketch by default; set `SQUIGGLE_LIBRARY_EXPECTED_COUNT` to check a different selection, including zero. Run that fixture with `:app:testDebugUnitTest --tests art.squiggle.player.SketchLibraryTest.liveMacInteroperabilityFixture --rerun-tasks`; do not print the private file’s contents.

Official references: [BOOX SDK](https://github.com/onyx-intl/OnyxAndroidDemo), [screen updates](https://github.com/onyx-intl/OnyxAndroidDemo/blob/master/doc/EPD-Screen-Update.md), [update modes](https://github.com/onyx-intl/OnyxAndroidDemo/blob/master/doc/EPD-Update-Mode.md).

## Shadow widths (0.15)

Circular drawings from Squiggle Draw 0.13 can carry photo-guided stroke widths. The tablet multiplies its Pen width setting by each exported `data-squiggle-width-scale` ratio (0.25–6). Standard `stroke-width` attributes retain the desktop appearance in other SVG viewers. Imports without this Studio metadata retain the existing uniform-width behavior. Same-color runs sharing an endpoint continue without a pen-lift pause; color changes and disconnected paths still lift. Resize and restart preserve width behavior. Variable widths use the canvas renderer. Re-export and sync a sketch after enabling the new desktop option; older saved library items remain unchanged.

## USB pairing and transport (0.16)

On Mac 0.14, enable **Share library with BOOX** and click **Pair connected BOOX** while the authorized USB cable is attached. The tablet saves the Mac library identity and Wi-Fi address without text entry. **Library → Sync now** tries the Squiggle USB bridge first, then the saved Wi-Fi address. A mismatched library identity is rejected before committing. Saved sketches and other Mac libraries are preserved. Re-pair over USB if the Mac’s Wi-Fi address changes.

The Mac watches only the paired device while sharing is enabled and restores its port 48765 tunnel after replugging. It uses Android platform tools, the same transport approach as Inkwell, without modifying Inkwell’s port 9110 bridge or reading its credentials. Pairing is delivered through a manifest receiver protected by the Android system DUMP permission; ordinary apps cannot send it pairing broadcasts. The app does not request that permission itself.

## BOOX layout and sleep images (0.17)

Canvas controls use bold black 18sp labels, outlined white buttons, and larger touch targets. Library is a separate page with a permanent **Back to canvas** button; Android Back also returns to the canvas. Selecting a sketch opens the canvas, and manual import shows its loading message there. Opening Library pauses playback and preserves the current canvas.

Choose **Sleep image → Use this drawing** to export the entire artwork as a full-screen PNG and ask BOOX to set it as the sleep page. You do not need to finish playback first. Colors, polygon fills, and variable widths are preserved. The exported PNG is saved under **Pictures / Squiggle**; BOOX may also make its own copy. The sleep SVG is kept privately, reopens when the app starts, and is available through **Library → Open sleep drawing**. The generated Spirograph reopens as the default sample. Choosing **Sleep image → Choose photo** sets a normal image as the sleep page; a photo has no drawing paths to replay.

A real BOOX sleep image is static and cannot host a working touch button. Wake the tablet with its power button, then tap **Redraw** in Squiggle to watch the current drawing from the start. Keep Squiggle open when putting the tablet to sleep for the shortest route back. If another drawing is open, use **Library → Open sleep drawing** first. Redraw remains a foreground action; the app does not launch playback automatically while asleep or on wake.

The BOOX screensaver API dispatches a request and does not return a completion acknowledgment. The app reports that the image was sent; if dispatch fails, it gives instructions to select the exported PNG in BOOX Screensaver settings. The actual sleep display was checked on the connected Note Air5 C with the Spirograph and RGB Mittens artwork. Other firmware may behave differently. Original SVG files are unchanged.
