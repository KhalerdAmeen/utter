# Utter

**Say it messy. Send it clean.** Hold a key in any Mac app, talk, and Utter types polished text where your cursor is. It removes the ums, applies your self-corrections and fixes punctuation.

**[Download for Mac →](https://github.com/KhalerdAmeen/utter/releases/latest/download/Utter.dmg)** · [Website](https://getutter.vercel.app)

Free · macOS 13 or later · Apple Silicon and Intel · Signed and notarized by Apple

## Install
1. Open `Utter.dmg` and drag **Utter** into **Applications**.
2. Open Utter from Applications. It's notarized by Apple, so it opens like any other app.
3. Get a free API key at [console.groq.com/keys](https://console.groq.com/keys) and paste it into Utter's Settings.
4. Allow the **Microphone**, and turn on Utter under **System Settings → Privacy & Security → Accessibility**. That's what lets it paste into other apps.

## Use
- **Hold Right Option ⌥**, talk, then let go. Your words appear wherever you're typing.
- **Tap once** to go hands-free, and tap again to finish. **Esc** cancels.
- **Shift + Right Option** with text selected lets you rewrite it by voice, e.g. "make this shorter".
- **Snippets, Dictionary and Style** (formal / casual per app) live in the Utter window, which you open from the menu bar icon.
- Every dictation is saved with its audio, so if your connection drops, nothing is lost. Retry it from History.
- **Settings → Storage → Export / Import** backs up your dictionary, snippets, style, settings and history text in one file.

## Build from source
You need macOS 13+ and Xcode (or the Xcode command line tools: `xcode-select --install`). There's no Xcode project; the scripts compile `Sources/` directly.

```bash
./build.sh --install      # build for this Mac, copy to /Applications and launch
UNIVERSAL=1 ./build.sh    # one app for Apple Silicon + Intel
./make-dmg.sh             # universal build → signed, notarized build/Utter.dmg
./make-dmg.sh --publish   # same, then creates the GitHub release (needs `gh`)
```

**Signing and notarization:** `build.sh` signs with your `Developer ID Application` certificate if it finds one (otherwise ad-hoc). `make-dmg.sh` then notarizes with Apple using a stored profile. Set that up once with:
```bash
xcrun notarytool store-credentials "utter-notary" --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```
Bump `CFBundleShortVersionString` in `Info.plist` for each release, and keep the DMG named `Utter.dmg` so the download link always serves the latest one.

**Provider:** Utter talks to any OpenAI-compatible API. It defaults to Groq (`whisper-large-v3` for speech, `openai/gpt-oss-120b` for writing). You can change the models or provider in Settings → AI provider.

## Project layout
| Path | What it is |
|---|---|
| `Sources/AppDelegate.swift` | Menu bar, hotkey state machine, record → transcribe → clean → paste, auto-retry, Dock behaviour |
| `Sources/AIClient.swift` | Whisper upload, cleanup and command-mode prompts, snippets, connection warm-up |
| `Sources/Features.swift` | Per-app tone, snippets, reading selected/on-screen text, Snippets and Style pages |
| `Sources/HistoryStore.swift` | Saved dictations and audio, stats, retention, crash recovery |
| `Sources/Backup.swift` | Export / import |
| `Sources/Settings.swift` | Settings model, model presets, Settings page |
| `Sources/MainWindow.swift` | App window: sidebar, Home, History, Dictionary |
| `Sources/Overlay.swift` | Floating recording pill |
| `Sources/System.swift` | Hotkey monitor, recorder, paster, permissions, Keychain |
| `Sources/Theme.swift`, `Sources/App.swift` | Design components, app entry point |
| `Assets/` | App icon and menu bar icon |
| `site/` | Landing page (getutter.vercel.app) |
| `PLAN.md` | Market notes and roadmap |

Your API key is stored in the macOS Keychain, never in a file. Audio and history live in `~/Library/Application Support/Utter/`.

Made by [Khadstudio](https://khadstudio.co).

Happy dictating! 🎙️
