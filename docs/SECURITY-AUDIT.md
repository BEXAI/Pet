# Source and distribution audit

Audit date: **2026-09-07**. Remediation release: **v1.0.1**.

This review covers the macOS app, configuration, build/install/package scripts, vendored terminal integration, all reachable repository history, public source release, and locally generated app package. It is a code and distribution review, not a penetration test or a guarantee that every dependency is vulnerability-free.

## Findings and fixes

| Finding | Impact | Resolution |
| --- | --- | --- |
| Automatic clipboard access through OSC 52 | Terminal output, including output from an SSH host or a displayed file, could request the Mac’s clipboard or replace it without a user paste/copy action. | `TerminalOutputPolicy` denies both requests before they reach SwiftTerm’s local-process delegate. Native user-initiated Copy/Paste remains available. Regression tests feed real escape sequences through the parser using a mock clipboard. |
| Builder paths inside local app binaries | Unstripped compiler/debug symbols embedded the builder’s home, checkout, and Derived Data paths. The public v1.0.0 release was source-only; the affected local binary was not a release asset. | Release builds strip local/debug symbols before signing. Every build scans every bundle file, including both architectures, and fails if builder paths remain. The rebuilt app ZIP passed the same raw-byte scan. dSYMs and build logs remain private. |
| Unused upstream file-dump helper | Vendored code contained an upstream author’s home path and an unused helper that could write terminal contents. No active call was found. | Removed the helper and its commented call; documented the local vendor patch and retained all license attribution. The upstream path remains in historical source revisions; it is not the repository owner’s private data. |
| Manifest edge cases | A regular-expression end anchor could accept a trailing newline in the prompt ID; artwork filenames could contain control characters. | Require absolute string boundaries and reject control characters. Regression cases cover newline, CRLF, NUL, and path traversal. |
| Prevention gaps | Some credential/history file extensions were not ignored; checkout credentials persisted for the CI job. | Expanded `.gitignore` and set CI checkout `persist-credentials: false`. GitHub secret scanning and push protection were already enabled. |

## Verification

- **Swift parsing and type checking:** compiler syntax parsing passed; Debug tests and universal Release compilation passed with Xcode 26.1.1. Native compilation type-checks the app and vendored dependency. This remains a Swift 5 language-mode project, not a claim of Swift 6 strict-concurrency compliance. Two upstream Metal renderer warnings about unused `withUnsafeBytes` results and Xcode’s skipped AppIntents metadata warning remain; no compiler errors were found.
- **Native tests:** all **19 XCTest cases passed**, including clipboard denial, configuration validation, gaze/layout, real PTY input/output, resizing, Ctrl-C, and owned-process shutdown. The controller’s PTY test uses the same input delegate path as actual typing.
- **Shell and workflow:** every shell script passed `bash -n` and ShellCheck **0.11.0**. Actionlint **1.7.12** passed. One shared-variable ShellCheck false positive was documented with a narrow annotation.
- **Structured files:** pet JSON, Xcode scheme/workspace XML, Info.plist, and the Xcode project parsed successfully. XcodeGen regenerated the checked-in project from `project.yml`.
- **Secrets and identity:** Gitleaks **8.30.1** found no secrets in reachable Git history or the release source. GitHub’s secret-scanning alerts endpoint returned no alerts. All original commits used the BEXAI public identity and a GitHub no-reply author address; GitHub’s signing identity is public too. No creator username, private home path, credentials, signing certificate, provisioning profile, personal preferences, or terminal transcript was found in the distributed source.
- **Artwork metadata:** the WebP contains its image payload only. PNG/icon metadata contains image dimensions and color information, with no author, device, location, or capture timestamp tags found. Compressed image bytes produced a random email-shaped scanner match; no email metadata was present.
- **Archives and signature:** the published v1.0.0 source ZIP matched its checksum and passed CRC checks. The updated source and app ZIPs were checked for unexpected files and private strings. The universal app passed strict code-signature verification. The package path guard was exercised with clean and deliberately contaminated fixtures.
- **Fresh checkout:** GitHub Actions runs native tests and the Release/package checks on a separate Mac runner. See the [workflow results](https://github.com/BEXAI/Pet/actions/workflows/macos.yml) for the status of a particular commit.

## What “anonymous” means here

The starter does not require or contain the creator’s private accounts, credentials, local preferences, or machine paths. Each person builds it with their own local environment. The app does not contain an AI service, analytics client, remote control server, screen recorder, global keyboard listener, or automatic login item. Its window and folder preferences stay in the current user’s macOS preferences.

The repository is **publicly attributed to BEXAI**; GitHub ownership, public commit identity, release authorship, and upstream license credits remain visible. A Git clone includes history; a source ZIP excludes Git history but still contains the public attribution. This is not a guarantee of an untraceable author or download, and the app is not an anonymous networking tool.

The embedded terminal runs commands with the current macOS user’s permissions. It inherits the launch environment; applications a user runs can access files, credentials, clipboard APIs, and the network using their own capabilities. Blocking OSC 52 prevents terminal-output access; it does not sandbox shell commands. A user can still deliberately paste, run `pbpaste`, or launch a network client. Clicked terminal hyperlinks use the system handler. System-wide `/etc/zshenv` may run even with `zsh -f`.

## Remaining limits and repeat checks

- Source builds are the supported public distribution route. App ZIPs are ad-hoc signed, **not** Developer ID signed or notarized.
- Intel is compiled but not manually exercised. Fullscreen Spaces, physical monitor changes, sleep/wake, extended battery use, and dragging on affected automation setups retain the manual coverage limits documented in [TESTING.md](TESTING.md).
- No dynamic network capture, exhaustive terminal-parser fuzzing, or complete third-party dependency security audit was performed.
- Replacement artwork, new dependencies, new commits, and future binaries require another privacy review. `.gitignore` does not remove already committed data, and a path scan does not detect every possible secret.

To repeat the native checks:

```sh
./scripts/test.sh
./scripts/package.sh
./scripts/check-package.sh
```

With the audit tools installed, repeat the static and history scans:

```sh
shellcheck --external-sources --source-path=SCRIPTDIR scripts/*.sh
actionlint
xcrun swiftc -frontend -parse Sources/*.swift Tests/*.swift
gitleaks git . --redact --log-opts='--all'
```

Keep raw compiler logs, dSYMs, and any unredacted scanner findings out of public issues and release assets.
