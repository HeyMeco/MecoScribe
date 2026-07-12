#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/.build/checkouts/FluidAudio/Package.swift"
MARKER='ASR/Parakeet/Unified/benchmark.md'

if [[ ! -f "$PKG" ]]; then
  echo "FluidAudio checkout not found; resolving packages..."
  (cd "$ROOT" && swift package resolve)
fi

if grep -q "$MARKER" "$PKG"; then
  echo "FluidAudio Package.swift already patched."
  exit 0
fi

chmod u+w "$PKG"

python3 - "$PKG" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = '            path: "Sources/FluidAudio"\n'
replacement = (
    '            path: "Sources/FluidAudio",\n'
    '            exclude: ["ASR/Parakeet/Unified/benchmark.md"]\n'
)

if needle not in text:
    # Newer FluidAudio manifests also declare resources on this target.
    needle = (
        '            path: "Sources/FluidAudio",\n'
        '            resources: [\n'
    )
    replacement = (
        '            path: "Sources/FluidAudio",\n'
        '            exclude: ["ASR/Parakeet/Unified/benchmark.md"],\n'
        '            resources: [\n'
    )
    if needle not in text:
        raise SystemExit("Could not find FluidAudio target in Package.swift")

path.write_text(text.replace(needle, replacement, 1))
PY

echo "Patched FluidAudio Package.swift to exclude benchmark.md."
