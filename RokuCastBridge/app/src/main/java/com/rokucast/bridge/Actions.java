package com.rokucast.bridge;
public final class Actions {
    public static final String NATIVE="native", BACK="back", HOME="home",
        PLAY_PAUSE="play_pause", VOLUME_UP="volume_up", VOLUME_DOWN="volume_down",
        VOLUME_MUTE="volume_mute", RECENTS="recents", NOTIFICATIONS="notifications",
        QUICK_SETTINGS="quick_settings", YOUTUBE="youtube", NETFLIX="netflix", DISNEY="disney";
    public static final String[] VALUES={BACK, HOME, PLAY_PAUSE, VOLUME_UP,
        VOLUME_DOWN, VOLUME_MUTE, RECENTS, NOTIFICATIONS, QUICK_SETTINGS,
        YOUTUBE, NETFLIX, DISNEY};
    public static final String[] LABELS={"Back","Google TV Home","Play / Pause",
        "Volume +","Volume -","Mute","Recent Apps","Notifications",
        "Quick Settings","YouTube","Netflix","Disney+"};
    private Actions(){}
}
