# Squiggle Studio

Photographs become ordered pen drawings on your Mac, then emerge stroke by stroke on a BOOX tablet.

- **Squiggle Draw**: native macOS photo conversion, black, RGB + black, photo palettes or full color, SVG/PNG export, drawing simulation, sequential draw/erase artwork, and a Wi-Fi sketch library.
- **Squiggle**: Android/BOOX SVG playback and an offline library synchronized from the Mac.

Start with **Form sketch**, or explore Circular scribbles, Continuous sketch, Tonal cross-hatching, Stipple dots, and 3D poly. The techniques share image analysis but keep their own marks. Wave rows and the older stipple tour remain internal compatibility implementations, outside the main style picker.

## Try it

Build the Mac app with `sh squiggle-draw/build-app.sh`, open `squiggle-draw/dist/Squiggle Draw.app`, and choose **Try a sample**. The sixteen bundled references include shell, apple, pear and pitcher, mountain lake, and twelve object studies. All are generated images. No family photographs are included.

1. Use **Crop photo…** to drag a box around the area you want to draw, then **Apply crop**. The workspace fits the cropped photo; **Reset crop** restores the full image. Pick a style and choose **Optimize photo**.
2. Adjust the style settings or Background shading; regenerate to apply changes.
3. Choose **Test the draw** to inspect the actual exported path order.
4. For RGB, **Alternate colors while drawing** advances the inks together. Leave it off for fewer physical pen changes.
5. Select an e-ink display preset, save a sketch to **Gallery**, check **Available on BOOX**, and enable **Share library with BOOX**. The sharing setting is remembered when you reopen the Mac app.
6. With the BOOX connected by USB, click **Pair connected BOOX** on the Mac. In Squiggle 0.16 or later, choose **Library → Sync now**. The tablet saves Wi-Fi automatically and prefers the cable when available. Keep both devices on the same local network. The tablet retains downloaded sketches offline.

Choose an output preset in the drawing workspace: **E-ink**, **E-ink RGB**, **TV**, **Monitor**, or **Pen plotter**. TV and monitor workflows use the local gallery without tablet warnings. Oil painting and watercolor are marked as coming soon.

Open **Sequential drawings** to choose saved gallery sketches, arrange them with the arrow buttons, and set each transition’s duration. The default is 60 minutes per drawing, with accelerated previews and a separate presentation window. The last drawing transitions back to the first. Order and timing save automatically.

The app header always shows the version/build. Hover over it to identify the running app copy.

## Development

Mac: macOS 14+, Swift 6/Xcode Command Line Tools. No external Swift packages.

```sh
cd squiggle-draw
swift test -c release
sh build-app.sh
```

Android: JDK 17 or 21, Android SDK 35. Set `ANDROID_HOME` or create a local `local.properties` with your SDK path; this file is deliberately excluded from source control.

```sh
cd squiggle-player
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
sh tests/run.sh
```

Generate a repeatable style comparison from an explicitly chosen sample:

```sh
swift run -c release --package-path squiggle-draw SquiggleSamples \
  squiggle-draw/Sources/SquiggleDraw/Resources/Samples/shell.png /tmp/squiggle-gallery
```

See [architecture](docs/ARCHITECTURE.md), [contributing](CONTRIBUTING.md), [release steps](docs/RELEASING.md), and [third-party references](THIRD_PARTY_NOTICES.md). The `docs` directory includes a static gallery suitable for GitHub Pages.

## Current limits

This is a beta. macOS builds are locally signed, not notarized. Drawing sessions are not restored after closing; saved library sketches persist. The Android build is a debug APK; signing keys are never included. BOOX firmware refresh behavior requires device testing; Canvas is the reliable fallback when direct pen initialization is unavailable. RGB + black is a four-pen interpretation, not full photographic color reproduction. Poly simulates depth in 2D.

Wi-Fi sharing is opt-in, read-only HTTP protected by a random pairing address on your local network. It shares selected SVG sketches, never source photographs. Keep the address private and use a trusted network; it is not an Internet hosting service. The tablet syncs when you choose Sync now. Removing a sketch from availability takes effect on the tablet's next successful sync.

MIT license covers this project's original source. Dependencies retain their own licenses. Sample-image provenance is included alongside the files.
