# MecoScribe

![MecoScribe interactive HTML viewer](.github/mecoscribe-overview.gif)

Local **diarized transcription** on macOS, built on [FluidAudio](https://github.com/FluidInference/FluidAudio). Available as an Electron desktop app and a CLI.

## Features

- **Electron desktop app** — welcome screen, transcription progress, and the interactive HTML transcript editor with audio-synced highlighting, speaker editing, undo/redo, and auto-save
- **CLI** — batch transcription from the terminal
- **Diarized transcription** — identifies speakers and assigns words to each speaker
- **Plain-text output** — `<filename>.txt` with timestamps and speaker labels
- **Interactive HTML editor** — shared template used by the app and CLI exports:
  - Color-coded speaker segments
  - Word-level highlighting synced to playback
  - Click any word or segment to seek in the audio
  - Rename speakers, assign or move words
  - Built-in audio player (with playback speed selection)

## Requirements

- macOS 14+
- Swift 6.0+ (for the transcription CLI)
- Node.js 18+ (for the Electron app)
- Apple Silicon recommended (uses CoreML / ANE via FluidAudio)
- Network access on first run (models download from Hugging Face)

## Install

```bash
git clone https://github.com/HeyMeco/MecoScribe.git
cd MecoScribe
./scripts/patch-fluidaudio.sh
swift build -c release
cd electron && npm install
```

`patch-fluidaudio.sh` excludes a documentation file from FluidAudio's SwiftPM target (upstream emits a build warning otherwise). Re-run it after `swift package update` or `swift package reset`.

The CLI binary is at `.build/release/mecoscribe`.

## Desktop App

The Electron app wraps the HTML transcript editor and calls the Swift CLI for transcription:

```bash
cd electron
npm start
```

### App workflows

1. **Transcribe audio** — open or drop an audio file (`.wav`, `.mp3`, `.m4a`). Models download on first run, then MecoScribe writes `.txt` and `.mecoscribe.json` beside the audio and opens the editor.
2. **Open existing transcript** — open a `.txt` file (with sibling audio and optional `.mecoscribe.json` sidecar).
3. **Edit** — rename speakers, edit words/utterances, assign or move words, undo/redo. Changes auto-save to disk.
4. **Export** — save a copy as `.txt` or export an interactive `.html` viewer.

App settings (diarization mode, ASR model, model cache path) are available under **MecoScribe → Settings** or from the welcome screen.

## Model cache

Downloaded FluidAudio models are stored system-wide at `~/Library/Application Support/MecoScribe/models` by default. Subsequent runs reuse the cache instead of re-downloading, regardless of where your audio files live.

Override with `--models-dir /path/to/models` or the `MECOSCRIBE_MODELS_DIR` environment variable. The app uses the same default unless overridden in Settings.

## CLI Usage

```bash
# Basic — writes meeting.txt and meeting.html next to the audio file
swift run mecoscribe meeting.wav

# Specify output directory
swift run mecoscribe interview.mp3 --output-dir ./transcripts

# Offline diarization (default) — multilingual ASR is used automatically
swift run mecoscribe call.m4a --output-dir ./transcripts

# English-only ASR (optional)
swift run mecoscribe english.wav --model-version v2

# Preset speaker names
swift run mecoscribe panel.wav --speakers "Alice,Bob,Carol"
```

### Options

| Flag | Description |
|------|-------------|
| `-o, --output-dir <dir>` | Output directory (default: same folder as audio) |
| `--html-only` | If `.txt` exists, regenerate HTML only |
| `--both` | If `.txt` exists, re-transcribe and overwrite both |
| `--json-progress` | Emit machine-readable progress lines (used by the Electron app) |
| `--models-dir <dir>` | Model cache directory (default: `~/Library/Application Support/MecoScribe/models`) |
| `--mode streaming\|offline` | Diarization mode (default: `offline`) |
| `--threshold <float>` | Speaker clustering threshold (default: `0.6`) |
| `--model-version v2\|v3` | ASR model — default `v3` (multilingual); use `v2` for English-only |
| `--model-dir <path>` | Use local ASR models instead of downloading |
| `--speakers <n1,n2,...>` | Initial speaker display names |
| `-h, --help` | Show help |

## Output

Given `meeting.wav`, MecoScribe produces:

- **`meeting.txt`** — readable transcript:

  ```
  [00:12] Speaker 1:
  Welcome everyone to today's meeting.

  [00:18] Speaker 2:
  Thanks for having me.
  ```

- **`meeting.mecoscribe.json`** — word-level timings sidecar for the editor
- **`meeting.html`** — interactive browser viewer (CLI export; same template as the app editor)

## How it works

1. **Diarization** — FluidAudio identifies who spoke when (`offline` VBx pipeline by default)
2. **Transcription** — Parakeet ASR with word-level timestamps
3. **Alignment** — words are mapped to speakers by timestamp overlap
4. **Export** — plain text, JSON sidecar, and self-contained HTML are written

The HTML editor template lives in `Sources/MecoScribeCore/Resources/editor-template.html` and is shared by the CLI exporter and Electron app.

## License

MecoScribe is licensed under the [MIT License](LICENSE).

FluidAudio models and runtime are subject to their respective licenses (MIT / Apache 2.0). See the [FluidAudio repository](https://github.com/FluidInference/FluidAudio) for details.
