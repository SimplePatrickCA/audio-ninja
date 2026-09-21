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

1. Export a **Developer ID Application** certificate as a `.p12`.
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
  requires and what dynamic linking would take.

## iOS

Nothing is published for iOS. An unsigned `.ipa` cannot be installed, so distribution
means TestFlight or the App Store, which needs the same Developer ID work above plus an
App Store Connect record. CI builds for iOS devices and the simulator on every change,
so the platform stays honest; it is only the distribution step that is absent.
