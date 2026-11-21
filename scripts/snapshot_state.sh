#!/bin/sh
# Snapshot the TV's restorable configuration into <outdir>.
# Same commands that produced before/state/, so the two can be diffed.
set -e
OUT=${1:?usage: $0 <outdir>}
export PATH="$HOME/.local/android/platform-tools:$PATH"
export ANDROID_SERIAL=${ANDROID_SERIAL:-192.168.1.87:5555}
mkdir -p "$OUT"

adb shell pm list packages -u --user 0 | sed 's/^package://' | sort > "$OUT/packages_all_incl_uninstalled.txt"
adb shell pm list packages --user 0 | sed 's/^package://' | sort > "$OUT/packages_installed.txt"
adb shell pm list packages -d --user 0 | sed 's/^package://' | sort > "$OUT/packages_disabled.txt"
adb shell pm list packages -3 --user 0 | sed 's/^package://' | sort > "$OUT/packages_thirdparty.txt"
for ns in global secure system; do
  adb shell settings list $ns | sort > "$OUT/settings_$ns.txt"
done
adb shell cmd package resolve-activity --brief -c android.intent.category.HOME -a android.intent.action.MAIN | tail -1 > "$OUT/home_activity.txt"
adb shell getprop > "$OUT/getprop.txt"
adb shell 'wm size; wm density' > "$OUT/wm.txt"
adb shell dumpsys package preferred-activities > "$OUT/preferred_activities.txt"
adb shell cmd appops dump > "$OUT/appops.txt" 2>/dev/null || true
adb shell pm list packages -U --user 0 | sed 's/^package://' | sort > "$OUT/packages_uids.txt"
