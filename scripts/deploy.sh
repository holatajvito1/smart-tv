#!/bin/bash
# Build the launcher and put it on the TV, fully wired up:
#   build APK -> install (upgrade in place) -> grant READ_LOGS -> enable the Home-button
#   accessibility service -> verify it's bound -> open the launcher.
# Safe to re-run any time. Undo everything with ./restore_stock.sh --apply --remove-new
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/android/platform-tools:$PATH"
export ANDROID_SERIAL=${ANDROID_SERIAL:-192.168.1.87:5555}
adb() { command adb "$@" </dev/null; }   # adb shell eats stdin otherwise
PKG=dev.smarttv.home
SVC=$PKG/$PKG.HomeButtonService

adb connect "$ANDROID_SERIAL" >/dev/null 2>&1 || true
adb get-state >/dev/null || { echo "TV not reachable at $ANDROID_SERIAL (asleep? run: adb connect $ANDROID_SERIAL)"; exit 1; }
[ -d before/state ] || { echo "no baseline in before/state: snapshot the stock TV first"; exit 1; }

launcher/android/build.sh | tail -1
adb install -r launcher/android/build/smarttv-home.apk | tail -1

# Development permission: lets the service see Home presses in the system log instantly.
adb shell pm grant $PKG android.permission.READ_LOGS

# Enable the service (never `am force-stop` the app: Android then drops it from this list).
cur=$(adb shell settings get secure enabled_accessibility_services | tr -d '\r')
case ":$cur:" in
  *":$SVC:"*) ;;
  ":null:"|"::") adb shell settings put secure enabled_accessibility_services "$SVC" ;;
  *) adb shell settings put secure enabled_accessibility_services "$cur:$SVC" ;;
esac
adb shell settings put secure accessibility_enabled 1

adb shell am start -n $PKG/.MainActivity >/dev/null 2>&1
for _ in 1 2 3 4 5 6; do
  adb shell dumpsys accessibility | grep -q "$SVC" && break
  adb shell sleep 1
done
if adb shell dumpsys accessibility | grep -q "$SVC"; then echo "Home-button service: bound"
else echo "WARNING: Home-button service not bound"; exit 1; fi
if adb shell 'ps -A -o PPID,NAME' | grep -q logcat && adb shell dumpsys package $PKG | grep -q "READ_LOGS: granted=true"; then
  echo "Instant Home detection: on"
else
  echo "Instant Home detection: off (falls back to slower window events)"
fi
