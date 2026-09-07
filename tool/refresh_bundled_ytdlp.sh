#!/usr/bin/env bash
# Refresh the yt-dlp binary bundled in the APK's Android assets
# (android/app/src/main/assets/ytdlp/). YtDlpCore installs this on first
# run when it's newer than what youtubedl-android unpacked, so a fresh
# install isn't stuck on the months-old binary vendored inside the
# youtubedl-android AAR until the runtime self-update succeeds.
#
# Run this before every release build (see RELEASE.md), then commit the
# two changed files.
set -euo pipefail

dest="$(cd "$(dirname "$0")/.." && pwd)/android/app/src/main/assets/ytdlp"
mkdir -p "$dest"

tag="$(curl -fsSL https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest \
  | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 \
  | sed -E 's/.*"([^"]+)"$/\1/')"
[ -n "$tag" ] || { echo "could not resolve latest yt-dlp tag" >&2; exit 1; }

echo "latest yt-dlp: $tag"
curl -fSL "https://github.com/yt-dlp/yt-dlp/releases/download/$tag/yt-dlp" \
  -o "$dest/yt-dlp"
printf '%s' "$tag" > "$dest/version"

echo "wrote $dest/yt-dlp ($(wc -c < "$dest/yt-dlp") bytes)"
echo "wrote $dest/version = $tag"
