# MecoScribe

![MecoScribe interactive HTML viewer](.github/mecoscribe-overview.gif)

Local CLI for **diarized transcription** on macOS, built on [FluidAudio](https://github.com/FluidInference/FluidAudio). Upload an audio file and get a speaker-labeled transcript plus an interactive HTML viewer.

## Features

- **Diarized transcription** — NVIDIA Nemotron 3 diarization by default (Apple Silicon, up to 8 speakers). The offline VBx pipeline is available with `--mode offline`
- **Parakeet Ultra** — default multilingual ASR, more accurate than v3 with the same languages. Parakeet v3 is available with `--model-version v3`
- **Nemotron 3.5 ASR (streaming 0.6B)** — multilingual streaming transcription with `--model-version nemotron3` (alias `nemotron3.5`; about 40 languages, Apple Silicon)
- **English-only Parakeet-family models** — Phonon-2 (`phonon2`), Bark 3.0 (`bark3`, verbatim) and Bark 3.0 Clean (`bark3-clean`, drops fillers and false starts); macOS 15+
- **Nemotron 3.5 Transcribe Lite** (opt-in) — `--model-version transcribe-lite`. Very fast, but **low accuracy** (about 26% WER on an AMI meeting recording). English only, macOS 15+, roughly a 1.36 GB download
- **Plain-text output** — `<filename>.txt` with timestamps and speaker labels
- **Interactive HTML** — `<filename>.html` with:
  - Color-coded speaker segments
  - Word-level highlighting synced to playback
  - Click any word or segment to seek in the audio
  - Rename speakers
  - Built-in audio player (with playback speed selection)

## Requirements

- macOS 14+ (macOS 15+ for `phonon2`, `bark3`, `bark3-clean` and `transcribe-lite`)
- Swift 6.0+
- Apple Silicon recommended (uses CoreML / ANE via FluidAudio)
- Network access on first run (models download from Hugging Face)

## Install

```bash
git clone https://github.com/HeyMeco/MecoScribe.git
cd MecoScribe
swift build -c release
```

The binary is at `.build/release/mecoscribe`.

## Model cache

Downloaded FluidAudio models are stored in `./models` by default (relative to your current working directory). Subsequent runs reuse the cache instead of re-downloading.

Override with `--models-dir /path/to/models` or the `MECOSCRIBE_MODELS_DIR` environment variable.

## Usage

```bash
# Basic — Nemotron 3 diarization + Parakeet Ultra (defaults)
swift run mecoscribe meeting.wav

# Specify output directory
swift run mecoscribe interview.mp3 --output-dir ./transcripts

# Previous pipeline: offline VBx diarization + Parakeet v3
swift run mecoscribe call.m4a --mode offline --model-version v3

# Nemotron 3.5 ASR (streaming 0.6B) instead of Parakeet Ultra (Apple Silicon)
swift run mecoscribe call.m4a --model-version nemotron3 --language de-DE

# Nemotron 3.5 Transcribe Lite: fast but low accuracy (English, macOS 15+)
swift run mecoscribe meeting.wav --model-version transcribe-lite

# Preset speaker names
swift run mecoscribe panel.wav --speakers "Alice,Bob,Carol"
```

### Options

| Flag | Description |
|------|-------------|
| `-o, --output-dir <dir>` | Output directory (default: same folder as audio) |
| `--models-dir <dir>` | Model cache directory (default: `./models`) |
| `--mode streaming\|offline\|nemotron3` | Diarization mode (default: `nemotron3`). `nemotron3` is NVIDIA Nemotron 3 (Apple Silicon, up to 8 speakers); `offline` is the VBx pipeline |
| `--threshold <float>` | Speaker clustering threshold, or Nemotron 3 frame-activity threshold (default: `0.6`) |
| `--model-version <name>` | ASR model — default `ultra` (multilingual Parakeet); `v3` is the previous multilingual Parakeet; `v2` is English-only; `phonon2`, `bark3` and `bark3-clean` are English-only (macOS 15+); `nemotron3` (alias `nemotron3.5`) is Nemotron 3.5 ASR (streaming 0.6B), multilingual (Apple Silicon); `transcribe-lite` is Nemotron 3.5 Transcribe Lite — fast but low accuracy (~26% WER on AMI meetings), English only, macOS 15+, ~1.36 GB download |
| `--language <code>` | Nemotron 3.5 ASR language hint, `nemotron3` only (default: `auto`). Examples: `en-US`, `de-DE`, `fr-FR`, `ja-JP` |
| `--chunk-ms <560\|1120\|2240\|4480>` | Nemotron 3.5 ASR chunk tier, `nemotron3` only (default: `2240`) |
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

- **`meeting.html`** — open in any browser. The HTML references the original audio file via a relative path, so keep both files together (or open the HTML from the same directory).

## How it works

1. **Diarization** — FluidAudio identifies who spoke when (NVIDIA Nemotron 3 by default, or the `offline` VBx pipeline with `--mode offline`)
2. **Transcription** — Parakeet Ultra by default, Parakeet v3 (`--model-version v3`), Nemotron 3.5 ASR (streaming 0.6B) (`--model-version nemotron3`), or Nemotron 3.5 Transcribe Lite (`--model-version transcribe-lite`), with word-level timestamps. Transcribe Lite only reports word start times, so each word is taken to end where the next one starts
3. **Alignment** — words are mapped to speakers by timestamp overlap
4. **Export** — plain text and self-contained HTML are written

## License

MecoScribe is licensed under the [MIT License](LICENSE).

FluidAudio models and runtime are subject to their respective licenses (MIT / Apache 2.0). See the [FluidAudio repository](https://github.com/FluidInference/FluidAudio) for details.
