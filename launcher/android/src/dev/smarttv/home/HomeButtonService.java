package dev.smarttv.home;

import android.Manifest;
import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;
import android.widget.ImageView;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * Brings our launcher back when the remote's Home button is pressed.
 *
 * Fire OS sends Home straight to Amazon's launcher: it ignores the preferred-home setting and
 * never passes the key to accessibility services (verified with hardware-level key events).
 * Two ways to notice a Home press instead:
 *  1. System log (needs READ_LOGS, granted over adb): the system logs every Home-key launch as
 *     a HOME-category START "from uid 0", the moment it happens. We react before Amazon's home
 *     has drawn, and it works even when Amazon's home or Settings is already showing.
 *  2. Fallback: Amazon's home window coming to the front, unless the user picked Fire TV Home
 *     or Settings on purpose. ~0.4 s later, so Amazon's home is briefly visible.
 *
 * To hide the hand-off, the moment Amazon's home is detected we cover the screen with a
 * snapshot of our launcher as the user left it, and drop the cover once the real one has
 * drawn underneath. Without it, Amazon's home plus a ~1 s WebView redraw are visible.
 */
public class HomeButtonService extends AccessibilityService {
    private static final String TAG = "SmartTvHome";
    private static final String AMAZON_PKG = "com.amazon.tv.launcher";
    private static final String AMAZON_HOME_CLASS_PREFIX = "com.amazon.tv.launcher.ui.HomeActivity";
    // Amazon's Settings app hands off to the launcher's Settings tab, so it counts as "Amazon home".
    private static final String AMAZON_SETTINGS_PKG = "com.amazon.tv.settings.v2";
    private static final long COVER_TIMEOUT_MS = 4000;

    private static HomeButtonService instance;

    // Set when the user picked Fire TV Home or Settings on our launcher; cleared when ours
    // comes back (MainActivity.onResume) or any other app takes the screen.
    private static volatile boolean amazonHomeAllowed;

    // Last frame of our launcher, taken just before it opens an app.
    private static Bitmap snapshot;

    // Circuit breaker: if we keep bouncing (e.g. our activity can't start), stop redirecting.
    private static final int MAX_BOUNCES = 5;
    private static final long BOUNCE_WINDOW_MS = 10_000;
    private final long[] bounces = new long[MAX_BOUNCES];
    private int bounceIdx;

    private final Handler main = new Handler(Looper.getMainLooper());
    private ImageView cover;

    static void allowAmazonHome() {
        amazonHomeAllowed = true;
    }

    static void clearAmazonHome() {
        amazonHomeAllowed = false;
    }

    static void setSnapshot(Bitmap bitmap) {
        if (snapshot != null && snapshot != bitmap) snapshot.recycle();
        snapshot = bitmap;
    }

    /**
     * Puts the TV in standby, like the remote's power button (the remote turns it back on).
     * Restart isn't possible: REBOOT is a signature permission and Amazon's Restart page is protected.
     * False if the service isn't running.
     */
    static boolean sleepTv() {
        HomeButtonService s = instance;
        return s != null && s.performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN);
    }

    /** Our launcher has drawn its real content: the cover can go. */
    static void onHomeDrawn() {
        HomeButtonService s = instance;
        if (s != null) s.main.post(s::hideCover);
    }

    // Home-key launches as the system logs them (see class comment).
    private static final String HOME_START = "cat=[android.intent.category.HOME]";
    private static final String FROM_SYSTEM = "from uid 0";
    private volatile boolean watching;
    private Process logcat;

    @Override
    protected void onServiceConnected() {
        instance = this;
        if (checkSelfPermission(Manifest.permission.READ_LOGS) == PackageManager.PERMISSION_GRANTED) {
            watching = true;
            new Thread(this::watchSystemLog, "home-key-watch").start();
        } else {
            Log.w(TAG, "READ_LOGS not granted: falling back to window events (slower)");
        }
    }

    @Override
    public void onDestroy() {
        watching = false;
        if (logcat != null) logcat.destroy();
        hideCover();
        instance = null;
        super.onDestroy();
    }

    /** Follows the (quiet) system log buffer for Home-key launches; restarts logcat if it dies. */
    private void watchSystemLog() {
        while (watching) {
            // Only lines from now on: an old Home press must not trigger a jump.
            String since = new SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US).format(new Date());
            try {
                logcat = new ProcessBuilder("logcat", "-b", "system", "-v", "brief", "-T", since,
                        "-s", "ActivityTaskManager:I").redirectErrorStream(true).start();
                BufferedReader in = new BufferedReader(new InputStreamReader(logcat.getInputStream()));
                String line;
                while (watching && (line = in.readLine()) != null) {
                    if (line.contains(HOME_START) && line.trim().endsWith(FROM_SYSTEM)) {
                        main.post(this::onHomeKey);
                    }
                }
            } catch (IOException e) {
                Log.w(TAG, "system log watch failed", e);
            }
            if (watching) SystemClock.sleep(2000);
        }
    }

    private void onHomeKey() {
        amazonHomeAllowed = false;      // Home always means our launcher, even from Fire TV Home
        boolean alreadyHome = MainActivity.isShowing();
        if (!alreadyHome) showCover();  // the snapshot is from when we left; useless (stale) if we never did
        showHome(alreadyHome);
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return;
        CharSequence pkg = event.getPackageName();
        CharSequence cls = event.getClassName();
        if (pkg == null) return;

        boolean isAmazonHome = AMAZON_PKG.contentEquals(pkg)
                && cls != null && cls.toString().startsWith(AMAZON_HOME_CLASS_PREFIX);
        if (isAmazonHome) {
            if (!amazonHomeAllowed && !tooManyBounces()) {
                Log.i(TAG, "Amazon home came up; returning to ours");
                showCover();
                showHome(false);
            }
        } else if (!AMAZON_PKG.contentEquals(pkg) && !AMAZON_SETTINGS_PKG.contentEquals(pkg)
                && !isOverlay(pkg.toString())) {
            amazonHomeAllowed = false;
        }
    }

    // Windows that float over whatever's showing shouldn't count as "left the Fire TV home".
    private static boolean isOverlay(String pkg) {
        return pkg.equals("com.android.systemui") || pkg.equals("com.amazon.tv.ime")
                || pkg.startsWith("com.amazon.tv.quicksettings") || pkg.equals("android");
    }

    private boolean tooManyBounces() {
        long now = SystemClock.elapsedRealtime();
        long oldest = bounces[bounceIdx];
        bounces[bounceIdx] = now;
        bounceIdx = (bounceIdx + 1) % MAX_BOUNCES;
        if (oldest != 0 && now - oldest < BOUNCE_WINDOW_MS) {
            Log.w(TAG, "Redirect loop detected; leaving Amazon home alone");
            return true;
        }
        return false;
    }

    private void showHome(boolean toFirstTile) {
        Intent i = new Intent(this, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                        | Intent.FLAG_ACTIVITY_NO_ANIMATION)
                .putExtra(MainActivity.EXTRA_TO_FIRST_TILE, toFirstTile);
        startActivity(i);
    }

    private void showCover() {
        if (cover != null) return;
        cover = new ImageView(this);
        cover.setScaleType(ImageView.ScaleType.FIT_XY);
        if (snapshot != null && !snapshot.isRecycled()) cover.setImageBitmap(snapshot);
        else cover.setBackgroundColor(Color.BLACK);
        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN | WindowManager.LayoutParams.FLAG_FULLSCREEN,
                PixelFormat.OPAQUE);
        try {
            getSystemService(WindowManager.class).addView(cover, lp);
        } catch (RuntimeException e) {
            Log.w(TAG, "couldn't show cover", e);
            cover = null;
            return;
        }
        main.postDelayed(this::hideCover, COVER_TIMEOUT_MS);   // never leave it up
    }

    private void hideCover() {
        if (cover == null) return;
        final ImageView v = cover;
        cover = null;
        main.removeCallbacksAndMessages(null);
        v.animate().alpha(0f).setDuration(120).withEndAction(() -> {
            try {
                getSystemService(WindowManager.class).removeView(v);
            } catch (RuntimeException ignored) {
            }
        });
    }

    @Override
    public void onInterrupt() {
    }
}
