# Releasing

1. Work from this clean repository, not a personal experimentation folder. Run `python3 scripts/check_publication.py` before uploading any source archive.
2. Run both applications' checks in the root README. Regenerate and inspect approved still-life comparisons. CI is configured but must also pass on GitHub after the repository exists.
3. Update `squiggle-draw/version.env` and Android's version fields. The Mac build creates a fresh app bundle and verifies its ad-hoc signature before replacing local artifacts.
4. Build the Mac ZIP and Android APK. Test importing, color alternation, polygon filling, library selection, failed sync, offline reopening, and synchronization on an actual BOOX. Do not claim device-tested behavior from host tests alone.
5. For a public Mac binary, arrange Developer ID signing and notarization with the maintainer's credentials. For a stable Android release, use a private release keystore; never commit the keystore or passwords. The current scripts produce local test builds.
6. Create a GitHub repository and push this source only when the owner chooses the account, repository name, and visibility. Attach verified binaries to a release. No deployment or repository creation is performed by these scripts.
7. To publish the included gallery, configure GitHub Pages to serve `docs` from the main branch. The gallery is plain local HTML/CSS with no tracking or remote scripts.

No account credentials, signing certificates, or CI secrets are required to run source tests. The Android build retrieves declared dependencies from official repositories on a fresh machine.
