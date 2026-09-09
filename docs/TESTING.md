# Validation

The hover-dictation update passed **38 native XCTest cases** with zero failures on macOS 26.6.2 / Xcode 26.1.1 (Apple Silicon). The additions cover hover reachability and placement, speech cancellation and finalization, audio resampling, transcript revisions, session-safe insertion, and a real PTY check showing that dictated text is not submitted until Return is sent separately. A controlled, generated speech fixture also passed through the app's actual conversion/streaming pipeline and Apple's SpeechAnalyzer with the expected transcript. The automated checks did not record ambient microphone audio. Subsequent hands-on user testing confirmed the installed hover-dictation feature works; broader microphone-device and language coverage remains manual.

The privacy update passed all **19 native XCTest cases** with zero failures on Xcode 26.1.1 (the initial starter had 17). Local shell scripts and first-party documentation links were also checked.

The install helper was exercised with a destination containing spaces. The installed public app launched with its configured terminal theme and prompt, showed the floating pet with live gaze, and was quit independently of the existing personal companion. The Release bundle passed strict code-signature verification.

Run the native checks on macOS:

```sh
./scripts/validate.sh
./scripts/test.sh
./scripts/build.sh
```

The validator checks the manifest, RGBA components, atlas dimensions, and visible/transparent content in the 73 expected cells. Visor mode additionally requires detectable screen surfaces. These checks do not replace visual review or prove that a new character's gaze is correct.

The XCTest suite covers:

- Layout at screen edges, negative monitor coordinates, and small screens.
- Movement overshoot and long elapsed intervals.
- V2 frame loading and all sixteen direction mappings.
- Neutral gaze, angular hysteresis, and moved/resized native-window coordinate conversion.
- Sprite alpha and pixels outside the visor across all 416 frame/direction combinations for compatible visor artwork.
- Gaze-mode selection and safe configuration decoding.
- Terminal escape sequences cannot read or write the system clipboard, while ordinary input still reaches the terminal delegate. The tests use a mock clipboard and do not read the user’s pasteboard.
- Real PTY output and ANSI color, interactive input, PTY resizing, Ctrl-C, normal shell exit, and owned foreground-job cleanup.

Builds have been exercised with Xcode 26.1.1 on Apple Silicon. Release builds include arm64 and x86_64; Intel runtime testing remains outstanding. Fullscreen Spaces, physical monitor hot-plug, sleep/wake, and extended battery measurements require additional manual coverage. Geometry and long elapsed-time behavior have automated checks.

The included [eye-tracking visual review](images/eye-tracking.png) shows sixteen idle gaze directions and four cardinal directions in both walking animations. A new atlas needs a new visual review. During development, Computer Use could click the borderless pet, but its drag tool could not target that window; native dragging is implemented and still needs manual end-to-end verification on affected setups.

When testing, use an isolated build identity or your own idle test session. Do not close a user's active terminal simply to refresh a visual change.

The [security and privacy audit](SECURITY-AUDIT.md) records type/syntax checks, secret scanning, archive checks, and distribution limitations. Release builds also reject embedded builder paths through `scripts/check-package.sh`.
