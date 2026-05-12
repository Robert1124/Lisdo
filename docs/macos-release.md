# macOS Release Packaging

Lisdo publishes Developer ID macOS builds through `.github/workflows/macos-release.yml`.
The workflow runs for `v*` tags or manual dispatch, archives the `LisdoMac`
scheme, validates the Developer ID signature, notarizes the app and DMG,
staples both artifacts, generates the Mac appcast, uploads release assets to
GitHub Releases, publishes the release, and commits the generated appcast to
`Website/appcast.xml` on the repository default branch. Cloudflare Pages then
deploys the website from that repo push.

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

No Cloudflare credentials are required. The Mac app reads
`https://lisdo.robertw.me/appcast.xml` from `SUFeedURL`, and that file is
published from this repository's `Website/appcast.xml` by Cloudflare Pages.

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
- `appcast.xml`

The temporary app zip used for notarization is an implementation detail and is
not uploaded as a release asset.

## Appcast Deployment

After the notarized DMG is stapled and the checksum is refreshed, the workflow
generates `dist/release/appcast.xml` with
`script/generate_mac_appcast.py`. The appcast contains one latest-release item
with the GitHub Release URL, DMG download URL, DMG byte length,
`sparkle:shortVersionString`, and `sparkle:version`. The build value is
`GITHUB_RUN_NUMBER`, matching the archive's `CURRENT_PROJECT_VERSION`.

The workflow then uploads the appcast as a GitHub Release asset and runs
`gh release edit` to publish the release. After the release is public, the
workflow preserves the generated XML in `$RUNNER_TEMP/generated-appcast.xml`,
checks out the repository default branch, copies it to `Website/appcast.xml`,
and commits only that file if the contents changed. Pushing that commit lets
Cloudflare Pages publish `https://lisdo.robertw.me/appcast.xml` through the
normal website deployment.

The same `appcast.xml` is also uploaded as a workflow artifact with the DMG and
checksum so each Actions run keeps the exact generated feed.

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
