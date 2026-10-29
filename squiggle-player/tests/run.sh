#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
javac -d "$out" app/src/main/java/art/squiggle/player/Playback.java tests/PlaybackTest.java
java -cp "$out" art.squiggle.player.PlaybackTest
