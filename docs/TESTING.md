# Validation

The initial public starter passed all **17 native XCTest cases** with zero failures on Xcode 26.1.1. Local shell scripts and first-party documentation links were also checked.

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
- Real PTY output and ANSI color, interactive input, PTY resizing, Ctrl-C, normal shell exit, and owned foreground-job cleanup.

Builds have been exercised with Xcode 26.1.1 on Apple Silicon. Release builds include arm64 and x86_64; Intel runtime testing remains outstanding. Fullscreen Spaces, physical monitor hot-plug, sleep/wake, and extended battery measurements require additional manual coverage. Geometry and long elapsed-time behavior have automated checks.

The included [eye-tracking visual review](images/eye-tracking.png) shows sixteen idle gaze directions and four cardinal directions in both walking animations. A new atlas needs a new visual review. During development, Computer Use could click the borderless pet, but its drag tool could not target that window; native dragging is implemented and still needs manual end-to-end verification on affected setups.

When testing, use an isolated build identity or your own idle test session. Do not close a user's active terminal simply to refresh a visual change.
