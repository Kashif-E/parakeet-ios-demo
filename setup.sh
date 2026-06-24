#!/usr/bin/env bash
# One-command setup: fetch the prebuilt framework + models, generate the project.
#
#   git clone https://github.com/Kashif-E/parakeet-ios-demo
#   cd parakeet-ios-demo && ./setup.sh
#   open ParakeetDemo.xcodeproj      # set your signing Team, pick your iPhone, Run
#
# No submodule, no Metal toolchain, no cross-compile needed - the prebuilt
# Parakeet.xcframework is downloaded from the latest GitHub release. (To build it
# from source instead, run: git submodule update --init --recursive && scripts/build_xcframework.sh)
set -euo pipefail
cd "$(dirname "$0")"

REPO="Kashif-E/parakeet-ios-demo"
HF="https://huggingface.co/kashif3314/nemotron-3.5-asr-streaming-0.6b-gguf/resolve/main"
# .ort files are Git LFS (use media.); tokenizer.bin is a plain file (use raw.)
MOON_LFS="https://media.githubusercontent.com/media/moonshine-ai/moonshine/main/examples/android/Transcriber/app/src/main/assets/base-en"
MOON_RAW="https://raw.githubusercontent.com/moonshine-ai/moonshine/main/examples/android/Transcriber/app/src/main/assets/base-en"

# 1. Prebuilt Parakeet.xcframework (self-contained, EMBED=ON).
if [ ! -d vendor/Parakeet.xcframework ]; then
  echo "-> downloading prebuilt Parakeet.xcframework"
  mkdir -p vendor
  if curl -fL "https://github.com/$REPO/releases/latest/download/Parakeet.xcframework.zip" -o /tmp/pk-xcf.zip; then
    unzip -q -o /tmp/pk-xcf.zip -d vendor/ && rm -f /tmp/pk-xcf.zip
  else
    echo "  no prebuilt release - building from source (needs full Xcode + Metal toolchain)"
    git submodule update --init --recursive
    ./scripts/build_xcframework.sh
  fi
fi

# 2. Parakeet model (stock q4_k, ~685 MB; loads on vanilla parakeet.cpp).
mkdir -p ParakeetDemo/Resources
if [ ! -f ParakeetDemo/Resources/model.gguf ]; then
  echo "-> downloading Parakeet model (~685 MB)"
  curl -fL "$HF/nemotron-3.5-asr-streaming-0.6b-q4_k.gguf?download=true" \
    -o ParakeetDemo/Resources/model.gguf
fi

# 3. Moonshine base-en (for compare mode).
mkdir -p ParakeetDemo/Resources/base-en
for f in encoder_model.ort decoder_model_merged.ort; do
  [ -f "ParakeetDemo/Resources/base-en/$f" ] || { echo "-> downloading Moonshine $f"; curl -fL "$MOON_LFS/$f" -o "ParakeetDemo/Resources/base-en/$f"; }
done
[ -f "ParakeetDemo/Resources/base-en/tokenizer.bin" ] || { echo "-> downloading Moonshine tokenizer.bin"; curl -fL "$MOON_RAW/tokenizer.bin" -o "ParakeetDemo/Resources/base-en/tokenizer.bin"; }

# 4. Generate the Xcode project (disables scheme queue-debugging, resolves packages).
./scripts/generate.sh

echo
echo "Done. open ParakeetDemo.xcodeproj -> set your signing Team -> pick your iPhone -> Run."
