# Contributing

Keep each change focused and include a reproducible input. Use the bundled generated samples or synthetic rasters in tests. Never commit personal photos, private SVGs, device pairing addresses, signing keys, local SDK paths, build caches, or exported libraries.

Before a pull request:

1. Run the Swift release tests and build the app for Mac changes.
2. Run Android unit tests, lint, and the plain Java playback checks for player changes.
3. For rendering changes, regenerate the same approved sample with the same seed before and after. Inspect highlights, contours, tone, path continuity, and early drawing progress. A lower path count alone is not a quality improvement.
4. Verify SVG order agrees with Test the draw and the player. Preserve single-pen exports when adding color passes.
5. Update user-facing documentation and the version only for a release, using `squiggle-draw/version.env` and Android's `app/build.gradle`.

Tests live beside each application's source tree. Swift core functions accept validated rasters and parameters, are deterministic for a fixed seed, and must support cancellation and bounded output sizes. Network changes require negative tests for malformed input, authentication, failed transfers, and preservation of offline data.

Pull request descriptions should explain the problem, resulting behavior, and validation. Include sample preview changes when they help assess quality. Do not include private local paths or personal artwork.
