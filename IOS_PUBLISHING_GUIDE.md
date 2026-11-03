# Local Lekker: download on a Mac and publish for iOS

## Download the source backup

The source-only backup is on branch `backup/macos-ios-2026-11-01`:

https://github.com/locallekker/locallekker.github.io/tree/backup/macos-ios-2026-11-01

On the Mac, either select that branch on GitHub and choose **Code > Download
ZIP**, or run these commands in Terminal:

```bash
git clone --single-branch --branch backup/macos-ios-2026-11-01 \
  https://github.com/locallekker/locallekker.github.io.git local_lekker
cd local_lekker
```

This branch has no earlier Git history. It contains the current application,
platform source, tests and Supabase migrations/functions, but excludes local
credentials, database audit dumps, old snapshots and generated builds. It is
not a backup of the live database, storage uploads or server-side secrets.

## Prepare the Mac

1. Install Flutter stable, full Xcode and the CocoaPods tooling required by
   Flutter's iOS plugins. Use an Xcode/iOS SDK accepted by App Store Connect
   at submission time. The app requires Dart 3.9 or newer.
2. Launch Xcode once, install its requested components and accept its licence.
3. Have an active Apple Developer Program membership and access to the app
   in App Store Connect.
4. Run `flutter doctor -v` and resolve the iOS toolchain issues.

From the downloaded project folder:

```bash
cp .env.template .env
# Edit .env with the approved production CLIENT configuration.
flutter pub get
flutter test test/guest_browsing_test.dart \
  test/admin_guest_conversion_screen_test.dart \
  test/subscription_renewal_guard_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings lib test
```

The `.env` file is intentionally not on GitHub. The app bundles it as an asset,
so it must exist before building. Obtain the required client configuration
through a private channel. Never put a Paystack secret key, Supabase
service-role key, private certificate or other server secret into this file
or into the mobile app. Those belong in the backend's secret configuration.
Rotate any previously exposed server credentials before release.

## Current iOS preparation still required

This backup is source code, **not a verified App Store-ready IPA**. An iOS
build cannot be validated on the Windows development machine.

Before building on the Mac:

- The Xcode project currently uses the placeholder bundle identifier
  `com.example.localLekker`. Choose the registered production identifier in
  **Runner > Signing & Capabilities**, matching App Store Connect. Select your
  Apple Developer team and configure signing.
- Xcode references `ios/Runner/Base.lproj/Main.storyboard` and
  `LaunchScreen.storyboard`, but the tracked files end in `.storyboard.xml`.
  Restore the names expected by the project before building:

  ```bash
  mv ios/Runner/Base.lproj/Main.storyboard.xml \
    ios/Runner/Base.lproj/Main.storyboard
  mv ios/Runner/Base.lproj/LaunchScreen.storyboard.xml \
    ios/Runner/Base.lproj/LaunchScreen.storyboard
  ```

- No CocoaPods `ios/Podfile` is included in this snapshot. Resolve the plugin
  integration using the installed Flutter version's supported iOS setup.
  If regenerating platform files with `flutter create --platforms=ios .`,
  first keep a copy of the downloaded project, then review every generated
  change and preserve the existing app icons, URL schemes and privacy text.
  Run `flutter pub get` afterwards and, if a Podfile is present, run
  `cd ios && pod install && cd ..`.
- The existing deployment target is iOS 13.0. Check the installed plugins'
  minimum requirements and align the target and Podfile if necessary.
- Check permissions for every enabled feature, including location. Camera
  and photo-library usage descriptions are present; location descriptions
  are not currently present.
- Verify sign-in/deep links, member and partner flows, payments and
  subscription renewal on an iPhone. Push notification initialization is
  currently disabled; do not advertise background push as working.
- Apply the required backend migrations through the normal deployment
  process. Do not run database test fixtures against production.

Open the workspace after preparing dependencies:

```bash
open ios/Runner.xcworkspace
```

## Build, upload and submit

1. In App Store Connect, create or select **Local Lekker**, using the same
   registered bundle identifier as Xcode.
2. Confirm the app version in `pubspec.yaml` (currently `1.0.16+64`). Use a
   new build number if that number has already been uploaded.
3. Build a signed archive/IPA:

   ```bash
   flutter build ipa --release
   # For a later upload, use an unused number:
   # flutter build ipa --release --build-number=65
   ```

4. The signed IPA is exported into `build/ios/ipa/`. Open the archive in
   `build/ios/archive/Runner.xcarchive` with Xcode, then use **Organizer >
   Distribute App > App Store Connect > Upload**. Alternatively upload the
   exported IPA with Apple's Transporter app.
5. Wait for processing, test the build through TestFlight, and complete the
   App Store metadata, required screenshots, privacy disclosures, age rating,
   export-compliance questions and review notes. Verify that payment and
   account flows satisfy Apple's applicable review requirements.
6. Select the processed build and submit it for review. Uploading a build
   does not automatically publish the app.

## Existing GitHub Actions workflow

The existing unsigned iOS workflow is not a publishing pipeline. It does
not provide signing credentials or the required `.env` asset, and expects an
IPA from `flutter build ipa --no-codesign`. That command produces an unsigned
archive without a signed IPA export. Do not rely on this workflow for an
App Store download or submission; use the Mac signing process above.
