# Validation — BOOX Squiggle 0.17

- Built and installed version 0.17 (version code 17) on the connected BOOX Note Air5 C, retaining existing app data and pairing settings.
- Android tests: 41 passed; the optional live-Mac fixture was skipped. Playback timing: 25 checks passed. Android lint: zero errors, 15 warnings for SDK/dependency versions, existing private API access, and English-only literal labels.
- New graphics test checks the complete sleep export’s RGB strokes, fills, variable widths, white margins, and unchanged source paths. New navigation test checks both the explicit return button and Android Back retain the canvas. Updated damaged-library recovery test checks its visible Pair and sync action.
- Inspected actual tablet screenshots: black bold labels, outlined buttons, larger tap areas, separate Library page, and permanent Back to canvas button. Manually verified Android Back returns from Library to the paused canvas and the drawing wake lock is released. Imported the 16.3 MB RGB Mittens SVG using the native picker.
- Exported the complete Spirograph before drawing it; BOOX displayed it as the actual sleep screen. Repeated with RGB Mittens: a 5.16 MB full-screen PNG, all four colors, and a private 16.3 MB SVG copy. BOOX's native dream service was in its dozing state during both sleep screenshots. Neither sleep image contains controls.
- Fixed Android MediaStore’s pending-file rename before passing the final filesystem path to BOOX’s documented screensaver API. The API sends a broadcast request and does not acknowledge completion; the actual displayed image was verified separately.
- Reinstalled the final build and checked cold-launch restoration of the saved RGB sleep drawing. Redraw started color playback from the beginning, and the accepted onyx_Squiggle:Drawing wake lock was held. Large path files can take tens of seconds to prepare.
- Photo selection uses Android’s image picker and scaled software decoding; the arbitrary-photo picker/decoder route has not been tested with a separate camera photo on this tablet. Photos do not contain replayable paths.
- The physical e-ink panel’s color fidelity and ghosting remain dependent on BOOX firmware and refresh settings. Direct pen behavior is unchanged and remains experimental; color playback uses Canvas.

Sleep screens are static. Wake with the physical power button, then tap Redraw in the app. Squiggle must be the foreground app for the shortest return route. If another sketch is open, Library → Open sleep drawing restores the saved sleep artwork.
