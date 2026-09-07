# Distribute a pet

## Source distribution

Source is the recommended public download. Fork this repo or use it as a GitHub template, make your changes, and share the repository link or **Code → Download ZIP**. The checked-in Xcode project and vendored SwiftTerm source make the checkout self-contained. Users still need full Xcode on a compatible Mac to build.

From a committed, tested checkout you can produce a clean source ZIP:

```sh
mkdir -p dist
git archive --format=zip --prefix=Pet/ --output=dist/Pet-Starter-Source.zip HEAD
```

`git archive` includes committed files only. Review `git status` first so your intended changes are included. It excludes local preferences, Derived Data, credentials, and terminal history because those files are not part of the repository.

## Local app package

```sh
./scripts/test.sh
./scripts/package.sh
```

This creates `dist/Pet-Terminal-macOS.zip`. The build is universal (Apple Silicon and Intel) and signed with a local ad-hoc identity. Packaging excludes extended attributes and resource forks that can invalidate the bundle signature when files pass through synced folders.

The supplied scripts do **not** produce a notarized public binary. They do not request your Apple credentials or disable Gatekeeper. A downloaded prebuilt app may be blocked by macOS; building the source locally is the supported default route. A maintainer who wants normal public binary distribution should add their own Developer ID signing and notarization workflow, following [Apple's Developer ID guidance](https://developer.apple.com/developer-id/) and [notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Give a fork its own app identity

The simplest customization changes only `Resources/pet.json` and the artwork, keeping the app named **Pet Terminal**. For a separately branded app:

1. Change product/bundle names, the bundle identifier, and copyright metadata in `project.yml`.
2. Update `PET_PRODUCT` and `PET_SCHEME` in `scripts/common.sh` if the product or scheme changes.
3. Update scheme/module references in tests, scripts, workflow, and documentation where needed.
4. Replace `Resources/AppIcon.icns` and update asset credits.
5. Run `xcodegen generate` and commit the generated Xcode project with the manifest.
6. Validate, test, build, inspect, and package that exact revision.

Different bundle identifiers give installed pets separate preferences. The installer refuses to overwrite an unrelated app that happens to have the same filename, and refuses to install while Pet Terminal is running. It saves replaced app bundles beneath the configured build directory for rollback.

## Before publishing

- Confirm the exact source checkout builds and tests on a Mac.
- Review the pet at normal size and in all four cardinal gaze directions. Test the real terminal, not only its appearance.
- Check the Git diff for private paths, keys, certificates, account data, transcripts, and build products.
- Keep `LICENSE`, `THIRD_PARTY_NOTICES.md`, and upstream notices intact. Include credits and permissions for any replacement artwork.
- Report actual architecture/runtime coverage and whether a binary is notarized.

The GitHub Actions workflow runs validation, native tests, and a Release build. It uploads an ad-hoc app ZIP as a CI artifact for inspection; it does not publish a release or manage signing credentials.
