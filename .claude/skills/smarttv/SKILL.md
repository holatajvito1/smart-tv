---
name: smarttv
description: Manage the Fire TV smart TV at 192.168.1.87 and its custom Apple TV-style home screen (dev.smarttv.home). Use for "add [app] to my TV home screen", "remove/reorder an app", "change the background(s)", "change a radio station", "put the TV back to stock", "debloat", "redeploy/fix the launcher", "is the Home button working", or "measure TV performance". Covers adb setup, the launcher's web UI and Android wrapper, build/deploy, the remote-driven audits, restore, and every gotcha found so far.
---

# /smarttv

Everything lives in `/Users/tajsingh/Projects/smart-tv`. Run scripts from there. **Use bash scripts,
not inline zsh**, for anything with arrays or loops (see Gotchas).

## The TV

- Amazon `AFTHY7ABBA` ("ginza"), a **Fire TV smart TV** (MediaTek tuner, HDMI-ARC, live TV), not a stick.
  Fire OS 8.1.8.5 = Android 11 / API 30, **32-bit** `armeabi-v7a`, 1.8 GB RAM, weak GPU.
- adb: `~/.local/android/platform-tools/adb`, serial `192.168.1.87:5555`. Every script sets
  `PATH` and `ANDROID_SERIAL` itself. If the TV slept: `adb connect 192.168.1.87:5555`.
- Build tools (user space, no sudo): JDK 17 `~/.local/jdk/*/Contents/Home`, Android SDK
  `~/.local/android/sdk` (build-tools 34.0.0, platform android-30). No Gradle.

## Layout

| Path | What |
|---|---|
| `launcher/web/` | The home screen: `index.html`, `app.css`, `app.js`, `img/tiles/<id>.png` (320×180 app banners), `img/bg/<set>-N.jpg` (1920×1080 photos), `sounds/*.wav`, `fonts/inter-latin.woff2` |
| `launcher/web/app.js` | **All content config**: `APPS`, `STATIONS`, `PILLS` arrays at the top |
| `launcher/android/` | WebView wrapper: `MainActivity` (keys→JS, launching, SoundPool, snapshot), `HomeButtonService` (Home redirect + cover), `Radio` (MediaPlayer), `build.sh`, **`debug.keystore` (never delete: upgrades need the same key)** |
| `scripts/deploy.sh` | Build → install → grant READ_LOGS → enable service → verify. Safe to re-run. |
| `scripts/remote.sh` | Press buttons on a virtual **hardware** remote: `scripts/remote.sh down right select home` |
| `scripts/audit_home.sh` | Opens every app tile and pill with the remote, presses Home, checks we come back. Must print `ALL PASSED`. |
| `scripts/audit_radio.sh` | Plays every station in `STATIONS` (read from app.js) with the remote and checks audio is really playing; then Home and open-an-app. Must print `ALL PASSED` |
| `scripts/scroll_test.sh`, `scripts/frames.swift` | Stock-launcher scroll benchmark; video → frame contact sheet |
| `scripts/audio_after_home.sh` | Plays a YouTube video, presses Home, prints exactly when the app was stopped and its audio went quiet |
| `scripts/snapshot_state.sh`, `restore_stock.sh`, `before/` | Stock baseline (2026-10-23) and the restore tool |
| `scripts/debloat.sh`, `debloat_disabled.txt` | Disabled Amazon packages (15 disabled, 4 protected) |

## Workflows

### Add an app to the home screen
1. Find the package: `adb shell pm list packages | grep -i <name>`. Not installed? The tile can still
   exist: give it `open: { pkg, store: "<App name>" }` and it shows a **Get** badge and opens an
   Appstore search. Unsure of the package? Use `open: { label: "<exact app label>", store: ... }`.
2. Confirm it launches: `adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER <pkg>`.
   `ResolverActivity` means several matches, so use `component: "<pkg>/.Activity"`. A `SecurityException`
   on `am start` means a signature-protected screen that no third-party app can open (AirPlay, Settings sub-pages).
3. Tile art = the app's own leanback banner, highest density:
   ```bash
   adb pull "$(adb shell pm path <pkg> | head -1 | sed 's/^package://' | tr -d '\r')" /tmp/app.apk
   BT=~/.local/android/sdk/build-tools/34.0.0
   f=$($BT/aapt dump badging /tmp/app.apk | grep -oE "^application: .*" | grep -oE "banner='[^']*'" | cut -d"'" -f2)
   res=$($BT/aapt2 dump resources /tmp/app.apk | awk -v f="$f" '/^    resource /{r=$3} index($0,f){print r; exit}')
   $BT/aapt2 dump resources /tmp/app.apk | awk -v r="$res" '/^    resource /{on=($3==r)} on && /\(.*\)/'   # pick xxhdpi/xhdpi file
   unzip -p /tmp/app.apk res/XX.png > launcher/web/img/tiles/<id>.png
   ```
   No banner (or a bad one)? Make a 320×180 PNG with a headless-Chrome screenshot of a tiny HTML card.
4. Add 2–3 background photos `img/bg/<id>-1.jpg …` (see "Change the background").
5. Add the entry to `APPS` in `app.js` (`id`, `name`, one short `line`, `photos`, optional `dim` for bright photos, `open`).
   **The row fits 6 tiles** (23.6rem wide + 3rem gap, centred inside the dock). For a 7th, shrink `.tile` width or ask which to drop.
6. Preview (below), then `scripts/deploy.sh`, then `scripts/audit_home.sh`, after adding the new app
   to the `apps`/`names` arrays there. Show the user a screenshot from the TV: `adb exec-out screencap -p > shot.png`.

### Change the background
- **One photo for the whole home screen, chosen by month** (user's choice, 2026-10-24). `SEASONS` in `app.js`
  maps month → `launcher/web/img/bg/<name>.jpg`: Jan–Feb `winter`, Mar–May `spring`, Jun–Aug `summer`
  (Moraine Lake), Sep `autumn`, **Oct `halloween`, Nov `thanksgiving`, Dec `christmas`** (the user asked for
  those holiday themes; keep them fun). `tick()` re-checks every minute, so it switches on the 1st by itself.
  No per-app photo switching or rotation. Old per-app photos are in `launcher/photos-archive/` (not bundled).
- To change a month: replace that file, or add a new name and point the month at it in `SEASONS`.
  Preview any month on the Mac with `index.html?month=12`.
- Make each photo **1920×1080 exactly** (the TV's UI resolution, so pixels map 1:1; larger is wasted decode time),
  JPEG quality ~85, **at most ~1 MB** (busy foliage needs ~64). Start from a bigger original for sharpness:
  Unsplash `.../download?force=true&w=3840`. Free licence only. Check it really is a JPEG (`file`), because **Unsplash+ (paid)
  photos come back as non-images**.
  ```bash
  cp src.jpg crop.jpg && sips -c 2160 3840 crop.jpg          # center-crop a 3840-wide original to 16:9 (portrait ok)
  sips -s format jpeg -s formatOptions 85 --resampleWidth 1920 crop.jpg --out launcher/web/img/bg/<name>.jpg
  sips -f horizontal launcher/web/img/bg/<name>.jpg          # optional: mirror to move the subject right of the title
  ```
- Check the **top-right corner** (clock + date) and the bottom-left (title) are readable. The scrim in `.scrim`
  (app.css) shades both. Bright bokeh or leaves were the hard cases.
- Preview on the Mac, get the user's OK, then `scripts/deploy.sh`.

### Birthday / occasion messages
- `OCCASIONS` in `app.js`: `{ month, day, text }`, repeating every year, shown all day (midnight to midnight)
  over the background, big and bold, top-left. Currently:
  **Feb 2 "Happy Birthday Patricia"**, **Oct 31 "Happy Halloween"** (added as a test), **Dec 31 "Happy Birthday Lucia"**.
  To add one, append an entry.
  Long text wraps at 110rem so it never runs into the clock.
- Preview a date: `index.html?date=MM-DD` (sets background + message + shown date).
- **Always also check the page with NO URL parameters** before deploying; that's how the TV runs it. A preview-only
  bug (an empty `[]` override treated as truthy) once turned the clock into "Invalid Date" whenever `?date` was absent,
  and every screenshot with `?date` looked fine. Quick check:
  `chrome --headless=new --virtual-time-budget=3000 --dump-dom file://…/index.html | grep -oE 'id="(clock|date)"[^<]*'`

### Weather
- Third line under the time and date: icon + "60° Clear · H 68° L 39°" for **Astoria, NY 11102**
  (lat 40.7706, lon -73.9265, from api.zippopotam.us/us/11102). `WEATHER_URL` in `app.js` points at
  **Open-Meteo**: free, no API key, sends `access-control-allow-origin: *`, so the page fetches it directly
  (no native code). It refreshes every 30 min and on resume if stale. The last reading is kept in localStorage,
  so it shows instantly at startup and stays up if the network is down. `describeWeather()` maps WMO codes
  to words and `WX_ICONS`.
- To change the location: look up lat/lon for the new ZIP and edit `WEATHER_URL` (also `timezone=`).

### Preview on the Mac before touching the TV
`open -a "Google Chrome" launcher/web/index.html` (arrows, Enter, Esc = Back, P = Play/Pause).
URL params: `?focus=row,col`, `?radio=1`, `?month=N`, `?date=MM-DD`. Open with a `file://` URL
(`open -a "Google Chrome" "file:///…/index.html?date=02-02"`): a plain path with `?` fails. Headless screenshot for checking your own work:
```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
  --run-all-compositor-stages-before-draw --window-size=1920,1080 --virtual-time-budget=6000 \
  --screenshot=out.png "file://$PWD/launcher/web/index.html?focus=0,2"
```
The user asked to see previews before anything is installed on the TV. Keep doing that for visible changes.

### Put the TV back to stock
1. `./restore_stock.sh` is a **dry run**: it shows every difference from `before/state/`.
2. `./restore_stock.sh --apply --remove-new` re-enables the debloated packages, restores settings
   (including turning accessibility back off) and uninstalls the launcher (which also drops its READ_LOGS grant).
   Without `--remove-new`, sideloaded apps stay.
3. `adb reboot`, then `./restore_stock.sh` again should say "Already matches baseline".
It never touches the ADB/developer settings. Confirm with the user before `--apply`: it's the big undo.

### Redeploy / "the Home button stopped working"
`scripts/deploy.sh` and then `scripts/audit_home.sh`. Deploy re-adds the accessibility service, re-grants
READ_LOGS and prints whether instant Home detection is on.

### Measure performance
- Idle CPU: `adb shell "top -b -n 4 -d 3 -o %CPU,NAME" | grep -E "smarttv|surfaceflinger|sandboxed"`.
  Expect ~0.2% for each. Anything above a few % means something is animating forever.
- Frames: `adb shell dumpsys gfxinfo dev.smarttv.home reset`, drive with `scripts/remote.sh`, then read
  `dumpsys gfxinfo dev.smarttv.home`. Judge by **Frame deadline missed / Slow UI thread / Slow draw**
  (all 0 now; stock home: 334–376 / 221–250 / 278–312). Ignore "High input latency"/"Janky %": every
  WebView frame gets flagged.
- What you actually see during a transition: `adb shell screenrecord --time-limit 6 --size 960x540 /sdcard/x.mp4`,
  pull it, then `swift scripts/frames.swift x.mp4 outdir 0.12 4`.

## Current state (2026-11-21)
- **Look: "Dock"** (user's pick from 3 previews, 2026-11-21). Tiles + pills sit centred on a dark rounded shelf
  (`.ui::before` in app.css, no backdrop-filter), the focused item gets a white ring (`.tile::before`), and the app name
  is centred above the shelf. Radio stations scroll inside the shelf: `.stations` clips to the dock's inner width,
  which must match `visible` in `scrollStations()` (164.8rem). The previous look is in `launcher/web-backup-2026-11-21/`
  (not bundled): copy it over `launcher/web/` and run deploy.sh to revert.
- Launcher: apps Netflix (`com.netflix.ninja`), Prime Video (**`com.amazon.firebat`**: never disable),
  YouTube (`com.amazon.firetv.youtube`), Disney+, Hulu, Apple TV (`com.apple.atve.amazon.appletv`).
  Radio: 2 NYC (Hot 97, 1010 WINS) + 6 Santo Domingo, DR (CDN Radio, Primera 88.1, Latina 104, La X 102.1, Top Bachata,
  Platino) = 8, native MediaPlayer. On 2026-11-21 the user removed WNYC, WQXR, WFUV, WBGO, Z100, Radio Paradise,
  RP Mellow, NTS and KEXP (their stream URLs are still in `launcher/web-backup-2026-11-21/app.js`).
  `audit_radio.sh`: ALL PASSED on 2026-11-21.
  Pills: Radio, AirPlay (info only), Settings, Fire TV Home, Power Off. Top right: time (5.6rem bold), date, weather (11102).
- Audit `ALL PASSED` (17 checks). Idle CPU ~0.2%. Home from any app → our launcher in ~0.3–0.6 s, with no Amazon frame visible.
- Debloat: 15 Tier-1 Amazon packages disabled. Home-screen ads are served by Amazon's launcher itself, so only replacing the launcher removes them.

## Gotchas (each one cost time; don't repeat them)

**Shell and tooling (macOS)**
- The interactive shell is **zsh**: unquoted `$list` doesn't word-split and `${!arr[@]}` is a "bad substitution".
  Put loops in `bash` script files.
- **`adb shell` reads stdin** and swallows the rest of a heredoc or `while read` loop. Use `adb ... </dev/null`
  (scripts define `adb() { command adb "$@" </dev/null; }`).
- macOS bash 3.2 + `set -u`: an empty array is "unbound". Use `${a[@]+"${a[@]}"}`.
- BSD `sed` has no `\t` and needs `sed -i ''`. `cmd | while …` runs in a subshell, so counters are lost:
  use `done < <(cmd)`. `comm` needs both sides sorted under the same `LC_ALL=C`.
- `pm list packages -s` means **system** packages, not suspended ones (suspended: `dumpsys package` `suspended=true`).
- Headless Chrome screenshots can fire before CSS transitions finish: add `--run-all-compositor-stages-before-draw`
  and a `--virtual-time-budget`. Verify state with `--dump-dom` if a screenshot looks wrong. It cannot decode video (use `frames.swift`).

**adb / measuring**
- The TV drops adb after sleeping: `adb connect` again. The very first connection needs the on-TV
  "Allow USB debugging" prompt (with "Always allow").
- `dumpsys meminfo` times out while `dex2oat` runs after installs: use `dumpsys -t 90 meminfo`.
- Netflix screenshots are black (secure surface). `am start -W` times only the first frame (a splash screen).
- **`adb shell input keyevent` skips accessibility key filters.** To test the remote realistically, use
  `scripts/remote.sh`. It registers a virtual Bluetooth HID remote via Android's `hid` tool (`/dev/uhid`) with the
  real remote's vendor/product (0x0171/0x0424). The `hid` JSON **must include `"bus":"bluetooth"`** or it crashes.
  Writing to `/dev/input/event*` directly is blocked by SELinux.

**Fire OS and the Home button**
- Fire OS **never** gives Home to other apps: `cmd package set-home-activity` prints "Success" and changes nothing,
  a HOME intent-filter does nothing, and Home **never reaches accessibility key filters** (D-pad and Back do).
  Don't retry these.
- What works: `HomeButtonService` (1) follows the system log for `START … cat=[android.intent.category.HOME] … from uid 0`
  (needs `pm grant dev.smarttv.home android.permission.READ_LOGS`; `-b system` is nearly silent, so it's cheap) and
  (2) falls back to Amazon's `HomeActivity_vNext` window-state event (~0.4 s later, Amazon visible).
- **`am force-stop dev.smarttv.home` (or Force stop in Settings) removes the service from
  `enabled_accessibility_services`**, which silently kills the Home redirect. Never force-stop it. If it happened, run `scripts/deploy.sh`.
- Right after a Home press, the fallback round-trip can hand focus to Amazon's home for ~1–2 s, eating key presses.
  Scripts must wait until our activity is focused and stable before pressing more keys (see `go_home` in the audits).
- **Power Off pill** (2026-11-21): `HomeButtonService.sleepTv()` = `performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)` = standby,
  same as the remote's power button; adb stays connected in standby (`adb shell input keyevent KEYCODE_WAKEUP` wakes it).
  **No Restart button is possible**: REBOOT/SHUTDOWN are signature permissions and Amazon's Restart page is protected.
  `input keyevent --longpress KEYCODE_POWER` also goes straight to standby (no power menu on this TV).
  `audit_home.sh` reaches pills by index and never selects Power Off; keep it last in `PILLS`.
- Fire TV "Settings" = `com.amazon.tv.launcher/.ui.MainSettingsActivity`, reached by bouncing through `HomeActivity_vNext`.
  That's why the Settings pill sets `allowAmazon` and why `com.amazon.tv.settings.v2` windows don't cancel it.
- Signature-protected, so you can't launch them: AirPlay's activity (`com.amazon.airplay.permission.LAUNCH`) and Settings
  sub-pages (`com.amazon.tv.permission.LAUNCHER_SETTINGS`). `android.settings.DISPLAY_SETTINGS` has no handler.
  AirPlay is a background receiver anyway; the pill shows the TV's name ("Patricia's Fire TV").
- Returning from an app redraws the WebView in 0.02–2.4 s (memory pressure). That's hidden by a PixelCopy snapshot taken at
  launch and shown as an accessibility overlay until the WebView reports it has drawn. Home pressed while already on
  our launcher must **not** show the (stale) snapshot; it resets focus to the first tile instead.

**"Audio keeps playing after I exit an app" (YouTube)**
- Home must be a plain exit: **the user explicitly rejected pausing/stopping the app's playback**
  (media keys, audio-focus grabs). Don't reintroduce `dispatchMediaKeyEvent` / focus tricks.
- What happens on Home: Android pauses the app at once, but only *stops* it once the new home screen
  has resumed and gone idle. Then YouTube (Cobalt) takes another ~0.5–1.5 s to silence audio. It ignores
  audio-focus loss and the PAUSE/STOP keys and only obeys PLAY_PAUSE.
- Measured 2026-10-25 with `scripts/audio_after_home.sh`: stock Fire TV home: app stopped 2.5–6.4 s,
  audio 2.4–3.2 s. Ours: 1.3–2.0 s / 1.6–3.6 s. So ours already exits faster than stock; the tail is YouTube's.
  Pausing the WebView in the background or not makes no measurable difference.
- **Measure with timestamps, not polling.** Polling `dumpsys audio` took ~0.7 s per check and over-reported
  by ~2 s. The script uses the system log's Home line, the events log's `wm_stop_activity`, and the audio
  service's own player event times (format `MM-dd HH:mm:ss:SSS`, colon before millis).
- **Test with a video that has sound from the start** (default: Despacito, `kJQP7kiw5Fk`). A silent video
  (the first pick was a silent countdown stream) still shows an active audio track and gives meaningless numbers.
  Check a video's title first: `curl "https://www.youtube.com/oembed?url=<video url>&format=json"`.
- YouTube deep link: `adb shell am start -a android.intent.action.VIEW -d <url> com.amazon.firetv.youtube`.
  It may stop at the profile picker; press `select` until audio plays.

**Debloating**
- Fire OS refuses `disable-user` on protected packages: `ftvads.deeplinking`, `device.metrics`, `device.crashmanager`,
  `device.logmanager`. Never disable the launcher, `venezia` (Appstore, needed to launch/update apps), OOBE, settings,
  IME, Alexa/`vizzini`, tuner/livetv, `arc`, `channelscan`, inputs, audio, screensaver, webview, or any library/overlay.
  This is a TV: breaking inputs or the tuner is serious. Only `pm disable-user`, never uninstall.

**Performance on this chip**
- **No endless animations.** The focused tile's infinite sway/sheen plus a 40 s ambient photo drift cost ~93% CPU
  while idle. Now: animations run once on focus, and the background is one still photo.
- Animate only `transform`/`opacity`. Don't transition `box-shadow` (repaints): fade a pre-shadowed pseudo-element instead.
- Each 1920×1080 photo decode was a ~90–250 ms spike when photos switched per app. Now there is one fixed photo, so there's no decode while navigating.
- The page is designed on a 1920×1080 canvas with `1rem = 1/192` of the width. The TV's UI is 1920×1080 at density 320.
- The WebView never takes focus: `MainActivity.dispatchKeyEvent` forwards keys as `tvKey('left'|…|'back'|'playpause')`.
  `setTextZoom(100)` so the system font size can't break the layout.

**Android build**
- `minSdk 26` (PixelCopy, AudioFocusRequest). WAVs must be stored uncompressed (`aapt2 -0 wav`) for `SoundPool` `openFd`.
- Keep `launcher/android/debug.keystore`. A different key means you can't install over the old version
  (you'd have to uninstall, which also wipes the service setting and the permission grant).
- After `adb install -r`, the service rebinds by itself and grants persist. After an uninstall/reinstall, run `scripts/deploy.sh`.

**Content**
- **This TV's MediaPlayer can't play raw-AAC live streams** (`audio/aac`, `audio/aacp`). They stick on "Tuning…"
  forever; the log shows `NuCachedSource2: caching reached eos`. Use the station's **MP3 mount** or its **HLS**
  (`.m3u8`) instead: curl's 200 OK says nothing about whether the TV can play it. Radio.java now gives up after 15 s.
  After adding stations, run `scripts/audit_radio.sh` (it reads the list from app.js).
- **The TV sleeps after 14 min without a button press** (`settings get secure sleep_timeout` = 840000; the Fire TV
  screensaver is off). Radio used to get cut off by it. Fixed 2026-11-21: `MainActivity.onRadioState` sets
  `FLAG_KEEP_SCREEN_ON` while playing/loading and clears it on stopped/error. Verify with `dumpsys power`: a
  `SCREEN_BRIGHT_WAKE_LOCK 'WindowManager' … WorkSource{<our uid>}` while playing, none after. To test without waiting,
  set `sleep_timeout 60000`, play for 90 s, then **put it back to 840000**.
- **No idle fade (user's choice, 2026-11-21):** the dock and everything else stay on screen all the time. The old
  "ambient" mode (UI faded after 12 s; first key press only woke it) was removed from app.js and app.css. Don't bring it back.
- Finding streams: `https://de1.api.radio-browser.info/json/stations/search?countrycode=DO&order=votes&reverse=true`
  (any country code) lists candidates with homepages. Station websites load their players via JS, so scraping rarely works.
  Then verify each one: HTTP 200, `audio/*`, sensible `icy-name`, and the **final URL after redirects must be https**.
  Android blocks cleartext. The only exception is `radiojar.com` (Primera 88.1's https link redirects to
  short-lived http URLs), allowed in `res/xml/network_security_config.xml`; don't widen it.
  Zeno.fm streams now return 401 (token needed): skip them. Z101 / Alofoke / KQ 94.5 had no verifiable stream (2026-10-25).
- Crave isn't on this TV (Canada-only). SomaFM streams return 403 from this network. Check radio URLs with
  `curl -sI -H "Icy-MetaData: 1"` and look at `icy-name`. Prefer official station hosts (WBGO's comes from wbgo.org).
