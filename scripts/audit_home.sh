#!/bin/bash
# End-to-end audit of the launcher using the (virtual hardware) remote:
# every app tile -> app opens -> Home -> back on our launcher; plus each pill.
# Prints one line per check and exits non-zero if anything failed.
set -u
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/android/platform-tools:$PATH"
export ANDROID_SERIAL=${ANDROID_SERIAL:-192.168.1.87:5555}
adb() { command adb "$@" </dev/null; }   # adb shell eats stdin otherwise
OURS=dev.smarttv.home/dev.smarttv.home.MainActivity
FAIL=0

top() { adb shell dumpsys window | grep -m1 mCurrentFocus | sed 's/.*u0 //; s/}.*//' | tr -d '\r'; }
now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
# wait_for <regex> <timeout s>: poll the focused window; prints elapsed ms or "timeout"
wait_for() {
  local start=$(now_ms) end=$(( $(date +%s) + $2 )) cur
  while [ "$(date +%s)" -le "$end" ]; do
    cur=$(top)
    if [[ "$cur" =~ $1 ]]; then echo $(( $(now_ms) - start )); return 0; fi
  done
  echo "timeout (on: ${cur:-?})"; return 1
}
# Home, then wait for our launcher to stay in front: right after Home the fallback redirect can
# briefly hand focus to Amazon's home, which would eat the next key presses.
go_home() {
  scripts/remote.sh home
  local stable=0
  for _ in $(seq 1 25); do
    if [ "$(top)" = "$OURS" ]; then stable=$((stable + 1)); [ $stable -ge 3 ] && return 0; else stable=0; fi
  done
}
check() { if [ "$1" = ok ]; then printf '  PASS  %s\n' "$2"; else printf '  FAIL  %s\n' "$2"; FAIL=1; fi; }

echo "== App tiles (open, then Home)"
go_home
apps=(com.netflix.ninja com.amazon.firebat com.amazon.firetv.youtube com.disney.disneyplus com.hulu.plus com.apple.atve.amazon.appletv)
names=(Netflix "Prime Video" YouTube Disney+ Hulu "Apple TV")
for i in "${!apps[@]}"; do
  go_home                                      # Home on our launcher refocuses the first tile
  moves=(left left left left left left); for ((k = 0; k < i; k++)); do moves+=(right); done   # from the first tile, wherever focus was
  scripts/remote.sh ${moves[@]+"${moves[@]}"} select
  if t=$(wait_for "^${apps[$i]}/" 20); then
    check ok "${names[$i]} opened in ${t} ms"
    adb shell sleep 5                          # let it settle into its own UI
    adb logcat -c
    scripts/remote.sh home
    if t=$(wait_for "^$OURS$" 10); then
      cover=$(adb logcat -d -s SmartTvHome:I | grep -c "returning to ours")
      check ok "${names[$i]} -> Home -> our launcher in ${t} ms (redirects: $cover)"
    else check fail "${names[$i]} -> Home: $t"; fi
  else
    check fail "${names[$i]} didn't open: $t"
  fi
done

echo "== Pills"
pill() { go_home; scripts/remote.sh down left left left left; local m=(); for ((k = 0; k < $1; k++)); do m+=(right); done; scripts/remote.sh ${m[@]+"${m[@]}"} select; adb shell sleep 4; }

pill 1   # AirPlay: nothing to open, should stay on our launcher
[ "$(top)" = "$OURS" ] && check ok "AirPlay stays on launcher" || check fail "AirPlay left launcher: $(top)"

pill 2   # Settings: Amazon's settings must not bounce back
cur=$(top); [[ "$cur" =~ ^com.amazon.tv.launcher/.*Settings ]] && check ok "Settings opens and stays ($cur)" || check fail "Settings: $cur"
scripts/remote.sh home; t=$(wait_for "^$OURS$" 10) && check ok "Settings -> Home -> launcher in ${t} ms" || check fail "Settings -> Home: $t"

pill 3   # Fire TV Home: must stay on Amazon's home
cur=$(top); [[ "$cur" =~ HomeActivity ]] && check ok "Fire TV Home opens and stays" || check fail "Fire TV Home: $cur"
scripts/remote.sh home; adb shell sleep 3; cur=$(top)
[ "$cur" = "$OURS" ] && check ok "Fire TV Home -> Home -> launcher" || check fail "Fire TV Home -> Home stayed on: $cur"

go_home
echo; [ $FAIL = 0 ] && echo "ALL PASSED" || echo "SOME CHECKS FAILED"
exit $FAIL
