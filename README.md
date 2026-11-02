# MyTube Music

A small Flutter shell for YouTube Music. Uses the existing WebView dependency;
no audio downloads, transcoding, or separate streaming backend.

## Features

- Search songs, artists, and albums.
- Listen, Explore, and account library navigation.
- Compact previous/play/pause/next controls synchronized with page media.
- Loading feedback and connection error recovery.
- Best-effort ad request blocking and skip-button handling, without changing
  song volume or playback speed.

YouTube controls stream quality and account entitlements. Select the highest
available quality in YouTube Music settings. Ad-free listening, background
playback, and lock-screen controls are not guaranteed by this wrapper. Library
requires a supported YouTube sign-in; embedded-browser sign-in may be restricted.

## Development

Use a current stable Flutter SDK (the source uses
`PopScope.onPopInvokedWithResult`) and Android SDK. This checkout contains partial
native scaffolding. Generate a disposable project outside the checkout rather
than running the destructive regeneration commands in CI against local changes:

```sh
flutter create --org com.custom.ytadfree --project-name adfree_youtube --platforms=android /tmp/mytube-dev
cp pubspec.yaml /tmp/mytube-dev/pubspec.yaml
cp lib/main.dart /tmp/mytube-dev/lib/main.dart
cp android/app/src/main/AndroidManifest.xml /tmp/mytube-dev/android/app/src/main/AndroidManifest.xml
cd /tmp/mytube-dev
rm test/widget_test.dart
flutter pub get
flutter analyze
flutter build apk --debug
flutter run
```

Refresh the copied source after edits. iOS builds require macOS and Xcode.

## Device verification

Search for a song, start it, verify title and pause/play synchronization, then
check next/previous with a populated queue. Confirm library navigation and back
history. Disconnect networking and check retry recovery. Check that skipping an
ad does not mute or accelerate the following song. Test screen lock, background
playback, and picture-in-picture on each supported OS; configuration alone does
not establish that these work. Confirm quality using YouTube's available settings.

The cloud machine used for this change did not have Flutter/Dart installed;
Flutter analysis, APK builds, and device playback remain unverified.

## Windows PC

Windows support uses Microsoft Edge WebView2 through flutter_inappwebview 6.1.5.
Target: Windows 10/11, x64. Install the Evergreen WebView2 Runtime from Microsoft:
https://developer.microsoft.com/microsoft-edge/webview2/

For a packaged build, run the **Build Windows Music App** workflow in GitHub
Actions after pushing these changes. Download its artifact, extract the inner
`MyTube-Music-Windows-x64.zip` completely, and run `adfree_youtube.exe`.
Keep the executable, DLLs, and `data` directory together. This is a portable,
unsigned build; no installer or signing certificate is included. The workflow
has been added but has not been executed from this Linux workspace.

To build on your Windows PC, install Flutter 3.24.5 (or a compatible newer stable
version), Visual Studio 2022 with **Desktop development with C++** and the Windows
SDK, and the NuGet CLI on PATH. Run `flutter doctor -v` to check the toolchain.
From the repository root in PowerShell:

```powershell
./scripts/build-windows.ps1 -Run
```

The script generates a fresh Windows runner in a unique temporary directory,
copies the app source and manifest, analyzes it, builds the release app, and
writes `artifacts/MyTube-Music-Windows-x64.zip`. It retains the temporary project
for diagnosis. Generated files do not overwrite your source checkout.
Cookies and browser settings live in `%LOCALAPPDATA%/MyTubeMusic/WebView2`.
Close the app before deleting that folder to reset browser state (including login).

Validate on Windows: launch the extracted package, search and play a song, check
pause/next/previous, resize and minimize the window, reopen to check browser
persistence, and verify connection-error recovery. Windows playback and packaging
have not yet been validated on a Windows machine. Mobile picture-in-picture
settings do not guarantee Windows picture-in-picture or playback during PC sleep.

## Background playback

On Android or Windows, start a song, then turn on **Background playback** above
the player. The setting lasts for the current app session and defaults to off.

- Android: the option starts a media-playback foreground service with an ongoing
  notification (allow notifications when prompted) and a partial CPU wake lock (the screen can still turn off). Turn
  the option off when finished to release the lock and stop the service. Removing
  the app from recent apps stops the service; force-stop or OS process termination
  ends playback. The notification opens the app to manage the option. Keeping the
  service enabled while paused still uses background resources.
- Windows: the option suppresses website visibility-based pauses. In Windows
  **Settings → System → Power & battery → Screen and sleep**, allow the display to
  turn off but prevent the PC from sleeping while listening. This does not enable
  playback during sleep, hibernation, or shutdown.
- iOS: this switch is not exposed; dependable iOS background playback has not been
  implemented or verified.

Both platforms retain the WebView as the audio source. Website/account limits,
WebView behavior, and manufacturer battery policies can still interrupt playback;
this is not a separate native streaming engine. Test on the target device before
relying on screen-off playback.

For local Android builds, after generating the temporary project described above,
copy `platform/android/*.kt` into
`android/app/src/main/kotlin/com/custom/ytadfree/adfree_youtube/` in that project,
replacing the generated `MainActivity.kt`. Copy the repository Android manifest
as well. The GitHub APK workflow performs these steps automatically.

Validation: `node test/background_playback_test.cjs` checks that the visibility
handling enables, disables, and installs once. On a device, start a song, enable
background playback, lock the screen for several minutes and across a track
change, then unlock and disable it. Check that the notification disappears and
play/pause still works. Repeat with the option off and after removing the app
from recent apps. Actual device playback and native builds remain unverified in
this Linux environment.
