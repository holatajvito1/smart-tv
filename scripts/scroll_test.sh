#!/bin/sh
# Repeatable home-screen scroll test. Usage: scripts/scroll_test.sh <outdir>
# Resets launcher frame stats, drives a fixed D-pad sequence, then saves dumpsys gfxinfo.
set -e
OUT=${1:?usage: $0 <outdir>}
export PATH="$HOME/.local/android/platform-tools:$PATH"
export ANDROID_SERIAL=${ANDROID_SERIAL:-192.168.1.87:5555}
PKG=com.amazon.tv.launcher
mkdir -p "$OUT"

adb shell input keyevent KEYCODE_HOME
adb shell sleep 5
adb shell dumpsys gfxinfo $PKG reset >/dev/null

# Fixed sequence, run on-device so key timing isn't affected by adb round-trips:
# down through the rows, along each row to the right, back to the left, then back up.
adb shell '
k() { input keyevent $1; sleep 0.35; }
for row in 1 2 3 4 5 6; do
  k KEYCODE_DPAD_DOWN
  for i in 1 2 3 4 5 6 7 8; do k KEYCODE_DPAD_RIGHT; done
  for i in 1 2 3 4 5 6 7 8; do k KEYCODE_DPAD_LEFT; done
done
for row in 1 2 3 4 5 6; do k KEYCODE_DPAD_UP; done
'

adb shell dumpsys gfxinfo $PKG > "$OUT/gfxinfo_launcher.txt"
adb shell input keyevent KEYCODE_HOME
sed -n '/Total frames rendered/,/Number Frame deadline missed/p' "$OUT/gfxinfo_launcher.txt" | head -20
