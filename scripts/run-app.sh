#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -x "$ROOT/.build/release/mecoscribe" ]]; then
  echo "Building mecoscribe CLI..."
  (cd "$ROOT" && ./scripts/patch-fluidaudio.sh && swift build -c release)
fi

if [[ ! -d "$ROOT/electron/node_modules" ]]; then
  echo "Installing Electron dependencies..."
  (cd "$ROOT/electron" && npm install)
fi

cd "$ROOT/electron"
npm start
