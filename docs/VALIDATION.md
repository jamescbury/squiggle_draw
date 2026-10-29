# Validation — Mac 0.14.0 / BOOX 0.16

- 108 Swift release tests passed; Mac app build and ad-hoc signature verification passed.
- 39 Android unit/graphics tests passed, with one optional live-Mac fixture skipped; Android build and lint passed. New tests cover cable preference, Wi-Fi fallback after timeout, wrong-library rejection before commit, valid USB pairing, and invalid pairing preserving saved settings.
- Installed player 0.16 on the USB-connected BOOX Note Air5 C, retaining app data.
- Executed the actual Mac USBTransport pairing code against that tablet. Verified its saved Wi-Fi URL and library identity without logging the bearer token.
- The physical tablet fetched the selected Mac library manifest through both the USB reverse tunnel and its direct Wi-Fi address. Both returned the same library and two selected sketches. This checks connectivity and pairing; the user still chooses Sync now to download the sketches.
- Saved cable reconnection settings for Mac 0.14. Inkwell’s tunnel was left intact. The new Mac app must be reopened for its reconnection watcher to run.

---

# Earlier validation — 0.13.1 / player 0.15

Circular loops now deform around photo edges, keeping a broad extent along contours and narrowing across them. RGB boundary probes also protect narrow highlights between endpoints. Two smoothing passes round contact corners and recheck their boundary confinement. The option is labelled **Bend loops along edges** and is enabled by default.

- 108 Swift release tests passed. New tests cover silhouette confinement with a broad tangential extent, narrow highlights, equal-luminance color boundaries, image bounds, determinism, and reduced highlight spill in actual generated strokes.
- Nine full-resolution circular samples passed all BOOX size limits; SVG byte/element/path counts match their estimates.
- Mac 0.13.1 build 15 packaged with its ad-hoc signature verified. BOOX 0.15 requires no update for this geometry change; regenerate and sync the drawing.
- No new physical-tablet drawing test was performed for this release.

| Input / mode | SVG elements | File MiB | Path-data bytes |
| --- | ---: | ---: | ---: |
| apple-rgb | 3,452 | 3.77 | 3,460,109 |
| apple-shadow | 3,504 | 2.93 | 2,562,961 |
| apple-uniform | 144 | 9.20 | 9,627,907 |
| pear_and_pitcher-rgb | 3,906 | 5.32 | 5,012,593 |
| pear_and_pitcher-shadow | 3,751 | 3.37 | 2,989,788 |
| pear_and_pitcher-uniform | 135 | 9.44 | 9,887,577 |
| shell-rgb | 3,942 | 3.18 | 2,769,790 |
| shell-shadow | 3,857 | 2.29 | 1,850,189 |
| shell-uniform | 291 | 5.84 | 6,089,411 |

---

# Earlier validation — 0.13.0 / player 0.15

Circular scribbles now use broader loops and optional tone-dependent widths. Host verification on Apple silicon; physical BOOX display behavior has not been rechecked for this release.

- 104 Swift release tests passed, including width/geometry continuity, SVG byte counts, RGB alternation, uniform-pen mode, and saturated full-resolution color budgets.
- 35 Android unit/graphics tests passed; the optional live-Mac transfer fixture was skipped. Tests cover width parsing and rejection of invalid ratios, no lift at connected width changes, visible thickness, resize, restart, and pen-width changes. The 25 standalone playback checks passed.
- Android lint/build passed. The Mac app was rebuilt and its ad-hoc signature verified.
- Native UI verified version 0.13.0 build 14, the larger loop controls, shadow-width option, bundled shell generation, and Test the draw. The shell contains 81 actual pen strokes; its thousands of width runs do not add pauses.
- Nine original-size circular SVGs below fit the existing BOOX import limits. Exact export-size estimates matched the serialized SVGs. Old fine-loop examples remain in the comparison gallery.

| Input / mode | SVG elements | File MiB | Path-data bytes |
| --- | ---: | ---: | ---: |
| apple-rgb | 3,388 | 3.98 | 3,690,851 |
| apple-shadow | 3,622 | 3.06 | 2,684,699 |
| apple-uniform | 81 | 9.69 | 10,151,897 |
| pear_and_pitcher-rgb | 3,564 | 5.55 | 5,306,560 |
| pear_and_pitcher-shadow | 4,189 | 3.55 | 3,118,661 |
| pear_and_pitcher-uniform | 7 | 9.84 | 10,314,745 |
| shell-rgb | 3,726 | 3.34 | 2,963,493 |
| shell-shadow | 4,451 | 2.48 | 1,959,937 |
| shell-uniform | 63 | 6.01 | 6,291,149 |

Use BOOX player 0.15 for variable-width playback, then regenerate and sync sketches from Mac 0.13. Existing library entries are immutable snapshots. Production signing, physical-tablet checks, and GitHub publication remain pending.

---

# Earlier validation — 0.12.0 / player 0.14

Verified on a local Apple silicon Mac with Swift 6 and JDK 21. These are host checks, not a physical BOOX certification.

- 100 Swift release tests passed.
- 32 Android unit/graphics cases and 25 standalone playback checks passed; Android lint has no errors.
- Actual Mac HTTP library: one selected shell SVG downloaded, parsed by the Android player, and reopened offline. An empty selection also downloaded and reopened correctly. Unit tests separately cover failure preservation and managed removal.
- Native app UI: version/build visible; bundled shell loaded; RGB alternation and frequency appeared; generated artwork saved to the library; rename and availability controls worked.
- Fresh Mac bundle verified with codesign. Public source is assembled from an explicit allowlist and checked for unapproved media, local paths, pairing addresses, and signing material.

## Original-size still-life checks

Generated from the bundled shell, apple, and pear/pitcher inputs in black ink, with automatic settings. SVG limits: 20,000 elements, 28,000,000 path-data bytes, 32 MiB total. Figures below describe these examples, not every possible photo/settings combination.

| Input | Style | SVG elements | File MiB | Path-data bytes |
| --- | --- | ---: | ---: | ---: |
| Shell | Form sketch | 8,392 | 16.17 | 16,037,435 |
| Shell | Circular scribbles | 242 | 9.94 | 10,395,613 |
| Shell | Continuous sketch | 96 | 13.24 | 13,871,137 |
| Shell | Tonal cross-hatching | 10,417 | 9.92 | 9,256,797 |
| Shell | Stipple dots | 17,989 | 1.63 | 0 |
| Shell | 3D poly | 4,175 | 0.48 | 0 |
| Apple | Form sketch | 10,253 | 22.45 | 22,416,085 |
| Apple | Circular scribbles | 140 | 19.95 | 20,900,438 |
| Apple | Continuous sketch | 81 | 19.97 | 20,926,871 |
| Apple | Tonal cross-hatching | 16,002 | 16.83 | 15,891,757 |
| Apple | Stipple dots | 17,994 | 1.63 | 0 |
| Apple | 3D poly | 4,535 | 0.53 | 0 |
| Pear and pitcher | Form sketch | 10,822 | 23.47 | 23,415,958 |
| Pear and pitcher | Circular scribbles | 151 | 19.58 | 20,517,004 |
| Pear and pitcher | Continuous sketch | 23 | 23.45 | 24,589,736 |
| Pear and pitcher | Tonal cross-hatching | 18,687 | 18.05 | 16,872,757 |
| Pear and pitcher | Stipple dots | 18,002 | 1.63 | 0 |
| Pear and pitcher | 3D poly | 4,225 | 0.49 | 0 |

## Remaining release work

Physical BOOX refresh/ghosting, multi-hour playback, public signing/notarization, and a fresh GitHub Actions run remain to be verified. Library synchronization is user-initiated on the tablet. GitHub publication has not been performed.

## Mac 0.14.1 — library transfer diagnosis

Confirmed BOOX player 0.17 is installed and retains the paired Mac identity. Its library cache was absent; the existing canvas drawing had been imported manually. The Mac library contained five selected sketches, but sharing was off. Enabling sharing restored the USB reverse connection on port 48765 alongside Inkwell's unchanged port 9110.

The Mac now remembers an explicit sharing choice across relaunch. Startup restores sharing only after the saved catalog loads; internal listener shutdown or failure does not erase the preference. The library labels distinguish sketches saved on the Mac from those downloaded by BOOX. Release build and code-signature verification passed. Download completion is recorded separately when verified; pairing alone is not proof of delivery.

Device transfer subsequently completed: all five selected sketches (90.4 MB total) are present in the BOOX's active offline snapshot. Each downloaded file's byte length and SHA-256 matched both the downloaded manifest and the Mac catalog. Inkwell's USB mapping remains present. The currently running Mac session was preserved; the built 0.14.1 app takes effect on next reopen. Its sharing preference is saved as enabled to match the user's current session.

## Mac 0.15.0 — photo crop

Added rectangular cropping against the full imported photo, automatic workspace fitting, and Reset crop. Applying a crop clears the previous generated drawing and playback plan before regenerating when automatic optimization is enabled. The source file and existing library snapshots remain unchanged.

All 111 Swift tests passed, including crop color/position/orientation preservation, full-photo restoration, clipped bounds, and invalid/tiny rectangles. Release packaging and local signature verification passed. In an isolated app instance, cropped the shell from 1254 × 1254 to 1165 × 832 and visually verified the enlarged fitted canvas matched the selection. Reopening retained the selection, Cancel preserved the applied crop, and Reset crop restored 1254 × 1254.

## Mac 0.16.0 — sequential drawings

Added a saved gallery playlist with ordering, per-transition timing, accelerated previews, scrubbing, looping, and a separate full-screen-capable presentation window. All source strokes retain their positions; the compositor preserves common RGB coverage and erases individual paths without cutting neighbouring paths at crossings. Gallery SVG parsing accepts the app’s bounded path/circle/polygon format and rejects external declarations and unsupported geometry.

All 118 Swift tests passed. New checks cover RGB and variable-width SVG round trips, stroke scheduling, exact rendered endpoints across different aspect ratios, last-to-first continuity, shared/crossing ink preservation, invalid input rejection, filled styles, and playlist serialization. Full-detail apple and shell fixtures retained 10,552 and 7,913 strokes; parsing the pair took 4.45 seconds, and 1,280 × 720 frames took 65–103 ms on the development Mac.

In an isolated native app, added the apple and shell from the gallery, changed the apple transition to 30 minutes, moved it after the shell, and verified the 90-minute total and saved settings. Played at 120×, advanced to the return transition, opened the presentation window, entered full screen, and returned to the playlist. Release packaging and local code-signature verification passed. This verifies Mac playback; no physical TV playback or hour-long soak test was performed.

## Mac 0.17.0 — color and display workspace

Added 12/24-color photo palettes and locally sampled full-color stroke runs. Color boundaries preserve connected geometry and widths; SVG, PNG, gallery thumbnails, draw simulation, the sample renderer, and sequential playback retain colors. Added E-ink, E-ink RGB, TV, Monitor, and Pen plotter presets, remembered destination selection, grouped inspector cards, persistent generation controls, and disabled painting placeholders. Bundled twelve additional generated object references with their prompts, for sixteen samples total.

All 125 Swift tests passed. New coverage checks palette size/determinism, full-color geometry and width preservation, continued strokes, exact SVG size, sequential parsing, dot/facet colors, display defaults, optimization mode retention, and gallery entries excluded from tablet manifests. Screen stipple previews fill dots; tablet previews retain outline behavior.

In an isolated packaged app, selected TV, verified full-color defaults and the sixteen-item sample menu, generated the butterfly reference, inspected its native colored preview, and ran Test the draw without tablet settings or warnings. Saved the 23.7 MB colored artwork to Gallery and verified its tablet availability remained false. Generated and saved its 12-color version, then loaded both large colored SVGs into Sequential drawings successfully. Release packaging and local signature verification passed. Public TV deployment and physical e-ink color accuracy were not tested.
