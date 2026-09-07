# SwiftTerm

Source: https://github.com/migueldeicaza/SwiftTerm

Tag: v1.20.0, commit 5d14406844143538cd8f8851d2d8a67c1fe443e5.

The Sources/SwiftTerm directory is copied from that revision, with the local change listed below. The local package manifest builds only the macOS library. Unrelated command-line apps, benchmark and documentation dependencies, and the Git build-metadata generator are not included. SwiftTermBuildInfo.swift supplies the pinned upstream identity without running an Xcode build plug-in. The MIT license is included.

## Local privacy patch

The unused `Buffer.dump()` helper and its commented-out call are removed. The helper contained an upstream developer’s absolute home path and code to write terminal contents there. It was not called by this app. No copyright or license attribution was removed. Clipboard protection is implemented in the app’s `TerminalOutputPolicy`, outside the vendored library.
