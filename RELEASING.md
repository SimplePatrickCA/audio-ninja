# Releasing

## Cutting a release

```bash
git tag v1.0.0
git push origin v1.0.0
```

`.github/workflows/release.yml` then runs the logic tests, builds the macOS app in
Release, ad-hoc signs it, zips it with `ditto`, and creates a GitHub Release with the
zip and its SHA-256 attached. The tag name minus the leading `v` becomes
`MARKETING_VERSION`, and the workflow run number becomes `CURRENT_PROJECT_VERSION`,
so the bundle's version always matches the release it came from.

To exercise the pipeline without spending a version number, run the workflow manually
from the Actions tab with a `version` input. That does everything except create the
release: the zip lands as a workflow artifact instead.

## What the artifact is, and is not

The published app is **ad-hoc signed** (`codesign -s -`), not signed with a Developer ID
and not notarized. Apple silicon refuses to execute a wholly unsigned binary, so ad-hoc
is the floor, not a choice — but it is not enough for Gatekeeper, which is why the
release notes tell people to clear the quarantine attribute.

It is built without the hardened runtime. The runtime's library validation only loads
frameworks signed by the same team as the app, and an ad-hoc app has no team, so it
would refuse the embedded `LAME.framework` and the app would not launch.

It is also arm64-only. macOS 27 dropped Intel support, so there is no second slice to build.

## Making it open without the quarantine dance

This needs an Apple Developer account, and it is the only part of publishing that
cannot be done from what is in this repo:

1. Export a **Developer ID Application** certificate as a `.p12`. Keep it out of the repo;
   `.gitignore` already refuses `*.p12`, `*.cer`, provisioning profiles and `AuthKey_*.p8`.
2. Add repository secrets: the base64 of the `.p12`, its password, the team ID, and an
   App Store Connect API key (or an app-specific password) for notarization.
3. In `release.yml`, import the certificate into a temporary keychain, swap
   `CODE_SIGN_IDENTITY="-"` for `"Developer ID Application"` with `DEVELOPMENT_TEAM` set,
   remove `ENABLE_HARDENED_RUNTIME=NO` (notarization requires the hardened runtime), and add `xcrun notarytool submit --wait` followed by `xcrun stapler staple` on the zip.

One thing to keep in mind, which matters more once the app is public:

- **The bundle identifier** is `com.simplepatrick.AudioNinja`, set in
  `scripts/generate-xcodeproj.py`. The signature, the document type associations and the
  user's preferences are all keyed to it, so it should not change once builds are public.

## TestFlight and the App Store

The app ships as one universal purchase: a single bundle identifier and one App Store
Connect record covering both iOS and macOS.

### Already done in the repo

- Info.plist keys App Store Connect checks for: interface orientations (iPad needs all four
  for multitasking), `UISupportsDocumentBrowser`, the scene manifest, a generated launch
  screen, `LSApplicationCategoryType` (Music, which macOS uploads require), and
  `ITSAppUsesNonExemptEncryption = NO`. The app uses no encryption beyond what the OS
  provides, so each upload can skip the export-compliance question.
- `AudioNinja/PrivacyInfo.xcprivacy`: no tracking and no data collected. It declares
  UserDefaults (reason `CA92.1`) for the one display preference. In App Store Connect the
  privacy label is **Data Not Collected**.
- The App Sandbox entitlements apply to macOS only. An iOS binary carrying them is rejected.
- The iOS icon has no alpha channel, which App Store Connect rejects even when the image is
  fully opaque. `scripts/generate-app-icon.sh` strips it.
- One third-party library ships: LAME (LGPL), as the embedded dynamic `LAME.framework`,
  credited with its full licence under Acknowledgements in the app. See
  [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md), including what is not settled about
  LGPL code on the App Store.

### Still needed, and only you can do it

1. **Register one iPhone or iPad with the team** (connect it to this Mac with Xcode open,
   or add its UDID under Certificates, Identifiers & Profiles). Automatic signing signs an
   archive with a development profile first and switches to distribution at upload, and
   Xcode cannot make a development profile for a team with no devices. Until then the
   iOS archive fails with "Your team has no devices". The Mac archive is unaffected.
2. **Keep the bundle identifier and team in the generator.** They are
   `com.simplepatrick.AudioNinja` and team `XJ77XT4Z9Y`, set as `BUNDLE_ID` and `TEAM_ID` in
   `scripts/generate-xcodeproj.py`. The identifier is permanent once a build is uploaded.
   The generator writes the project exactly as Xcode saves it, so changing a setting in
   Xcode's editor is fine, but copy the change into the generator or CI's drift check fails.
3. **Create the App Store Connect record** with that identifier, and fill in the name,
   privacy policy URL, category and age rating. TestFlight external testing also needs beta
   review information: a contact and a description of what to test.
4. **Archive and upload.** Bump `CURRENT_PROJECT_VERSION` in
   `scripts/generate-xcodeproj.py` (every upload needs a higher build number than the last
   one for its platform), regenerate, commit, then run `scripts/upload-app-store.sh`. It
   runs the logic tests, archives both platforms, and uploads them with the Apple account
   signed in to Xcode, using exactly the build number in the project. Pass `iOS` or
   `macOS` to upload one platform. Xcode's Organizer works too: archive with *Any iOS
   Device* and with *My Mac*, then Distribute App ▸ App Store Connect.

   | Build | Platforms | Notes |
   |---|---|---|
   | 1 | iOS, macOS | First upload, from Xcode |
   | 2 | macOS | From Xcode |
   | 3 | iOS, macOS | iPhone layout fix (controls overflowed the screen) |
   | 4 | iOS, macOS | One document type, MP3 read-only (build 3 crashed in SwiftUI's document cast on iOS) |
   | 5 | iOS, macOS | MP3 editing and export, through LAME (LAME-xcframework 3.100.3) |
   | 6 | iOS, macOS | Time labels on the cursor and selection; the original shown above the waveform after a cut |
   | 7 | iOS, macOS | Show Separate Channels responds to the first tap on iOS (the bar's interactive glass took it) |
5. Upload with the **release** Xcode 27, not a beta. App Store Connect refuses builds from
   beta toolchains.

Automating the upload in CI would need the same certificate secrets as the Developer ID
section above, plus an App Store Connect API key, and `xcodebuild -exportArchive` with
`method = app-store-connect`. It is not set up.
