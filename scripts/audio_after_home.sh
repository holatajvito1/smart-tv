#!/bin/bash
# After pressing Home in an app, how long until the app has really exited? Prints, from the
# system's own Home-key log line:
#   stopped  - Android tells the app to stop (it waits until our launcher reports it's ready)
#   audio    - the app's audio player pauses/stops (what you hear)
# Usage: scripts/audio_after_home.sh [package] [video-url]
# Default: YouTube + "Despacito" (sound from the first second: a silent video still shows an
# active audio track, which made earlier measurements meaningless).
set -u
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/android/platform-tools:$PATH"
export ANDROID_SERIAL=${ANDROID_SERIAL:-192.168.1.87:5555}
adb() { command adb "$@" </dev/null; }
PKG=${1:-com.amazon.firetv.youtube}
URL=${2:-https://www.youtube.com/watch?v=kJQP7kiw5Fk}

uid=$(adb shell pm list packages -U "$PKG" | grep -oE '[0-9]+$' | tr -d '\r')
started_piid() {
  adb shell dumpsys audio | awk '/players:/,/ducked players/' | grep "u/pid:$uid/" | grep "state:started" \
    | grep -oE "piid:[0-9]+" | head -1
}

adb shell am start -a android.intent.action.VIEW -d "$URL" "$PKG" >/dev/null
piid=""
for _ in $(seq 1 25); do piid=$(started_piid); [ -n "$piid" ] && break; adb shell sleep 1; scripts/remote.sh select; done
[ -n "$piid" ] || { echo "couldn't get $PKG playing audio"; exit 1; }
adb shell sleep 4

adb logcat -b all -c
scripts/remote.sh home
adb shell sleep 9

home=$(adb logcat -d -b system -v time | grep "category.HOME" | grep "from uid 0" | tail -1 | awk '{print $1" "$2}')
stop=$(adb logcat -d -b events -v time | grep "wm_stop_activity" | grep "$PKG" | head -1 | awk '{print $1" "$2}')
audio=$(adb shell dumpsys audio | grep -E "player $piid state:(paused|stopped)" | awk '{print $1" "$2}')
# Audio-service times look like "10-25 10:53:45:610" (colon before the millis); logcat's "10-25 10:53:44.879".
python3 -I - "$home" "$stop" "$audio" <<'EOF'
import sys, datetime as d
home, stop, audio = sys.argv[1], sys.argv[2], sys.argv[3].split("\n")
if not home:
    sys.exit("no Home press found in the system log")
parse = lambda t: d.datetime.strptime(t[:-4] + "." + t[-3:], "%m-%d %H:%M:%S.%f")
h = parse(home)
ms = lambda t: f"{int((parse(t) - h).total_seconds() * 1000)} ms" if t else "never"
first_audio = next((e for e in audio if e.strip() and parse(e) >= h), "")
print(f"app told to stop after {ms(stop)}, audio stopped after {ms(first_audio)}")
EOF
