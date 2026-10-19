#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOADS="$ROOT/downloads"
ENGINES="$ROOT/engines"
DATA="$ROOT/data"
CONFIG="$ROOT/config"
PREFIX="$DATA/prefix"

BEAMNG_APPID=284160

WINE_URL="https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir10.0_8.tar.xz"
WINE_SHA="2a6bcf2a3bf13cddf825599b6bc1e3659cbf71e1282c6d77141a92f6ac8d4c68"
# The wrapper template carries the dylibs the engine links against, plus
# DXMT and D3DMetal builds that match this engine.
TEMPLATE_VERSION="1.0.24"
TEMPLATE_URL="https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-$TEMPLATE_VERSION.tar.xz"
TEMPLATE_SHA="4b5f89eeb9ef139936bdfad33d9b420b05ea4597cb7d63376674f7a8e171321c"
STEAM_SETUP_URL="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"

# dxmt: DXMT for BeamNG, Steam on wined3d
# d3dmetal: Apple's D3DMetal from the Game Porting Toolkit
# wined3d: plain Wine OpenGL path, only for comparison
BACKEND="${BEAMNG_BACKEND:-dxmt}"

engine_dir() {
  case "$1" in
    d3dmetal) echo "$ENGINES/wine-d3dmetal" ;;
    *) echo "$ENGINES/wine/wswine.bundle" ;;
  esac
}

wine_bin() { echo "$(engine_dir "$1")/bin/wine"; }
wineserver_bin() { echo "$(engine_dir "$1")/bin/wineserver"; }
steam_exe() { echo "$PREFIX/drive_c/Program Files (x86)/Steam/steam.exe"; }

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mFehler:\033[0m %s\n' "$*" >&2; exit 1; }

fetch() {
  local url="$1" sha="$2" dest="$3"
  if [[ -f "$dest" ]] && [[ -z "$sha" || "$(shasum -a 256 "$dest" | cut -d' ' -f1)" == "$sha" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  log "Lade $(basename "$url")"
  curl -fL# -o "$dest.part" "$url"
  if [[ -n "$sha" ]]; then
    local got
    got="$(shasum -a 256 "$dest.part" | cut -d' ' -f1)"
    [[ "$got" == "$sha" ]] || die "Prüfsumme passt nicht für $(basename "$url"): $got"
  fi
  mv "$dest.part" "$dest"
}

wine_env() {
  local backend="$1"
  export WINEPREFIX="$PREFIX"
  export WINEDEBUG="${WINEDEBUG:--all}"
  export WINEMSYNC=1
  # The engine binaries have no rpath; Sikarugir's launcher resolves its
  # dylibs the same way. Calling wine through /usr/bin/arch would strip this.
  export DYLD_FALLBACK_LIBRARY_PATH="$ENGINES/frameworks:$ENGINES/frameworks/GStreamer.framework/Libraries:/usr/lib"
  export DXMT_CONFIG_FILE="Z:${CONFIG//\//\\}\\dxmt.conf"
  export DXMT_SHADER_CACHE_PATH="$DATA/shader-cache/"
  export DXMT_METALFX_SPATIAL_SWAPCHAIN="${BEAMNG_METALFX:-1}"
  export MTL_HUD_ENABLED="${BEAMNG_HUD:-0}"
  export ROSETTA_ADVERTISE_AVX=1
  case "$backend" in
    d3dmetal|wined3d) export WINEDLLOVERRIDES="d3d11,dxgi,d3d10core=b;${WINEDLLOVERRIDES:-}" ;;
  esac
  mkdir -p "$DATA/shader-cache"
}

run_wine() {
  local backend="$1"; shift
  wine_env "$backend"
  "$(wine_bin "$backend")" "$@"
}
