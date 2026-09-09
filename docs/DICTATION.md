# Voice dictation

## Use

1. Hover over the pet and click **Dictate**, or click the terminal header's microphone.
2. Grant microphone permission if macOS asks. Wait until the preview says **Listening**.
3. Speak. Provisional recognition results appear in the preview, outside the terminal's character grid.
4. Choose **Stop & Insert**, or press **⇧⌘D** in the terminal. The microphone stops, recognition finishes, and the final text is inserted once.
5. Edit the terminal input normally and press Return yourself when ready.

**Esc** or **Cancel** discards the current dictation. A retained draft has an explicit **Insert** action. Hiding the terminal, switching away, sleeping, or replacing its shell interrupts capture and prevents automatic insertion. The pet stops roaming while its voice controls are being used.

The destination is the embedded terminal's current foreground program. Dictation does not identify shell commands or interpret spoken “execute” as a keypress. A terminal editor or other interactive program may interpret printable input immediately. The app inserts a single line, replaces line breaks and control characters with spaces, and does not add Return or shell quoting.

## Requirements and privacy

The dictation feature requires macOS 26 and a device/locale supported by Apple's SpeechTranscriber. Other app features retain their macOS 14 requirement. A supported speech model is downloaded through Apple's system asset manager when necessary. Recognition is on-device. No API account, Accessibility permission, clipboard access, or global keyboard monitor is used by this feature.

Microphone capture begins only after a dictation action and permission approval. Audio buffers are temporary; the app writes no recording or dictation history. Inserted text becomes ordinary terminal input and may consequently be retained by the shell or application receiving it, according to that program's behavior.

## Implementation

- `PetVoiceControls.swift` places an independent nonactivating control panel next to the sprite. Alpha-aware sprite hit testing and drawing are unchanged. A short hover grace period lets the pointer reach the button without making the pet roam away.
- `DictationController.swift` owns microphone capture, SpeechAnalyzer, transcript assembly, cancellation and finalization. Session identity rejects callbacks from cancelled recordings.
- `TerminalPanel.swift` owns the preview, keyboard shortcut, destination checks and direct SwiftTerm input. Partial transcripts never enter the PTY. Final text respects bracketed-paste mode and passes through the existing terminal-output clipboard policy.
- `App.swift` coordinates hovering, roaming, visibility, deactivation, sleep and shutdown.
- `PetTerminal.entitlements` enables hardened-runtime audio input. `project.yml` supplies the microphone usage description and references the entitlements file.

## Verification

Run the usual `scripts/validate.sh`, `scripts/test.sh`, and `scripts/build.sh`. New automated tests exercise hover reachability, screen-edge placement, insertion framing, control-character handling, destination invalidation and speech-session state without capturing ambient microphone audio.

For manual testing, launch an isolated app identity if another pet owns an active terminal session. Verify first-use microphone permission, the hover-to-button transition, cancellation, live recognition, Stop & Insert, and that the resulting command line remains unsubmitted. Also check hiding, focus changes, sleep, microphone disconnection, and shell replacement during dictation. A denied permission should leave the ordinary pet/terminal usable.
