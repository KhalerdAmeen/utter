# Utter: plan

## Market snapshot (Nov 2026)
- **Wispr Flow**: free tier capped at 2,000 words/week on desktop. Pro is $15/mo, or $144/yr billed annually. It's cloud-based. Failed dictations keep their audio and can be retried for 14 days.
- **Open-source alternatives**: VoiceInk (GPL, local, Mac), Handy (MIT, local, cross-platform), OpenWhispr (MIT, local or cloud), FreeFlow, Hex. All of them prove the pattern works. None of them is tuned to your own workflow.
- **What makes this nearly free**: Groq's free tier hosts Whisper large-v3 with limits of 20 req/min, 2,000 req/day and 8 hours of audio a day. That covers heavy personal use at $0. Paid usage is about $0.04 per hour of audio.

## Architecture (v0.1, built)
Native Swift menu bar app, no Xcode project needed. The flow:
1. Hotkey hold or tap → `AVAudioRecorder` writes 16 kHz mono AAC to disk.
2. A History entry is logged before any network call (this is what makes recovery possible).
3. Groq Whisper turns the audio into a raw transcript, with custom vocabulary passed as a hint.
4. A Groq LLM cleans it up: fillers, self-corrections, punctuation, grammar. Tone follows the target app. There's a guardrail so it never "answers" a prompt you're dictating.
5. The text is pasted with ⌘V into the app you started in, and your old clipboard is put back afterwards.
6. Anything that fails stays in History with its audio, gets retried automatically when the network comes back, and can be retried by hand.

## Roadmap
**v0.2 — feel**
- Offline fallback: transcribe on-device (WhisperKit or Apple's Speech framework) when there's no network
- Streaming: upload audio while you're still talking, to cut wait time
- Snippets: say "my calendly" and it expands to the link
- Command mode: select text, hold the key, say "make this shorter"
- Stats: words dictated, time saved

**v0.3 — share with others**
- Apple Developer ID ($99/yr), plus notarization so friends can install without warnings
- Sparkle auto-updates
- A small proxy backend (e.g. Vercel) so users don't need their own API key. Add usage caps, and Stripe if you productize it.
- Landing page (Fun Projects / X build-in-public angle)
