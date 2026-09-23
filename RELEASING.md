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
   and add `xcrun notarytool submit --wait` followed by `xcrun stapler staple` on the zip.

Two things to fix at the same time, both of which matter more once the app is public:

- **The bundle identifier is still `com.example.AudioNinja`**, set in
  `scripts/generate-xcodeproj.py`. It needs to be a real reverse-DNS identifier you own
  before anything is signed with a Developer ID, because the identifier is what the
  signature, the document type associations and the user's preferences are all keyed to.
- **LAME is statically linked.** While this repo is private, a release is visible only to
  collaborators and little turns on it. Publishing binaries publicly makes LGPL §6 apply.
  Read [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md), which spells out what that
  requires.

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
- LAME is credited in-app, with the full LGPL text, under **Acknowledgements**.

### Still needed, and only you can do it

1. **Choose the bundle identifier.** It is still `com.example.AudioNinja`, set as
   `BUNDLE_ID` in `scripts/generate-xcodeproj.py`. Change it, run the script, and commit
   the regenerated project. Once a build is uploaded the identifier is permanent for that
   App Store record.
2. **Set the team.** Signing is Automatic, but no `DEVELOPMENT_TEAM` is committed. Pick the
   team under Signing & Capabilities in Xcode, or add `DEVELOPMENT_TEAM` to `APP_SETTINGS`
   in the generator.
3. **Decide how LAME ships.** See "App Store distribution" in
   [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md). Settle this before the first upload,
   not after.
4. **Create the App Store Connect record** with that identifier, and fill in the name,
   privacy policy URL, category and age rating. TestFlight external testing also needs beta
   review information: a contact and a description of what to test.
5. **Archive and upload** from Xcode: Product ▸ Archive once with *Any iOS Device* and once
   with *My Mac*, then Distribute App ▸ App Store Connect from the Organizer. Every upload
   needs a higher `CURRENT_PROJECT_VERSION` than the one before, for the same
   `MARKETING_VERSION`.
6. Upload with the **release** Xcode 27, not a beta. App Store Connect refuses builds from
   beta toolchains.

Automating the upload in CI would need the same certificate secrets as the Developer ID
section above, plus an App Store Connect API key, and `xcodebuild -exportArchive` with
`method = app-store-connect`. It is not set up.
