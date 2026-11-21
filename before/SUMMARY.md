# Baseline — stock Fire TV, 2026-10-23 ~18:30
Amazon AFTHY7ABBA (ginza), Fire OS 8.1.8.5 (RS8185/3885), Android 11, 32-bit armeabi-v7a, 1.74 GiB RAM.
UI renders at 1920x1080 (overridden from 3840x2160 panel).

## Home screen ads/promos above the fold (home_screen.png, home_ui.xml)
Strict count (explicit ads/promos): **2**
1. Hero banner: Prime Video NBA "Knicks vs Celtics" live promo, with 2 sponsor brands inside it (American Express Tip-Off, Wingstop)
2. Bottom row labeled "Sponsored": FOX One World Series banner ("Watch 3 days free")

Broad count (+ Amazon self-promotion): **6**
3. "Spooktober" seasonal promo tab in the top nav
4. Fire TV Channels tile, 5. Luna tile, 6. Music Videos tile in the app row (Amazon services, not apps the user chose)

Not counted: "Next up for you" row (5 full + 1 partial tiles: Carrie, VisionQuest, Love of Your Life,
Tenzing, Masterplan). Content recommendations; can't tell from adb whether any come from watch history.

## Cold start (cold_start_raw.txt) — `am start -W` after force-stop, time to first frame
| App | run 1 | run 2 | run 3 | median |
|---|---|---|---|---|
| Netflix (com.netflix.ninja) | 1318 ms | 972 ms | 954 ms | **972 ms** |
| YouTube (com.amazon.firetv.youtube) | 932 ms | 791 ms | 930 ms | **930 ms** |
First frame is a splash; YouTube showed its profile picker by 12 s (coldstart_youtube_after12s.png).
Netflix blocks screenshots (secure surface), so no image.

## RAM, idle on home (meminfo_*.txt, top_processes_rss.txt)
- MemAvailable over 1 min: 570–679 MB (median ~619 MB) of 1,823 MB
- dumpsys: Used 1,426 MB, Free 517 MB, ZRAM swap 381 MB in use
- Biggest: launcher 234 MB, system_server 211 MB, venezia (Appstore) 2×~127 MB, vizzini 117 MB
- Note: first sample hit background dex2oat; samples taken after it finished.

## Home scroll smoothness (scroll_run1/, scroll_run2/) — scripts/scroll_test.sh, launcher gfxinfo
| | run 1 | run 2 |
|---|---|---|
| Frames | 4278 | 4034 |
| Janky | 71.5% | 60.6% |
| p50 / p90 / p99 | 19 / 34 / 44 ms | 19 / 34 / 42 ms |
| Slow UI thread | 250 | 221 |
| Deadline missed | 376 | 334 |
Budget at 60 fps is 16.7 ms, so even the median frame is late.
"High input latency" counts are inflated by `input keyevent` injection; compare before/after only.

## state/
Full config snapshot used by ../restore_stock.sh (packages, settings, app-ops, wm, home app, uid map).
