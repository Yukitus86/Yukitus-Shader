#!/usr/bin/env bash
# Prepares the headless test harness: GL headers, Python deps, the GLX context helper and an Xvfb display.
# Usage: bash tools/harness/setup.sh   (then: python3 tools/harness/iris_emu.py compile)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/.build"
DISPLAY_NUM="${EMU_DISPLAY:-:99}"

missing=()
for pkg in libgl-dev libx11-dev mesa-common-dev libgl1-mesa-dri xvfb gcc; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done
if [ ${#missing[@]} -gt 0 ]; then
    sudo_cmd=""
    [ "$(id -u)" -ne 0 ] && sudo_cmd="sudo"
    $sudo_cmd apt-get update -qq
    $sudo_cmd apt-get install -y -qq "${missing[@]}"
fi

python3 -c "import numpy, PIL, OpenGL" 2>/dev/null || pip3 install -q numpy pillow PyOpenGL

mkdir -p "$BUILD"
if [ ! -f "$BUILD/glctx.so" ] || [ "$HERE/glctx.c" -nt "$BUILD/glctx.so" ]; then
    gcc -shared -fPIC -o "$BUILD/glctx.so" "$HERE/glctx.c" -lX11 -lGL
fi

if ! pgrep -f "Xvfb ${DISPLAY_NUM}( |\$)" >/dev/null; then
    # a killed Xvfb can leave its lock/socket behind, which would block a restart
    rm -f "/tmp/.X${DISPLAY_NUM#:}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM#:}"
    nohup Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 >/dev/null 2>&1 &
    for _ in $(seq 1 20); do
        [ -e "/tmp/.X11-unix/X${DISPLAY_NUM#:}" ] && break
        sleep 0.5
    done
fi

echo "harness ready (DISPLAY=$DISPLAY_NUM, $BUILD/glctx.so)"
