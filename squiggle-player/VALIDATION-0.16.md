# Validation — Mac 0.14.0 / BOOX 0.16

- 108 Swift release tests passed; Mac app build and ad-hoc signature verification passed.
- 39 Android unit/graphics tests passed, with one optional live-Mac fixture skipped; Android build and lint passed. New tests cover cable preference, Wi-Fi fallback after timeout, wrong-library rejection before commit, valid USB pairing, and invalid pairing preserving saved settings.
- Installed player 0.16 on the USB-connected BOOX Note Air5 C, retaining app data.
- Executed the actual Mac USBTransport pairing code against that tablet. Verified its saved Wi-Fi URL and library identity without logging the bearer token.
- The physical tablet fetched the selected Mac library manifest through both the USB reverse tunnel and its direct Wi-Fi address. Both returned the same library and two selected sketches. This checks connectivity and pairing; the user still chooses Sync now to download the sketches.
- Saved cable reconnection settings for Mac 0.14. Inkwell’s tunnel was left intact. The new Mac app must be reopened for its reconnection watcher to run.
