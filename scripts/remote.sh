#!/bin/sh
# Press Fire TV remote buttons over adb, the way the physical remote does.
#
# `adb shell input keyevent` injects at the Android framework level and skips accessibility
# key filters, so it can't test our Home-button service. Writing to the real remote's
# /dev/input node is blocked by SELinux, so instead this uses Android's `hid` tool (uhid) to
# register a virtual HID remote with the real remote's vendor/product IDs (same key layout,
# Vendor_0171_Product_0424.kl), sends the presses as kernel input events, then unregisters it.
#
# Usage: scripts/remote.sh home | back | select | up | down | left | right | menu | playpause ...
set -e
export PATH="$HOME/.local/android/platform-tools:$PATH"
export ANDROID_SERIAL=${ANDROID_SERIAL:-192.168.1.87:5555}

# Report 1: keyboard (one keycode byte). Report 2: consumer control (one 16-bit usage).
DESC='5,1,9,6,161,1,133,1,5,7,25,0,41,255,21,0,38,255,0,117,8,149,1,129,0,192,5,12,9,1,161,1,133,2,25,0,42,255,3,21,0,38,255,3,117,16,149,1,129,0,192'

json='{"id":1,"command":"register","name":"Fire TV Remote (adb)","vid":369,"pid":1060,"bus":"bluetooth","descriptor":['"$DESC"']}
{"id":1,"command":"delay","duration":900}'
for b in "$@"; do
  case $b in
    up)        down='1,82'    up='1,0' ;;      # keyboard Up Arrow     -> KEY_UP      -> DPAD_UP
    down)      down='1,81'    up='1,0' ;;      # keyboard Down Arrow   -> KEY_DOWN    -> DPAD_DOWN
    left)      down='1,80'    up='1,0' ;;      # keyboard Left Arrow   -> KEY_LEFT    -> DPAD_LEFT
    right)     down='1,79'    up='1,0' ;;      # keyboard Right Arrow  -> KEY_RIGHT   -> DPAD_RIGHT
    select|ok) down='1,88'    up='1,0' ;;      # keypad Enter          -> KEY_KPENTER -> DPAD_CENTER
    home)      down='2,35,2'  up='2,0,0' ;;    # consumer AC Home      -> KEY_HOMEPAGE -> HOME
    back)      down='2,36,2'  up='2,0,0' ;;    # consumer AC Back      -> KEY_BACK    -> BACK
    menu)      down='2,64,0'  up='2,0,0' ;;    # consumer Menu         -> KEY_MENU    -> MENU
    playpause) down='2,205,0' up='2,0,0' ;;    # consumer Play/Pause   -> KEY_PLAYPAUSE
    *) echo "unknown button: $b" >&2; exit 2 ;;
  esac
  json="$json
{\"id\":1,\"command\":\"report\",\"report\":[$down]}
{\"id\":1,\"command\":\"delay\",\"duration\":80}
{\"id\":1,\"command\":\"report\",\"report\":[$up]}
{\"id\":1,\"command\":\"delay\",\"duration\":350}"
done
json="$json
{\"id\":1,\"command\":\"delay\",\"duration\":200}"

printf '%s\n' "$json" | adb shell 'cat > /data/local/tmp/remote.json && hid /data/local/tmp/remote.json >/dev/null 2>&1'
