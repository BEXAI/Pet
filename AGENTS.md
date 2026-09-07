# Working on Pet Terminal

This repository is a native macOS desktop pet with a real local terminal. Start with `README.md`, `docs/CUSTOMIZE.md`, and `docs/ARCHITECTURE.md`.

- Use the existing runnable app as the starting point. Change the pet definition and artwork before considering a rewrite.
- `Resources/pet.json` controls the pet name, atlas filename, gaze mode, and terminal RGBA colors. Keep personal paths, keys, certificates, conversations, and terminal transcripts out of the repository.
- Use `./scripts/validate.sh`, `./scripts/test.sh`, and `./scripts/build.sh`. XcodeGen is needed only after changing the project structure or build settings in `project.yml`; regenerate and commit `PetTerminal.xcodeproj` together with that manifest.
- The app requires macOS and full Xcode to compile. When working elsewhere, prepare the source and clearly state that native compilation and visual testing remain pending.
- Preserve real PTY input, ANSI output, resizing, Ctrl-C, copy/paste, and the working-directory picker. A drawn command field does not replace the terminal.
- Hide/show must preserve the shell. Shutdown may signal only the pet's own shell and its foreground process group. Do not kill other terminals or use broad process-name kill commands.
- Keep the user's active app and terminal session running during development. Use the existing user authorization before restarting a pet with active work; if a restart is not authorized, finish the build and package first.
- Retain the original sprite silhouette and alpha-aware click-through. Review new artwork at actual pet size and in motion. Directional poses go clockwise from up; they are not animation frames to play sequentially.
- The `visor` renderer is specialized for Violet Ember's dark screen face. For other art, use `directional` or `off`, or implement and verify an appropriate character-specific renderer. Do not claim universal eye detection.
- Only the first four animation rows currently drive desktop behavior. Other rows remain available in the atlas; they do not automatically reflect an AI agent's activity.
- Keep dependencies pinned and retain their license notices. Do not add API accounts, telemetry, remote command execution, or background network features unless the user requests them.
- For a requested public release, review the staged diff and test the exact distributable source. A macOS app packaged by the helper is ad-hoc signed, not notarized; describe that accurately.
