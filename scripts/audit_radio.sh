#!/bin/bash
# Plays every radio station through the launcher with the (virtual hardware) remote and checks
# that the TV's audio system reports our player as started. Then: the radio must keep playing
# through a Home press, and must stop when an app is opened. Exits non-zero on any failure.
set -u
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/android/platform-tools:$PATH"
export ANDROID_SERIAL=${ANDROID_SERIAL:-192.168.1.87:5555}
# adb reads stdin; keep it from swallowing anything piped/heredoc'd into this script
adb() { command adb "$@" </dev/null; }
OURS=dev.smarttv.home/dev.smarttv.home.MainActivity

FAIL=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAIL=1; }
uid=$(adb shell pm list packages -U dev.smarttv.home | grep -oE '[0-9]+$' | tr -d '\r')
top() { adb shell dumpsys window | grep -m1 mCurrentFocus | sed 's/.*u0 //; s/}.*//' | tr -d '\r'; }
# Our app's media player state per the audio service (started / paused / stopped / idle)
radio_state() {
  adb shell dumpsys audio | awk '/players:/,/ducked players/' | grep "u/pid:$uid" \
    | grep "usage=USAGE_MEDIA" | grep -oE "state:[a-z]+" | tail -1
}
wait_playing() {
  local st=""
  for _ in 1 2 3 4 5 6 7; do adb shell sleep 2; st=$(radio_state); [ "$st" = "state:started" ] && break; done
  echo "${st:-no player}"
}
# Home, then wait until our launcher has been in front for a couple of seconds: right after a
# Home press the fallback redirect can briefly hand focus to Amazon's home, eating key presses.
go_home() {
  scripts/remote.sh home
  local stable=0
  for _ in $(seq 1 20); do
    if [ "$(top)" = "$OURS" ]; then stable=$((stable + 1)); [ $stable -ge 3 ] && return 0; else stable=0; fi
    adb shell sleep 0.7
  done
}

go_home
scripts/remote.sh up                                                 # wakes it if idle; no-op on the top row
scripts/remote.sh down left left left select; adb shell sleep 2      # Radio pill -> station row
scripts/remote.sh left left left left left left left left left left left left left left left left left left left left

# Station names in on-screen order, read from app.js so new stations are covered automatically.
names=()
while IFS= read -r n; do names+=("$n"); done < <(sed -n '/^const STATIONS/,/^];/p' launcher/web/app.js | grep -oE 'name: "[^"]+"' | sed 's/name: "//; s/"$//')
echo "stations: ${#names[@]}"
for i in "${!names[@]}"; do
  [ "$i" -gt 0 ] && scripts/remote.sh right
  scripts/remote.sh select
  st=$(wait_playing)
  [ "$st" = "state:started" ] && pass "${names[$i]} playing" || fail "${names[$i]}: $st"
done

# Home while listening: the radio should carry on.
go_home; adb shell sleep 3
st=$(radio_state); [ "$st" = "state:started" ] && pass "radio keeps playing through Home" || fail "radio stopped by Home ($st)"

# Opening an app must stop it. Home put the top row back on the apps; open Netflix.
scripts/remote.sh select; adb shell sleep 6
st=$(radio_state); [ "$st" != "state:started" ] && pass "radio stopped when an app opened" || fail "radio still playing after opening an app"
go_home

echo; [ $FAIL = 0 ] && echo "ALL PASSED" || echo "SOME CHECKS FAILED"
exit $FAIL
