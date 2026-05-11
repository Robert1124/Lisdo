# macOS Release Packaging

Lisdo publishes Developer ID macOS builds through `.github/workflows/macos-release.yml`.
The workflow runs for `v*` tags or manual dispatch, archives the `LisdoMac`
scheme, validates the Developer ID signature, notarizes the app and DMG,
staples both artifacts, and uploads the DMG plus SHA-256 checksum to GitHub
Releases.

## Required GitHub Secrets

- `APPLE_TEAM_ID`
- `DEVELOPER_ID_APPLICATION`, for example `Developer ID Application: Name (TEAMID)`
- `DEVELOPER_ID_CERTIFICATE_BASE64`, a base64-encoded `.p12`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `DEVELOPER_ID_PROVISIONING_PROFILE_BASE64`, a base64-encoded Developer ID profile for `com.yiwenwu.Lisdo.macOS`
- `NOTARY_KEY_ID`
- `NOTARY_ISSUER_ID`
- `NOTARY_PRIVATE_KEY_BASE64`, a base64-encoded `AuthKey_*.p8`

The macOS app currently uses iCloud, app groups, and Keychain access groups.
Those entitlements require a Developer ID provisioning profile for CI signing.
Export the LisdoMac Developer ID profile from the Apple Developer portal and
store it in `DEVELOPER_ID_PROVISIONING_PROFILE_BASE64`.

Useful local encoding commands:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i LisdoMac.provisionprofile | pbcopy
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

## Triggering a Release

Push a version tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Or run **macOS Release** manually from GitHub Actions and provide a `v*`
version string. The workflow publishes or updates the matching GitHub Release.

## Release Assets

Official macOS releases should attach:

- `Lisdo-<version>.dmg`
- `Lisdo-<version>.dmg.sha256`

The temporary app zip used for notarization is an implementation detail and is
not uploaded as a release asset.

## Local Dry Run

You can verify the unsigned build path locally with:

```bash
xcodegen generate
swift test --package-path Packages/LisdoCore
xcodebuild -project Lisdo.xcodeproj -scheme LisdoMac -configuration Release -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

The packaging script also supports a local ad-hoc DMG smoke test with
`script/package_mac_release.sh --allow-ad-hoc` after you have staged and
ad-hoc-signed a local `Lisdo.app`.

Full Developer ID signing and notarization are expected to run in GitHub
Actions after the repository secrets above are configured.
