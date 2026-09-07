# Customize the pet

## Names and colors

Start in `Resources/pet.json`:

| Field | Meaning |
| --- | --- |
| `id` | Lowercase slug such as `moon-cat`; also used in the shell prompt. |
| `displayName` | Name shown in the pet and terminal interface, up to 60 printable characters. |
| `description` | A short description of the character. |
| `spriteVersionNumber` | Must be `2`. |
| `spritesheetPath` | A `.webp` or `.png` filename located directly in `Resources`. |
| `gazeMode` | `visor`, `directional`, or `off`; see below. Missing values default to `directional`. |
| `terminal` | Four RGBA arrays: `border`, `glow`, `text`, `background`. Omit the whole object for the default neon theme. |

All color components are numbers from `0` to `1`. Alpha `0` is fully transparent; alpha `1` is opaque. The default background `[0,0,0,0]` is transparent black. The window behind the terminal may affect readability. Explicit ANSI colors from programs can override the default text color.

Settings are bundled at build time. Rebuild and restart to apply changes. The Finder app name remains **Pet Terminal**. To publish a separately branded app, also change the product name, bundle identifier, scheme references, and icon as described in [DISTRIBUTION.md](DISTRIBUTION.md).

## Artwork contract

The atlas is **1536×2288 pixels**: **8 columns × 11 rows**, with **192×208** pixels per cell. Cells have transparent backgrounds. Keep the whole character inside each cell and maintain a consistent scale, face, props, and baseline.

| Row | State | Used columns | Timing |
| --- | --- | --- | --- |
| 0 | Idle | 0–5 | 280, 110, 110, 140, 140, 320 ms |
| 1 | Walk/run right | 0–7 | 120 ms each; last 220 ms |
| 2 | Walk/run left | 0–7 | 120 ms each; last 220 ms |
| 3 | Wave | 0–3 | 140 ms each; last 280 ms |
| 4 | Jump | 0–4 | Reserved by the current desktop app |
| 5 | Failed | 0–7 | Reserved |
| 6 | Waiting | 0–5 | Reserved |
| 7 | Working/thinking | 0–5 | Reserved |
| 8 | Review | 0–5 | Reserved |
| 9 | Look directions A | 0–7 | Up through down-right, clockwise |
| 10 | Look directions B | 0–7 | Down through up-left, clockwise |

The renderer loads rows 0–3, uses rows 0–2 for normal desktop behavior, and uses rows 9–10 for gaze. The wave frames are available for extensions. The remaining states do not automatically connect to ChatGPT or a CLI's activity. For new artwork, leave unused cells transparent; this renderer ignores cells outside the documented used columns.

Look poses are selected by pointer direction; do not play them as a timed animation:

```text
row 9:    0°,  22.5°,  45°,  67.5°,  90°, 112.5°, 135°, 157.5°
row 10: 180°, 202.5°, 225°, 247.5°, 270°, 292.5°, 315°, 337.5°
```

`0°` points up, `90°` to the viewer's right, `180°` down, and `270°` to the viewer's left. The small pointer dead zone near the face returns to the ordinary frame. Review both cardinal and diagonal poses at the actual display size.

## Choose a gaze mode

### `visor` — the included Violet Ember

The renderer identifies the dark, purple-edged screen surface and maps the original directional face artwork inside each animated visor. It preserves walking motion, the surrounding artwork, alpha, and short idle blinks. It is specifically tuned to this atlas's face colors and position; it is not a general face or eye detector. Recolors or a substantially different screen face need visual review and possibly adjustments in `Sources/EyeTracking.swift`.

### `directional` — custom characters with sixteen look poses

Shows the complete supplied look frame, preserving the artist's eye/head/body pose. It works without the visor detector. The pet still moves around the screen, but while tracking it displays the selected look pose instead of the walking/idle animation. This is the simplest starting mode for unrelated characters. For animated walking and independent eyes together, build a renderer appropriate to the new character's eye apertures or rig.

### `off` — ordinary animation

Plays the regular idle/walking frames without mouse-driven eye changes. The atlas geometry stays the same, so you can add gaze later.

## Replace artwork

1. Create or obtain artwork you can redistribute. Start from one consistent character reference.
2. Produce and assemble the animation and directional poses into the atlas above. Keep effects attached to the character, remove backgrounds, and avoid clipping or seams.
3. Put the atlas in `Resources`, update `pet.json`, and select its gaze mode.
4. Replace `Resources/AppIcon.icns` if you want a matching icon.
5. Run `./scripts/validate.sh` and `./scripts/test.sh`, then build and visually inspect the app. Numeric validation cannot prove that a pose looks in the correct direction or that animations are attractive.

Adding a new resource filename to the project may require regenerating it with `xcodegen generate`; commit the updated `PetTerminal.xcodeproj` along with `project.yml`. Replacing the existing filename needs no regeneration.
