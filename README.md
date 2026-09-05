# AnyWhere Downloader

An Android app for saving videos and media to your device from a link you paste
(or one it picks up from the clipboard).

## Supported sources

- **YouTube** — video, up to high resolution (video/audio are merged on-device); pause/resume and a progress notification.
- **TikTok** — video (HD/SD).
- **X (Twitter)** — post video.
- **Instagram** — reels and posts.
- **WhatsApp** — statuses you have already viewed, read from the local status cache via the Storage Access Framework (no network, no login).

Everything downloaded is collected in the **Library** tab (grouped by source, with sorting, multi-select, sharing and delete) and saved to the device gallery.

## Notes

- Android only, minimum Android 12 (API 31). Distributed as a direct APK, not through Google Play.
- No accounts or authentication anywhere in the app.
- Extraction runs on-device (via a bundled [yt-dlp](https://github.com/yt-dlp/yt-dlp) engine) for every source except TikTok, which uses a third-party public API.
- UI languages: English, Russian, Kazakh.

## Legal

This tool is intended for downloading content you own or have permission to
download. Respect the terms of service of each platform and the rights of content
creators. The authors take no responsibility for misuse.

## Build

```
flutter pub get
flutter build apk --release --split-per-abi
```

Release signing expects `android/key.properties` + `android/keystore/` (both
gitignored); without them the build falls back to the debug key.
