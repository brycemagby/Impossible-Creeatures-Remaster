#!/usr/bin/env bash
# Shrinks a web export for hosting: gzips the engine (index.wasm, ~35 MB) to
# index.wasm.gz (~8 MB), which the page unpacks itself (see html/head_include
# in export_presets.cfg). Cloudflare Pages refuses files over 25 MB.
#   tools/pack_web.sh build/web
set -euo pipefail
dir="${1:-build/web}"
gzip -9 -f "$dir/index.wasm"
ls -la "$dir"
