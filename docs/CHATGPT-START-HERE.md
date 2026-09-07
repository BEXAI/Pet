# Build my pet with ChatGPT

Download or clone the whole repository. On your Mac, attach its folder to a local project and start a Work chat with **Work locally** selected. The native toolchain must be available on that Mac. See [official Work setup](https://learn.chatgpt.com/docs/get-started-with-work) and [local projects](https://learn.chatgpt.com/docs/projects).

Paste the prompt below. Replace the bracketed fields, or leave them out and let the agent propose defaults.

```text
Make my own macOS desktop pet with an attached real terminal using this repo.
Read README.md, AGENTS.md, docs/CUSTOMIZE.md, and docs/ARCHITECTURE.md first.

Pet name: [name]
Appearance and personality: [description]
Reference artwork: [attached image or a local file in this project, if available]
Terminal border and glow: [colors]
Terminal text: [color]
Terminal background: [transparent, or an RGBA color]

Start from the working app. Keep its real zsh pseudoterminal, roaming, dragging,
pin/unpin, resizing, show/hide session preservation, and mouse tracking.
Use Resources/pet.json for settings. Keep the default sample working until the
replacement artwork is ready. Use an image-generation capability if available
for new artwork; a text response or one still image is not an animation atlas.

Prepare a transparent 1536×2288 atlas with 192×208 cells using the documented
rows and clockwise look directions. Preserve the character's identity across
frames. Choose a gaze mode appropriate to this character. Do not apply Violet
Ember's visor detector to unrelated facial anatomy or draw extra eyes over
existing eyes. Explain any tradeoff between full directional poses and walking
animation. Update the icon if the pet's identity changes.

Run scripts/validate.sh, scripts/test.sh, and scripts/build.sh on this Mac.
Fix build errors. Inspect the pet at normal size, while moving, in all four
cardinal gaze directions, and beside the real terminal. Check that hiding the
terminal preserves its shell and that closing the pet affects only its own
processes. Use a separate test copy if my existing pet has an active session.

Package the final source and app with clear installation instructions. Keep
credentials, signing identities, private paths, and terminal transcripts out
of distributable files. Report the actual checks performed and any remaining
limitations. If a Mac, Xcode, folder access, or image-generation capability is
missing, complete the independent work and state exactly what remains needed.
```

## If you already have a pet atlas

Provide both `pet.json` and its `.webp` or `.png` file, or put them into the project's `Resources` directory. Ask the agent to check the cell geometry and choose an appropriate gaze mode. The app currently consumes a v2 atlas, so a single PNG portrait or a nine-row atlas needs additional work.

## If you only want the included pet

Use this shorter request:

```text
Read this repo's README and AGENTS.md. Build and test the included Pet Terminal
on this Mac using its scripts, then install it in my Applications folder.
Keep the existing artwork and cyan/magenta transparent terminal theme.
```

## Folder access and visual testing

Giving an ordinary chat a GitHub link is enough for discussion, but native build tools need the local source folder. Use the downloaded folder as the primary local project. Computer Use is optional for automated visual testing; it is not needed by the standalone pet. If used, follow the desktop app's current setup prompts. The pet itself does not request Screen Recording or Accessibility permission for mouse-position tracking.
