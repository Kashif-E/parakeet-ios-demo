# parakeet-ios-demo

Live, **on-device streaming speech-to-text** on iOS, built on
[parakeet.cpp](https://github.com/mudler/parakeet.cpp). Tap the mic, speak, and the
transcript streams onto the screen — waveform on top, mic button in the middle,
transcript at the bottom, with a one-tap copy button per pane. Includes a
**compare mode** that runs Parakeet next to Apple's `SpeechTranscriber` (iOS 26)
and [Moonshine](https://github.com/moonshine-ai/moonshine-swift) side by side.

> **Community example — not maintained or tested by the parakeet.cpp core team**
> (they have no Apple toolchain). Best-effort, maintained here.

## How it links to parakeet.cpp

parakeet.cpp is a **pinned git submodule** at `third_party/parakeet.cpp`.
`scripts/build_xcframework.sh` compiles `libparakeet` (+ ggml, Metal) from it into a
static `Parakeet.xcframework` for device + simulator. The app drives the streaming
C-API (`parakeet_capi_stream_*`) over mic audio captured with `AVAudioEngine` and
resampled to 16 kHz.

## Requirements

- **Full Xcode** (not just Command Line Tools) — needed for the iOS SDK and the
  Metal toolchain (run `xcodebuild -downloadComponent MetalToolchain` if the metal
  compiler is missing).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- An iPhone (A16+ recommended for the 0.6B model in real time) and an Apple ID for signing.

## Build & run

```sh
# 1. Clone with submodules (pulls parakeet.cpp + its ggml).
git clone --recursive https://github.com/Kashif-E/parakeet-ios-demo
cd parakeet-ios-demo

# 2. Build the static framework (device + simulator). A few minutes.
./scripts/build_xcframework.sh                 # -> vendor/Parakeet.xcframework

# 3. Get a model — any *streaming* parakeet GGUF that loads on stock parakeet.cpp,
#    saved as ParakeetDemo/Resources/model.gguf. e.g. the stock q4_k from
#    https://huggingface.co/kashif3314/nemotron-3.5-asr-streaming-0.6b-gguf
mkdir -p ParakeetDemo/Resources
#   nemotron-3.5-asr-streaming-0.6b-q4_k.gguf  ->  ParakeetDemo/Resources/model.gguf

# 4. (Optional, for compare mode) Moonshine base-en model files into
#    ParakeetDemo/Resources/base-en/ : encoder_model.ort, decoder_model_merged.ort,
#    tokenizer.bin (from github.com/moonshine-ai/moonshine assets).
mkdir -p ParakeetDemo/Resources/base-en

# 5. Generate the Xcode project (the wrapper also disables scheme queue-debugging,
#    which otherwise crashes iOS 26+/27 at launch under the debugger).
./scripts/generate.sh                          # -> ParakeetDemo.xcodeproj

# 6. Open, set your signing Team, pick your iPhone, Run.
open ParakeetDemo.xcodeproj
```

## Compare mode

Toggle **"Compare"** to run three engines on the same mic audio, stacked:
**Parakeet** (this) · **Apple `SpeechTranscriber`** (iOS 26, system) · **Moonshine**
(SPM package, bundled `base-en` model). Each pane has a copy button. Useful for
judging accuracy, punctuation, number formatting, and latency for your use case.

## Notes

- Uses a **stock parakeet.cpp model** so it builds from the vanilla pinned submodule
  with no extra patches. (A smaller `q4_k + q8-rest` build exists but needs a
  load-time dequant patch; not used here.)
- The metallib is precompiled at build time (`EMBED=OFF`) so first-load is fast.
- The model must be a **streaming** model (`nemotron-3.5-asr-streaming-0.6b` or
  `parakeet_realtime_eou_120m-v1`); offline-only GGUFs fail `stream_begin`.
- Models are gitignored — you supply them per steps 3–4.

## Licenses

- App code: MIT (this repo, `LICENSE`).
- [parakeet.cpp](https://github.com/mudler/parakeet.cpp): MIT (submodule).
- Model weights follow each model's own license (e.g. NVIDIA nemotron is
  OpenMDW-1.1; Moonshine per its repo). Apple `SpeechTranscriber` is a system framework.
