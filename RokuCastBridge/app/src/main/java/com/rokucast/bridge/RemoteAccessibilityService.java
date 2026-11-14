package com.rokucast.bridge;
import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.media.AudioManager;
import android.os.SystemClock;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

/**
 * Remaps only key events delivered to Android TV by a HID receiver or HDMI-CEC.
 * Does not pair with Roku Wi-Fi remotes or receive IR on its own.
 */
public class RemoteAccessibilityService extends AccessibilityService {
    private long ignoreMediaUntil=0;
    @Override public void onAccessibilityEvent(AccessibilityEvent e) {}
    @Override public void onInterrupt() {}
    @Override public boolean onKeyEvent(KeyEvent e) {
        if(e.getAction()!=KeyEvent.ACTION_DOWN || e.getRepeatCount()>0) return false;
        int key=e.getKeyCode();
        KeyMap.preferences(this).edit().putString("last_key",KeyEvent.keyCodeToString(key)).apply();
        String action=KeyMap.actionFor(this,key);
        if(Actions.NATIVE.equals(action)) return false;
        if(action.equals(Actions.PLAY_PAUSE) &&
           key==KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE &&
           SystemClock.uptimeMillis()<ignoreMediaUntil) return false;
        switch(action) {
            case Actions.BACK: return performGlobalAction(GLOBAL_ACTION_BACK);
            case Actions.HOME: return performGlobalAction(GLOBAL_ACTION_HOME);
            case Actions.RECENTS: return performGlobalAction(GLOBAL_ACTION_RECENTS);
            case Actions.NOTIFICATIONS: return performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS);
            case Actions.QUICK_SETTINGS: return performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS);
            case Actions.VOLUME_UP: return adjust(AudioManager.ADJUST_RAISE);
            case Actions.VOLUME_DOWN: return adjust(AudioManager.ADJUST_LOWER);
            case Actions.VOLUME_MUTE: return adjust(AudioManager.ADJUST_TOGGLE_MUTE);
            case Actions.PLAY_PAUSE: return playPause();
            case Actions.YOUTUBE: return launch("com.google.android.youtube.tv");
            case Actions.NETFLIX: return launch("com.netflix.ninja") || launch("com.netflix.mediaclient");
            case Actions.DISNEY: return launch("com.disney.disneyplus");
            default: return false;
        }
    }
    private boolean adjust(int direction) {
        AudioManager a=(AudioManager)getSystemService(AUDIO_SERVICE);
        if(a==null)return false;
        a.adjustSuggestedStreamVolume(direction,AudioManager.USE_DEFAULT_STREAM_TYPE,0);
        return true;
    }
    private boolean playPause() {
        AudioManager a=(AudioManager)getSystemService(AUDIO_SERVICE);
        if(a==null)return false;
        ignoreMediaUntil=SystemClock.uptimeMillis()+650;
        long t=SystemClock.uptimeMillis();
        a.dispatchMediaKeyEvent(new KeyEvent(t,t,KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,0));
        a.dispatchMediaKeyEvent(new KeyEvent(t,t+1,KeyEvent.ACTION_UP,KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,0));
        return true;
    }
    private boolean launch(String pkg){
        Intent intent=getPackageManager().getLeanbackLaunchIntentForPackage(pkg);
        if(intent==null)intent=getPackageManager().getLaunchIntentForPackage(pkg);
        if(intent==null)return false;
        try{
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            return true;
        }catch(RuntimeException e){return false;}
    }
}
