#!/usr/bin/env bash
set -euo pipefail

# ROOT holds the scripts and the default config; inside BeamMac.app that is
# read-only. Engines, the prefix and the game live in BEAMMAC_HOME. A checkout
# that already has a prefix keeps using itself.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${BEAMMAC_HOME:-}" ]]; then
  if [[ -d "$ROOT/data/prefix" ]]; then
    BEAMMAC_HOME="$ROOT"
  else
    BEAMMAC_HOME="$HOME/Library/Application Support/BeamMac"
  fi
fi
DOWNLOADS="$BEAMMAC_HOME/downloads"
ENGINES="$BEAMMAC_HOME/engines"
DATA="$BEAMMAC_HOME/data"
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
# DXMT from its main branch: the build inside the template crashes BeamNG 0.40
# while a level loads (a command helper used its device before it was set).
# On top of it the fork's dxgi.maxFrameLatency, which overrides how many frames
# the game lets the CPU queue ahead of the GPU.
DXMT_VERSION="v0.80-267-ga945c2b"
DXMT_URL="https://github.com/jx-grxf/BeamMac/releases/download/dxmt-a945c2b/dxmt-a945c2b.tar.xz"
DXMT_SHA="5fa213a805298ee3a2f3e5c531602106d68563043c09009e13659233673388c8"
STEAM_SETUP_URL="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"

# dxmt: DXMT for BeamNG, Steam on wined3d
# d3dmetal: Apple's D3DMetal from the Game Porting Toolkit
# wined3d: plain Wine OpenGL path, only for comparison
BACKEND="${BEAMNG_BACKEND:-dxmt}"
UPSCALER="${BEAMNG_UPSCALER:-metalfx}"
# The BeamMac Game Pack: MSync, AVX for Rosetta and no Steam overlay here,
# MetalFX, frame pacing and low latency through the DXMT config the app writes.
# 0 starts the game the way Wine alone would, to compare against.
PACK="${BEAMNG_PACK:-1}"

# Each engine is an app bundle: macOS only enables Game Mode (CPU and GPU
# priority, faster Bluetooth polling for controllers) for a process it can tie
# to an app in the games category. DXMT replaces the builtin d3d11/dxgi of the
# main engine, so the other two backends run from APFS clones with their own DLLs.

engine_dir() {
  case "$1" in
    d3dmetal) echo "$ENGINES/BeamNG D3DMetal.app/Contents" ;;
    wined3d) echo "$ENGINES/BeamNG WineD3D.app/Contents" ;;
    *) echo "$ENGINES/BeamNG.app/Contents" ;;
  esac
}

wine_bin() { echo "$(engine_dir "$1")/MacOS/wine"; }
wineserver_bin() { echo "$(engine_dir "$1")/MacOS/wineserver"; }
steam_dir() { echo "$PREFIX/drive_c/Program Files (x86)/Steam"; }
steam_exe() { echo "$(steam_dir)/steam.exe"; }

# pgrep takes a regex; paths like "Program Files (x86)" need escaping.
regex_escape() { printf '%s' "$1" | sed 's/[][\\.*^$()+?{}|]/\\&/g'; }

steam_running() { pgrep -qf "$(regex_escape "$(steam_exe)")"; }

HANDOFF_TIMEOUT=30
LOGIN_TIMEOUT=120

# Steam sets ActiveUser once an account is logged in and clears it on quit.
# Reading it through reg.exe sees the live value; user.reg lags behind.
steam_logged_in() {
  run_wine "$BACKEND" reg query 'HKCU\Software\Valve\Steam\ActiveProcess' /v ActiveUser 2>/dev/null \
    | grep -q 'REG_DWORD[[:space:]]*0x0*[1-9a-f]'
}

wait_for_steam_login() {
  local start=$SECONDS
  steam_logged_in && return 0
  log "Warte, bis Steam angemeldet ist"
  while (( SECONDS - start < LOGIN_TIMEOUT )); do
    steam_running || return 1
    sleep 2
    steam_logged_in && return 0
  done
  return 1
}

# Steam's bootstrapper checks for client updates on every start, and under Wine
# that first request hangs for a 60 s timeout. steam.cfg turns the check off;
# once a week a start runs without it so the client stays current.
STEAM_UPDATE_DAYS=7

prepare_steam_bootstrap() {
  local cfg marker="$DATA/steam-updated"
  cfg="$(steam_dir)/steam.cfg"
  if [[ "${1:-}" == force || ! -f "$marker" || -n "$(find "$marker" -mtime +"$STEAM_UPDATE_DAYS" 2>/dev/null)" ]]; then
    rm -f "$cfg"
    touch "$marker"
    log "Steam sucht diesmal nach Updates"
  else
    printf 'BootStrapperInhibitAll=enable\nBootStrapperForceSelfUpdate=disable\n' >"$cfg"
  fi
}

# Steam Input off for BeamNG, set while Steam is not running because Steam
# rewrites localconfig.vdf when it quits. With it on, Steam takes PlayStation
# controllers for itself and hands them over through the overlay, which under
# Wine never reaches the game.
configure_steam_app() {
  local f
  for f in "$(steam_dir)"/userdata/*/config/localconfig.vdf; do
    [[ -f "$f" ]] || continue
    awk -v app="$BEAMNG_APPID" '
      BEGIN { t5 = "\t\t\t\t\t"; t6 = t5 "\t" }
      !inblk && $0 == t5 "\"" app "\"" { header = 1; print; next }
      header && $0 == t5 "{" { header = 0; inblk = 1; print; next }
      inblk && index($0, t6 "\"UseSteamControllerConfig\"") == 1 { next }
      inblk && $0 == t5 "}" {
        print t6 "\"UseSteamControllerConfig\"\t\t\"0\""
        inblk = 0
      }
      { print }
    ' "$f" >"$f.beammac" && mv "$f.beammac" "$f"
  done
}

# steam.exe runs straight from the engine bundle and would sit in the Dock as
# a second, blank icon next to Steam's window. As a UI element it stays out;
# Wine still brings a process into the Dock once it shows a window, and then
# the bundle icon is what it gets.
# Every other Wine process, the game included, is started as
# Contents/lib/wine/../../bin/wine, which macOS does not see as part of the
# bundle: no name, no icon and no Game Mode. A copy of Info.plist next to the
# binary makes bin/ a flat bundle of its own with the same identity.
engine_icon() {
  local icon
  for icon in "$ROOT/../AppIcon.icns" "$ROOT/Assets/AppIcon.icns"; do
    [[ -f "$icon" ]] && { echo "$icon"; return 0; }
  done
  return 1
}

finish_engine_bundle() {
  local app="$1" icon
  plutil -replace LSUIElement -bool true "$app/Contents/Info.plist"
  if icon="$(engine_icon)"; then
    mkdir -p "$app/Contents/Resources"
    cp "$icon" "$app/Contents/Resources/AppIcon.icns"
    plutil -replace CFBundleIconFile -string AppIcon "$app/Contents/Info.plist"
    cp "$icon" "$app/Contents/MacOS/AppIcon.icns"
  fi
  cp "$app/Contents/Info.plist" "$app/Contents/MacOS/Info.plist"
  # Launch Services caches bundle info and would keep the old Dock behavior.
  touch "$app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" 2>/dev/null || true
}

# Engines set up before finish_engine_bundle existed, or rewritten by bin/setup.
update_engine_bundles() {
  local app
  for app in "$ENGINES"/*.app; do
    [[ -f "$app/Contents/Info.plist" ]] || continue
    cmp -s "$app/Contents/Info.plist" "$app/Contents/MacOS/Info.plist" && continue
    finish_engine_bundle "$app"
  done
}

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
# The app reads "[n/total]" from these lines to show setup progress.
step() { printf '\033[1;36m==>\033[0m [%s/%s] %s\n' "$1" "$2" "$3"; }
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
  # Errors stay on: they are rare, and without them a crash leaves no trace.
  export WINEDEBUG="${WINEDEBUG:-fixme-all}"
  # The engine binaries have no rpath; Sikarugir's launcher resolves its
  # dylibs the same way. Calling wine through /usr/bin/arch would strip this.
  export DYLD_FALLBACK_LIBRARY_PATH="$ENGINES/frameworks:$ENGINES/frameworks/GStreamer.framework/Libraries:/usr/lib"
  # The app writes its graphics settings to data/; the tracked file is the default.
  local conf="$CONFIG/dxmt.conf"
  [[ -f "$DATA/dxmt.conf" ]] && conf="$DATA/dxmt.conf"
  export DXMT_CONFIG_FILE="Z:${conf//\//\\}"
  export DXMT_SHADER_CACHE_PATH="$DATA/shader-cache/"
  # metalfx: the game renders at the screen size in points and DXMT's MetalFX
  #   scales the whole frame, UI included, to the panel.
  # game: the game renders at the panel's pixels and its own temporal upscaler
  #   (DLSS through DXMT's NV extension, else FSR) scales only the 3D world, so
  #   text stays sharp.
  # off: native pixels, no upscaling.
  case "$UPSCALER" in
    metalfx) export DXMT_METALFX_SPATIAL_SWAPCHAIN=1 ;;
    game) export DXMT_METALFX_SPATIAL_SWAPCHAIN=0 DXMT_ENABLE_NVEXT=1 ;;
    *) export DXMT_METALFX_SPATIAL_SWAPCHAIN=0 ;;
  esac
  export MTL_HUD_ENABLED="${BEAMNG_HUD:-0}"
  if [[ "$PACK" == 1 ]]; then
    export WINEMSYNC=1
    export ROSETTA_ADVERTISE_AVX=1
    # Steam injects its overlay into the game and hooks every Present, which
    # costs frame time; Steam ignores its own per-game switch for it.
    export WINEDLLOVERRIDES="gameoverlayrenderer,gameoverlayrenderer64=d;${WINEDLLOVERRIDES:-}"
  fi
  case "$backend" in
    d3dmetal|wined3d) export WINEDLLOVERRIDES="d3d11,dxgi,d3d10core=b;${WINEDLLOVERRIDES:-}" ;;
  esac
  mkdir -p "$DATA/shader-cache"
}

# Retina mode decides whether the game sees the screen in points or pixels.
# It is set for the game executable only, so Steam keeps its normal size.
set_game_retina() {
  local want="$1" state="$DATA/game-retina"
  [[ "$(cat "$state" 2>/dev/null)" == "$want" ]] && return 0
  local reg="$DATA/game-retina.reg"
  {
    echo 'Windows Registry Editor Version 5.00'
    for exe in BeamNG.drive.x64.exe BeamNG.tech.x64.exe; do
      echo
      printf '[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\%s\\Mac Driver]\n' "$exe"
      printf '"RetinaMode"="%s"\n' "$want"
    done
  } >"$reg"
  run_wine "$BACKEND" regedit /S "$reg"
  echo "$want" >"$state"
}

run_wine() {
  local backend="$1"; shift
  wine_env "$backend"
  "$(wine_bin "$backend")" "$@"
}
