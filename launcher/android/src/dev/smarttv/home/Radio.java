package dev.smarttv.home;

import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

/**
 * Internet radio on the platform MediaPlayer (handles MP3/AAC/HE-AAC streams natively, far
 * lighter than WebView audio). Holds audio focus while playing, so it stops by itself when
 * another app starts playing and ducks under short sounds.
 */
final class Radio implements MediaPlayer.OnPreparedListener, MediaPlayer.OnErrorListener,
        AudioManager.OnAudioFocusChangeListener {
    private static final String TAG = "SmartTvHome";

    /** States sent to the page: loading | playing | stopped | error. */
    interface Listener {
        void onRadioState(String state, String stationId);
    }

    private final AudioManager audio;
    private final Listener listener;
    private final AudioFocusRequest focusRequest;
    private static final long CONNECT_TIMEOUT_MS = 15_000;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Runnable connectTimeout = this::onConnectTimeout;
    private MediaPlayer player;
    private String stationId;

    Radio(Context context, Listener listener) {
        this.audio = context.getSystemService(AudioManager.class);
        this.listener = listener;
        AudioAttributes attrs = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build();
        this.focusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener(this)
                .build();
    }

    void play(String id, String url) {
        release();
        stationId = id;
        listener.onRadioState("loading", id);
        try {
            player = new MediaPlayer();
            player.setAudioAttributes(focusRequest.getAudioAttributes());
            player.setOnPreparedListener(this);
            player.setOnErrorListener(this);
            player.setDataSource(url);
            player.prepareAsync();
            main.postDelayed(connectTimeout, CONNECT_TIMEOUT_MS);   // a stuck prepare never reports an error
        } catch (Exception e) {
            Log.w(TAG, "radio: can't open " + url, e);
            fail();
        }
    }

    void stop() {
        String id = stationId;
        release();
        if (id != null) listener.onRadioState("stopped", id);
    }

    @Override
    public void onPrepared(MediaPlayer mp) {
        if (mp != player) return;
        main.removeCallbacks(connectTimeout);
        if (audio.requestAudioFocus(focusRequest) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            stop();
            return;
        }
        mp.start();
        listener.onRadioState("playing", stationId);
    }

    @Override
    public boolean onError(MediaPlayer mp, int what, int extra) {
        Log.w(TAG, "radio error " + what + "/" + extra + " on " + stationId);
        if (mp == player) fail();
        return true;
    }

    @Override
    public void onAudioFocusChange(int change) {
        if (player == null) return;
        switch (change) {
            case AudioManager.AUDIOFOCUS_LOSS:
            case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
                stop();                             // an app started playing
                break;
            case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
                player.setVolume(0.25f, 0.25f);
                break;
            case AudioManager.AUDIOFOCUS_GAIN:
                player.setVolume(1f, 1f);
                break;
        }
    }

    private void onConnectTimeout() {
        Log.w(TAG, "radio: no audio after " + CONNECT_TIMEOUT_MS + " ms on " + stationId);
        fail();
    }

    private void fail() {
        String id = stationId;
        release();
        listener.onRadioState("error", id);
    }

    private void release() {
        main.removeCallbacks(connectTimeout);
        if (player != null) {
            player.setOnPreparedListener(null);
            player.setOnErrorListener(null);
            player.release();
            player = null;
            audio.abandonAudioFocusRequest(focusRequest);
        }
        stationId = null;
    }
}
