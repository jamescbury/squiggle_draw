# Architecture

## Drawing

`SquiggleCore` contains the deterministic image-analysis, drawing, export, and playback-plan code. `PhotoAnalysis` provides a bounded analysis raster, feature energy, local surface directions, coordinate transforms, and a connected-background estimate. Each drawing strategy retains its own marks and geometry budget. Form sketch retains its contour → shading → accent sequence. The final color-order stage interleaves optional ink passes without changing the original single-pen paths.

`SquiggleDraw` is the SwiftUI/AppKit desktop interface. Generation and file work run outside the main actor. Request tokens prevent stale generation results from replacing newer images. `SquiggleSamples` is an explicit-input command-line gallery renderer.

`CircularContours` shapes broad loops using the surface-direction field and probes each displacement for tonal or RGB boundaries. Only the dimension across an edge tightens; the along-edge extent stays broad. Contact corners are softened and reprojected against the boundary. The original round-loop geometry remains available with edge bending disabled.

Circular scribbles optionally carry per-run width multipliers sampled from pigment at the pen position. Shared endpoints keep width changes continuous. Standard SVG stroke widths render outside the app; `data-squiggle-width-scale` carries ratios for the tablet's logical pen setting. Width runs are added after spatial ordering and retained through color partitioning. Tone compensation accounts for wider ink so shadow width replaces some of the densely overlapping geometry. Highlights use fine lines. Width changes are not counted as pen lifts.

## Library and transport

The Mac library stores an atomic JSON index and immutable SVG/thumbnail files, each identified by UUID. A save snapshots the generated drawing, visible inks, and color order; it does not copy the photograph. Availability and names are separate catalog metadata.

The opt-in server uses a random 64-character pairing token and a fixed local port, 48765. Only exact GET routes for the manifest and available SVG IDs are served. It never accepts filesystem paths, uploads, or remote commands. Requests, concurrency, catalog size, and file sizes are bounded. Source photographs and thumbnails are not HTTP routes.

Manifest schema 1 contains `libraryID` and `sketches`, each with `id`, `title`, `style`, `createdAt`, `bytes`, `sha256`, and `file`. The Android client accepts private IPv4 pairing addresses, refuses redirects, checks byte counts and hashes, stages the full transfer, and changes its active index only after success. A failed sync preserves the previous offline catalog. Different Mac library IDs retain separate caches. Unchecking on Mac removes only that managed tablet copy after a successful sync; manual SVG imports are independent.

## Playback

Both apps preserve SVG document order. The tablet streams bounded SVG input into compact geometry and grows ink by traveled distance. Pen lifts add a short pause. Filled polygons finish their outline and then apply their fill. Direct BOOX ink is experimental; colored/fill/variable-width artwork uses Canvas. Automated graphics tests cannot certify physical e-ink refresh or ghosting.

## Cable bootstrap

Mac USBConnection uses an existing authorized Android platform-tools connection. An explicit **Pair connected BOOX** action sends Squiggle’s existing bearer URL and library identity to the system-permission-protected PairingReceiver. The tablet saves its network address separately from the derived loopback URL. Sync tries the loopback bridge before Wi-Fi and checks the expected library ID before any snapshot commit. The Mac resumes only its previously paired serial while sharing is enabled. Inkwell’s credentials and reverse mappings remain separate.
