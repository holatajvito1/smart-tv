#!/bin/bash
# Put the Fire TV back to the state captured in before/state/ (2026-10-23, pre-tweaks).
#
# Works by diffing, not by replaying a list of our changes: it snapshots the TV now,
# compares against the baseline, and reverses every difference in
#   - packages (re-installs removed system apps, re-enables disabled ones, unsuspends)
#   - settings global/secure/system (restores changed/removed keys, deletes added ones)
#   - app-ops modes (per-package and per-uid)
#   - display size/density overrides, default home app
#
# Usage:
#   ./restore_stock.sh                 dry run: print what would change
#   ./restore_stock.sh --apply         make the changes
#   ./restore_stock.sh --apply --remove-new   also uninstall apps sideloaded since baseline
#
# Never touches ADB/developer settings (that would cut off this connection).
# Not covered: app data/caches, app version updates, anything requiring root.

set -euo pipefail
cd "$(dirname "$0")"

export PATH="$HOME/.local/android/platform-tools:$PATH"
export ANDROID_SERIAL=${ANDROID_SERIAL:-192.168.1.87:5555}
export LC_ALL=C   # consistent sort order for comm
BASE=before/state
APPLY=0 REMOVE_NEW=0
for a in "$@"; do
  case $a in
    --apply) APPLY=1 ;;
    --remove-new) REMOVE_NEW=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

# Settings the system changes on its own (found by diffing snapshots), ADB keys (never cut our
# own connection), and volume levels (the user's, not ours to reset).
SKIP_SETTINGS='^(prev_mem_size_broadcasted|user_rotation|boot_count|adb_enabled|adb_wifi_enabled|development_settings_enabled)$|timestamp|_report_time$|^volume_'

[ -d "$BASE" ] || { echo "missing $BASE — nothing to restore to" >&2; exit 1; }
adb connect "$ANDROID_SERIAL" >/dev/null 2>&1 || true
adb get-state >/dev/null 2>&1 || { echo "TV not reachable over adb at $ANDROID_SERIAL" >&2; exit 1; }

NOW=$(mktemp -d)
trap 'rm -rf "$NOW"' EXIT
LOG=restore_$(date +%Y%m%d_%H%M%S).log
echo "Snapshotting current state..."
scripts/snapshot_state.sh "$NOW"

CHANGES=0
# Quote one argument for the device's shell.
q() { printf "'%s'" "$(printf %s "$1" | sed "s/'/'\\\\''/g")"; }
run() {   # run <description> <remote command>
  CHANGES=$((CHANGES + 1))
  echo "  $1"
  if [ $APPLY = 1 ]; then
    echo "\$ adb shell $2" >> "$LOG"
    adb shell "$2" < /dev/null >> "$LOG" 2>&1 || echo "    ! failed (see $LOG)"
  fi
}

echo; echo "== Packages"
# Removed for user 0 (pm uninstall --user 0) -> bring back the system copy.
while read -r p; do
  run "reinstall $p" "cmd package install-existing --user 0 $p"
done < <(comm -23 <(sort "$BASE/packages_installed.txt") <(sort "$NOW/packages_installed.txt"))
# Disabled since baseline -> enable.
while read -r p; do
  run "enable $p" "pm enable --user 0 $p"
done < <(comm -13 <(sort "$BASE/packages_disabled.txt") <(sort "$NOW/packages_disabled.txt"))
# Disabled at baseline but enabled now -> disable again (keeps it exactly stock).
while read -r p; do
  if grep -qx "$p" "$NOW/packages_installed.txt"; then run "re-disable $p" "pm disable-user --user 0 $p"; fi
done < <(comm -23 <(sort "$BASE/packages_disabled.txt") <(sort "$NOW/packages_disabled.txt"))
# Suspended packages (pm suspend) — baseline had none.
adb shell dumpsys package packages | awk '
  /^  Package \[/ { p=$2; gsub(/[\[\]]/,"",p) }
  /^    User 0:/ && /suspended=true/ { print p }' | sort -u > "$NOW/packages_suspended.txt"
while read -r p; do
  if [ -n "$p" ]; then run "unsuspend $p" "pm unsuspend --user 0 $p"; fi
done < "$NOW/packages_suspended.txt"
# Apps added since baseline.
NEW=$(comm -13 <(sort "$BASE/packages_all_incl_uninstalled.txt") <(sort "$NOW/packages_all_incl_uninstalled.txt"))
for p in $NEW; do
  if [ $REMOVE_NEW = 1 ]; then run "uninstall new app $p" "pm uninstall $p"
  else echo "  (new since baseline, keeping: $p — pass --remove-new to uninstall)"; fi
done

echo; echo "== Settings"
for ns in global secure system; do
  # key<TAB>value, split on the first '='
  kv() { awk -v re="$SKIP_SETTINGS" '{ i=index($0,"="); if (!i) next; k=substr($0,1,i-1); if (k !~ re) print k "\t" substr($0,i+1) }' "$1" | sort; }
  kv "$BASE/settings_$ns.txt" > "$NOW/b_$ns"; kv "$NOW/settings_$ns.txt" > "$NOW/n_$ns"
  # Changed or removed keys -> baseline value.
  while IFS=$'\t' read -r k v; do
    if [ "$v" = null ]; then run "$ns $k -> (delete; was null)" "settings delete $ns $(q "$k")"
    else run "$ns $k -> $v" "settings put $ns $(q "$k") $(q "$v")"; fi
  done < <(comm -23 "$NOW/b_$ns" "$NOW/n_$ns")
  # Keys that didn't exist at baseline -> delete.
  cut -f1 "$NOW/b_$ns" > "$NOW/bk_$ns"
  while read -r k; do
    run "$ns $k (added) -> delete" "settings delete $ns $(q "$k")"
  done < <(cut -f1 "$NOW/n_$ns" | comm -13 "$NOW/bk_$ns" -)
done

echo; echo "== App-ops"
# Normalize the dump to lines: "pkg <package> <OP> <mode>" and "uid <uid> <OP> <mode>".
ops() {
  awk '
    /^  Uid /          { uid=$2; sub(/:$/,"",uid); pkg=""; next }
    /^    Package /    { pkg=$2; sub(/:$/,"",pkg); next }
    /^      [A-Z_0-9]+: mode=/ && pkg=="" { op=$1; sub(/:$/,"",op); m=$2; sub(/mode=/,"",m); print "uid", uid, op, m; next }
    /^      [A-Z_0-9]+ \([a-z_]+\):/ && pkg!="" { m=$2; gsub(/[():]/,"",m); print "pkg", pkg, $1, m }
  ' "$1" | sort -u
}
ops "$BASE/appops.txt" > "$NOW/b_ops"; ops "$NOW/appops.txt" > "$NOW/n_ops"
# uid name (u0a5 / 1000) -> one package name, for `appops set --uid`.
uid_pkg() {
  local n=$1
  case $n in u0a*) n=$((10000 + ${n#u0a})) ;; esac
  awk -v u="uid:$n" '$2==u {print $1; exit}' "$BASE/packages_uids.txt"
}
# Anything in the current dump whose mode differs from baseline.
while read -r kind who op mode; do
  base=$(awk -v k="$kind" -v w="$who" -v o="$op" '$1==k && $2==w && $3==o {print $4; exit}' "$NOW/b_ops")
  # A package-level "(allow)" line with no baseline entry is just access history, not a change.
  [ -z "$base" ] && [ "$kind" = pkg ] && [ "$mode" = allow ] && continue
  target=${base:-default}
  [ "$target" = "$mode" ] && continue
  if [ "$kind" = pkg ]; then
    run "appops $who $op: $mode -> $target" "cmd appops set --user 0 $who $op $target"
  else
    p=$(uid_pkg "$who"); [ -n "$p" ] || { echo "  ? uid $who $op=$mode: no package for uid, skipped"; continue; }
    run "appops uid $who ($p) $op: $mode -> $target" "cmd appops set --user 0 --uid $p $op $target"
  fi
done < <(comm -13 "$NOW/b_ops" "$NOW/n_ops")
# Uid-level modes that existed at baseline and have vanished.
while read -r kind who op mode; do
  [ "$kind" = uid ] || continue
  grep -q "^uid $who $op " "$NOW/n_ops" && continue
  p=$(uid_pkg "$who"); [ -n "$p" ] || continue
  run "appops uid $who ($p) $op: (reset) -> $mode" "cmd appops set --user 0 --uid $p $op $mode"
done < <(comm -23 "$NOW/b_ops" "$NOW/n_ops")

echo; echo "== Display"
override() { sed -n "s/^Override $1: //p" "$2"; }
for what in size density; do
  b=$(override $what "$BASE/wm.txt"); n=$(override $what "$NOW/wm.txt")
  [ "$b" = "$n" ] && continue
  if [ -n "$b" ]; then run "wm $what ${n:-physical} -> $b" "wm $what $b"
  else run "wm $what $n -> reset" "wm $what reset"; fi
done

echo; echo "== Home app"
b=$(cat "$BASE/home_activity.txt"); n=$(cat "$NOW/home_activity.txt")
if [ "$b" != "$n" ]; then
  run "home $n -> $b" "cmd package set-home-activity --user 0 $b"
fi

echo
if [ $CHANGES = 0 ]; then
  echo "Already matches baseline. Nothing to do."
elif [ $APPLY = 1 ]; then
  echo "Applied $CHANGES change(s); log in $LOG."
  echo "Reboot to make sure everything takes effect:  adb reboot"
else
  echo "$CHANGES change(s) would be made. Dry run only — re-run with --apply."
fi
