# Releasing AnyWhere Downloader

The app has no backend and is sideloaded as a direct APK, so a release is
just a **GitHub Release with the split APKs attached**. The in-app updater
(Settings → About → *Check for updates*) polls the repo's `releases/latest`
and compares the tag against the bundled version.

## One-time setup

1. Create a **public** GitHub repo (GPL-3.0 — the code is open anyway).
2. `git remote add origin git@github.com:<owner>/<repo>.git && git push -u origin main`
3. Set the repo slug the app checks: edit `kUpdateRepoSlug` in
   `lib/core/update/update_service.dart` to `'<owner>/<repo>'`. While it is
   the literal `OWNER/REPO` placeholder the update check is inert (always
   reports "up to date").

## Per release

1. **Bump the version** in three places, together:
   - `pubspec.yaml` → `version: X.Y.Z+N` (bump `+N` every build).
   - `lib/core/changelog/changelog.dart` → `kAppVersion` **and** a new
     top entry in `kChangelog` (newest first), notes localized EN/RU/KK.
   - `CHANGELOG.md` → mirror that entry (`## X.Y.Z — YYYY-MM-DD` with
     `### English` / `### Русский` / `### Қазақша`).
2. `flutter analyze` (clean) and `flutter test` (green).
3. Build the split release APKs:
   ```
   flutter build apk --release --split-per-abi
   ```
   Output: `build/app/outputs/flutter-apk/`
   - `app-arm64-v8a-release.apk`
   - `app-armeabi-v7a-release.apk`
   - `app-x86_64-release.apk`
   (`llvm-strip … not recognized as a valid object file` on the
   `*.zip.so` files is expected — see CLAUDE.md.)
4. Confirm the signing key is the real one, not the debug key:
   ```
   JAVA_HOME="C:/Program Files/Android/Android Studio/jbr" \
   "$LOCALAPPDATA/Android/sdk/build-tools/<ver>/apksigner.bat" \
     verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
   ```
   Expect `CN=AnyWhereDownloader`.
5. `git commit`, `git tag vX.Y.Z`, `git push --tags`.
6. Create the GitHub Release for tag `vX.Y.Z`:
   - Title `vX.Y.Z`, body = the English changelog notes (this becomes the
     "What's new" text the in-app update sheet shows).
   - **Attach all three APKs** as release assets, with the exact filenames
     above — the updater matches an asset by the device ABI token in its
     name (`arm64-v8a` etc.).
   - Mark it the *latest* release (GitHub does this for the newest
     non-prerelease tag automatically).

## Notes

- The updater only offers an update whose APK is signed with the **same
  key** as the installed app — Android refuses a differently-signed update.
  Always release-sign (step 4).
- Tag format: `vX.Y.Z` or `X.Y.Z` both work (the app strips a leading `v`).
- A release with no APK asset for the user's ABI shows "No compatible
  download for this device" and offers the release page instead.
