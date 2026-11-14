package com.rokucast.bridge;
import android.content.Context;
import android.content.SharedPreferences;
public final class KeyMap {
    private static final String PREFS="roku_cast_bridge";
    private KeyMap(){}
    public static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFS,Context.MODE_PRIVATE);
    }
    public static String actionFor(Context context,int code){
        return preferences(context).getString("key_"+code,Actions.NATIVE);
    }
    public static void setMapping(Context context,int code,String action){
        if(Actions.NATIVE.equals(action)) preferences(context).edit().remove("key_"+code).apply();
        else preferences(context).edit().putString("key_"+code,action).apply();
    }
    public static void clear(Context context){ preferences(context).edit().clear().apply(); }
}
