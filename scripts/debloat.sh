#!/bin/bash
# Disable (never uninstall) every uncommented package in debloat_disabled.txt.
# Usage: scripts/debloat.sh [--apply]   (dry run without --apply)
# Undo everything: ./restore_stock.sh --apply
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/android/platform-tools:$PATH"
export ANDROID_SERIAL=${ANDROID_SERIAL:-192.168.1.87:5555}
APPLY=0; [ "${1:-}" = --apply ] && APPLY=1

[ -d before/state ] || { echo "no baseline in before/state — refusing to change anything" >&2; exit 1; }
LOG=debloat_$(date +%Y%m%d_%H%M%S).log

sed 's/#.*//' debloat_disabled.txt | awk 'NF {print $1}' | while read -r p; do
  if ! adb shell pm list packages --user 0 < /dev/null | grep -qx "package:$p"; then
    echo "skip   $p (not installed)"; continue
  fi
  if [ $APPLY = 0 ]; then echo "would  $p"; continue; fi
  out=$(adb shell pm disable-user --user 0 "$p" < /dev/null 2>&1 || true)
  echo "$p: $out" >> "$LOG"
  case $out in *"new state: disabled-user"*) echo "ok     $p" ;; *) echo "FAILED $p: $out" ;; esac
done
[ $APPLY = 1 ] && echo "Log: $LOG"
