# Contributing

Small, focused contributions are welcome. Open an issue for a substantial feature or platform port, then submit a pull request with the concrete behavior change and validation performed.

1. Fork or clone the repo and create a branch.
2. Read `AGENTS.md` and `docs/ARCHITECTURE.md`.
3. Make the change and update documentation where behavior changes.
4. Run `./scripts/validate.sh`, `./scripts/test.sh`, and `./scripts/build.sh` on a Mac.
5. Visually review changes to the pet, eyes, or terminal. Include a screenshot or recording that contains no private terminal content.
6. Regenerate `PetTerminal.xcodeproj` with XcodeGen when `project.yml` or the source-file layout changes.

Keep changes to `Vendor/SwiftTerm` separate and explain the upstream revision or patch. Preserve upstream licenses. Do not commit build outputs, local Xcode user state, secrets, terminal history, signing credentials, or personal settings. Replacement artwork must be appropriate to redistribute with the project and have clear credits.

First-party Swift files use the checked-in `.swift-format` configuration. Format them with `xcrun swift-format format --in-place --recursive Sources Tests scripts/ValidatePet`; keep vendored source unchanged.

The pet's terminal is a real shell. Changes must preserve ownership checks during shutdown and must not terminate unrelated user processes.
