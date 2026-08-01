# Spitter

Local dictation for macOS, in the menu bar. Hold a hotkey, talk, let go — the text lands in
whatever you were typing into. Everything is transcribed **on-device** by Apple's Speech framework;
no audio, and no transcript, ever leaves your Mac.

Default hotkey: **hold Fn**.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/mlg87/spitter/main/install.sh | bash
```

That downloads the latest release, installs it to `/Applications` (or `~/Applications` if you are
not an admin), and launches it. Releases are ad-hoc signed rather than notarized; because `curl`
and `tar` never set the quarantine attribute, Gatekeeper does not prompt.

## First run

Spitter needs three privacy grants plus one system setting. It will prompt for the first two on
launch; the rest you have to switch on yourself.

| What | Where | Why |
| --- | --- | --- |
| Microphone | prompted on launch | to record while the hotkey is held |
| Speech Recognition | prompted on launch | to transcribe on-device |
| Accessibility | System Settings → Privacy & Security → Accessibility | to see the hotkey system-wide and to paste |
| **Dictation** | System Settings → Keyboard → Dictation → **On** | installs the on-device speech model Spitter uses |

Without Dictation enabled, recognition fails with *"Siri and Dictation are disabled"* and Spitter
turns orange. Without Accessibility, the hotkey does nothing and transcripts are placed
on the clipboard instead of pasted.

Anything still missing shows up as a warning item in the menu; clicking it opens the right
System Settings pane.

### If you keep the default Fn hotkey

macOS maps Fn to its own dictation/emoji picker. Set **System Settings → Keyboard → "Press 🌐 key
to" → Do Nothing**, otherwise Apple's own dictation fights Spitter for the key.

## Using it

- **Hold to Talk** (default): hold the hotkey, speak, release. Releasing within a quarter second is
  treated as an accidental tap and cancels. Pressing a normal key mid-hold also cancels — that is
  what makes Fn + arrow keys keep working.
- **Press to Toggle**: press once to start, press again to stop.
- Either mode can also be driven from the menu (**Start / Stop Dictation**).

Where the text goes:

- A text field, text area, search field, combo box, or web content area has focus → Spitter pastes
  into it and restores your previous clipboard contents half a second later.
- Nothing text-editable has focus → the transcript is left on the clipboard and the menu bar mark
  flashes blue. Paste it wherever you like.

Recording stops automatically after five minutes so a stuck key cannot record forever.

### Reading the menu bar

The mark in the menu bar is always the same speech bubble; only its colour changes, so you can read
the state out of the corner of your eye without the shape jumping around.

| Colour | Meaning |
| --- | --- |
| Black / white (matches your menu bar) | Idle, ready |
| Pink | Recording |
| Violet | Transcribing |
| Green (flash) | Pasted into the focused field |
| Blue (flash) | Left on the clipboard |
| Orange (flash) | Dictation failed — see the menu |
| Grey (flash) | Nothing was said |
| Dim red (steady) | A permission is missing |

### Changing the hotkey

**Change Hotkey…** in the menu, then press what you want: a lone modifier (Fn, Right ⌥, ⌘ …) or a
combination (⌃⌥Space). Esc cancels. **Mode** switches between hold and toggle. Both settings persist.

Known limitation: Spitter observes keys without consuming them, so a *combination* hotkey also
reaches the app in front — pick a lone modifier or an otherwise-unused combination. Consuming the
keystroke would require a `CGEventTap` and a fourth permission (Input Monitoring); one fewer
permission is the better trade.

## Development

```sh
make check   # build + tests + lint (swift-format, shellcheck)
make test    # assertion-based test runner: swift run SpitterTests
make app     # assemble build/Spitter.app (ad-hoc signed)
```

On an Intel Mac with only the Command Line Tools installed, build a single arch:
`ARCHS=x86_64 make app`. CI builds the universal binary.

Layout:

- `Sources/SpitterCore` — pure logic: hotkey engine, dictation state machine, delivery policy. All
  of it is unit-tested.
- `Sources/Spitter` — AppKit UI plus the system adapters (Speech, Accessibility, pasteboard).
- `Sources/SpitterTests` — an executable test runner. Neither XCTest nor Swift Testing is importable
  with Command Line Tools only, so tests are plain assertions that run identically here and on CI.

TCC keys its grants to the app's code signature, so **rebuilding invalidates them**. After a rebuild
run `tccutil reset All com.mlg87.spitter` and re-approve. Permissions also require the bundled app —
`swift run` has no `Info.plist`, so no prompts appear.

## Releases

Versioning is automated. Merge conventional commits (`feat:`, `fix:`, …) to `main`; release-please
maintains a release PR that bumps `version.txt` and `CHANGELOG.md`. Merging that PR tags `v<version>`,
builds the universal bundle, uploads `Spitter-<version>.tar.gz`, and publishes the release —
which is what `install.sh` downloads. Never create `v*` tags or releases by hand.
