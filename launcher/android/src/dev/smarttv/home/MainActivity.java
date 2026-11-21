package dev.smarttv.home;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.media.AudioAttributes;
import android.media.SoundPool;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;
import android.view.KeyEvent;
import android.view.PixelCopy;
import android.view.View;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.Toast;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;

/**
 * Full-screen WebView showing assets/www/index.html. The remote's buttons are handled here
 * natively and forwarded to the page as tvKey(...), so the WebView never does its own focus
 * navigation. The page calls back through the "TV" bridge to launch apps, play radio and
 * play UI sounds.
 */
public class MainActivity extends Activity implements Radio.Listener {
    private static final String TAG = "SmartTvHome";
    static final ComponentName AMAZON_HOME =
            new ComponentName("com.amazon.tv.launcher", "com.amazon.tv.launcher.ui.HomeActivity_vNext");

    private final Handler main = new Handler(Looper.getMainLooper());
    private WebView web;
    private Radio radio;
    private SoundPool sounds;
    private int soundMove, soundSelect;
    private static volatile boolean showing;   // in front right now (read by the Home service)
    private boolean resumed;
    private long resumedAt;
    static final String EXTRA_TO_FIRST_TILE = "toFirstTile";

    static boolean isShowing() {
        return showing;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().getDecorView().setBackgroundColor(Color.BLACK);

        web = new WebView(this);
        web.setBackgroundColor(Color.BLACK);
        web.setFocusable(false);
        web.setFocusableInTouchMode(false);
        web.setVerticalScrollBarEnabled(false);
        web.setHorizontalScrollBarEnabled(false);
        web.setLayerType(View.LAYER_TYPE_HARDWARE, null);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setTextZoom(100);   // ignore the system font-size setting; the page scales itself
        s.setAllowFileAccess(true);

        radio = new Radio(this, this);
        loadSounds();

        web.addJavascriptInterface(new Bridge(), "TV");
        web.loadUrl("file:///android_asset/www/index.html");
        setContentView(web);
    }

    private void loadSounds() {
        sounds = new SoundPool.Builder()
                .setMaxStreams(2)
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build())
                .build();
        try {
            soundMove = sounds.load(getAssets().openFd("www/sounds/move.wav"), 1);
            soundSelect = sounds.load(getAssets().openFd("www/sounds/select.wav"), 1);
        } catch (IOException e) {
            Log.w(TAG, "UI sounds unavailable", e);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        resumed = true;
        showing = true;
        resumedAt = android.os.SystemClock.uptimeMillis();
        HomeButtonService.clearAmazonHome();
        web.onResume();
        web.resumeTimers();
        js("window.tvResume && tvResume()");
        // Once the real page has drawn, drop the snapshot cover the Home service put up.
        web.postVisualStateCallback(0, new WebView.VisualStateCallback() {
            @Override
            public void onComplete(long requestId) {
                Log.i(TAG, "drawn " + (android.os.SystemClock.uptimeMillis() - resumedAt) + " ms after resume");
                main.postDelayed(HomeButtonService::onHomeDrawn, 80);
            }
        });
    }

    @Override
    protected void onPause() {
        resumed = false;
        showing = false;
        // Another app is in front: stop JS timers and rendering. A/B tested: no measurable effect
        // on how fast we come back or how fast Android stops the app being left.
        web.onPause();
        web.pauseTimers();
        super.onPause();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        // Home pressed while we're already showing: go back to the first tile. Coming back
        // from an app, keep everything where it was (it matches the snapshot cover).
        if (resumed || intent.getBooleanExtra(EXTRA_TO_FIRST_TILE, false)) js("window.tvHome && tvHome()");
    }

    @Override
    protected void onDestroy() {
        radio.stop();
        sounds.release();
        super.onDestroy();
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        String key = keyName(event.getKeyCode());
        if (key == null) return super.dispatchKeyEvent(event);   // volume etc.
        if (event.getAction() == KeyEvent.ACTION_DOWN) {
            boolean repeatable = key.equals("left") || key.equals("right") || key.equals("up") || key.equals("down");
            if (event.getRepeatCount() == 0 || repeatable) js("tvKey('" + key + "')");
        }
        return true;   // we're the home screen: Back and friends stop here
    }

    private static String keyName(int code) {
        switch (code) {
            case KeyEvent.KEYCODE_DPAD_LEFT: return "left";
            case KeyEvent.KEYCODE_DPAD_RIGHT: return "right";
            case KeyEvent.KEYCODE_DPAD_UP: return "up";
            case KeyEvent.KEYCODE_DPAD_DOWN: return "down";
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_NUMPAD_ENTER:
            case KeyEvent.KEYCODE_BUTTON_A:
                return "enter";
            case KeyEvent.KEYCODE_BACK: return "back";
            case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE: return "playpause";
            default: return null;
        }
    }

    private void js(String script) {
        if (web != null) web.evaluateJavascript(script, null);
    }

    @Override
    public void onRadioState(String state, String stationId) {
        main.post(() -> {
            // Radio has no picture, so nothing else tells Android someone is listening: without this
            // the TV's sleep timer (14 min without a button press) turns it off mid-song.
            // Only applies while our window is showing; stopped/error hands the timer back.
            if (state.equals("playing") || state.equals("loading")) {
                getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            } else {
                getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            }
            js("window.tvRadio && tvRadio(" + JSONObject.quote(state) + ","
                    + JSONObject.quote(stationId == null ? "" : stationId) + ")");
        });
    }

    /**
     * Turns a tile's `open` spec into an Intent, or null if the target isn't on the device.
     * Spec keys: pkg | component ("pkg/.Class") | action | label (match an app by name) | amazonHome.
     */
    private Intent resolve(JSONObject o) {
        PackageManager pm = getPackageManager();
        Intent i = null;
        if (o.optBoolean("amazonHome")) {
            i = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).setComponent(AMAZON_HOME);
        } else if (o.has("component")) {
            i = new Intent(Intent.ACTION_MAIN).setComponent(ComponentName.unflattenFromString(o.optString("component")));
        } else if (o.has("action")) {
            i = new Intent(o.optString("action"));
        } else if (o.has("pkg")) {
            String pkg = o.optString("pkg");
            i = pm.getLeanbackLaunchIntentForPackage(pkg);
            if (i == null) i = pm.getLaunchIntentForPackage(pkg);
        } else if (o.has("label")) {
            String label = o.optString("label");
            Intent query = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER);
            for (ResolveInfo ri : pm.queryIntentActivities(query, 0)) {
                if (label.equalsIgnoreCase(String.valueOf(ri.loadLabel(pm)).trim())) {
                    i = pm.getLeanbackLaunchIntentForPackage(ri.activityInfo.packageName);
                    break;
                }
            }
        }
        if (i != null && i.resolveActivity(pm) == null) i = null;
        return i;
    }

    private void launch(JSONObject o) {
        Intent i = resolve(o);
        if (i == null && o.has("store")) {
            i = new Intent(Intent.ACTION_VIEW,
                    Uri.parse("amzn://apps/android?s=" + Uri.encode(o.optString("store"))));
        }
        if (i == null) {
            Toast.makeText(this, "Not installed", Toast.LENGTH_SHORT).show();
            return;
        }
        // Fire TV Home, and Settings (which lives in Amazon's launcher), shouldn't bounce back.
        if (o.optBoolean("amazonHome") || o.optBoolean("allowAmazon")) HomeButtonService.allowAmazonHome();
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            startActivity(i);
        } catch (ActivityNotFoundException | SecurityException e) {
            Log.w(TAG, "launch failed: " + o, e);
            Toast.makeText(this, "Couldn't open that", Toast.LENGTH_SHORT).show();
        }
    }

    /** Grab what's on screen so the Home service can show it instantly on the way back. */
    private void snapshotThen(Runnable next) {
        View root = getWindow().getDecorView();
        if (root.getWidth() == 0) {
            next.run();
            return;
        }
        Bitmap bmp = Bitmap.createBitmap(root.getWidth(), root.getHeight(), Bitmap.Config.ARGB_8888);
        try {
            PixelCopy.request(getWindow(), bmp, result -> {
                if (result == PixelCopy.SUCCESS) HomeButtonService.setSnapshot(bmp);
                else bmp.recycle();
                next.run();
            }, main);
        } catch (IllegalArgumentException e) {
            bmp.recycle();
            next.run();
        }
    }

    private class Bridge {
        @JavascriptInterface
        public boolean isInstalled(String spec) {
            try {
                return resolve(new JSONObject(spec)) != null;
            } catch (JSONException e) {
                return false;
            }
        }

        /** The name the TV advertises (what iPhones show under Screen Mirroring for AirPlay). */
        @JavascriptInterface
        public String deviceName() {
            String name = Settings.Global.getString(getContentResolver(), "device_name");
            return name != null ? name : "";
        }

        @JavascriptInterface
        public void launch(final String spec) {
            main.post(() -> {
                try {
                    JSONObject o = new JSONObject(spec);
                    snapshotThen(() -> MainActivity.this.launch(o));
                } catch (JSONException e) {
                    Log.w(TAG, "bad launch spec: " + spec, e);
                }
            });
        }

        @JavascriptInterface
        public boolean powerOff() {
            return HomeButtonService.sleepTv();
        }

        @JavascriptInterface
        public void sound(String name) {
            int id = "select".equals(name) ? soundSelect : soundMove;
            if (id != 0) sounds.play(id, 0.8f, 0.8f, 1, 0, 1f);
        }

        @JavascriptInterface
        public void radioPlay(String id, String url) {
            main.post(() -> radio.play(id, url));
        }

        @JavascriptInterface
        public void radioStop() {
            main.post(radio::stop);
        }
    }
}
