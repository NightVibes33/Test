package com.rokucast.bridge;
import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.KeyEvent;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
public class MainActivity extends Activity {
    private TextView status,learned,mappings;
    private String pendingAction=null;
    @Override protected void onCreate(Bundle state){
        super.onCreate(state);
        ScrollView scroll=new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(Color.rgb(14,19,29));
        LinearLayout body=new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(54,36,54,40);
        scroll.addView(body);
        addText(body,"RokuCast Bridge",36,Color.WHITE);
        addText(body,"Turn incoming Roku remote buttons into Google TV actions",19,0xFFB9C9DD);
        status=addText(body,"Waiting for input...",18,0xFF7DD9C2);
        learned=addText(body,"",20,Color.WHITE);
        addText(body,"1  Connect an input source",24,Color.WHITE);
        addText(body,"First try HDMI-CEC on the Roku TV and Chromecast. If no button events arrive, a Roku infrared remote needs a USB IR-to-keyboard receiver such as FLIRC and a suitable hub. Roku Wi-Fi voice remotes cannot be paired directly.",17,0xFFC4CDD9);
        addText(body,"2  Enable remapping (optional)",24,Color.WHITE);
        addText(body,"Android D-pad/OK/Back often already work. Enable RokuCast key remapper in Accessibility settings only if custom keys need mapping.",17,0xFFC4CDD9);
        button(body,"Open Accessibility settings",()->{
            try{startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS));}
            catch(RuntimeException e){status.setText("Could not open settings");}
        });
        addText(body,"3  Learn remote button mapping",24,Color.WHITE);
        addText(body,"Select an action then press the remote button you want to assign. Press Back to cancel.",17,0xFFC4CDD9);
        for(int i=0;i<Actions.VALUES.length;i++){
            final String action=Actions.VALUES[i],label=Actions.LABELS[i];
            button(body,"Learn button: "+label,()->{
                pendingAction=action;
                learned.setText("Press physical remote button for: "+label);
            });
        }
        mappings=addText(body,"",17,0xFFB9C9DD);
        button(body,"Clear learned mappings",()->{
            KeyMap.clear(this);
            pendingAction=null;
            learned.setText("Mappings cleared");
            showMappings();
        });
        setContentView(scroll);
        showMappings();
    }
    @Override protected void onResume(){
        super.onResume();
        if(status!=null){
            String key=KeyMap.preferences(this).getString("last_key","none");
            status.setText("Last key seen by remapper: "+key);
        }
    }
    @Override public boolean dispatchKeyEvent(KeyEvent e){
        if(e.getAction()==KeyEvent.ACTION_DOWN && e.getRepeatCount()==0){
            int code=e.getKeyCode();
            if(pendingAction!=null){
                if(code==KeyEvent.KEYCODE_BACK || code==KeyEvent.KEYCODE_ESCAPE){
                    pendingAction=null;
                    learned.setText("Learning canceled");
                    return true;
                }
                String action=pendingAction;
                pendingAction=null;
                KeyMap.setMapping(this,code,action);
                learned.setText("Saved: "+KeyEvent.keyCodeToString(code)+" -> "+action);
                showMappings();
                return true;
            }
            if(status!=null)status.setText("Received: "+KeyEvent.keyCodeToString(code)+" ("+code+")");
        }
        return super.dispatchKeyEvent(e);
    }
    private void showMappings(){
        if(mappings==null)return;
        StringBuilder s=new StringBuilder("Learned mappings:\n");
        for(String key:KeyMap.preferences(this).getAll().keySet()){
            if(key.startsWith("key_")){
                try{
                    int c=Integer.parseInt(key.substring(4));
                    s.append("  ").append(KeyEvent.keyCodeToString(c)).append(" -> ")
                     .append(KeyMap.actionFor(this,c)).append("\n");
                }catch(NumberFormatException ignored){}
            }
        }
        mappings.setText(s.toString());
    }
    private TextView addText(LinearLayout body,String value,int size,int color){
        TextView t=new TextView(this);
        t.setText(value);
        t.setTextSize(size);
        t.setTextColor(color);
        t.setPadding(0,12,0,14);
        body.addView(t);
        return t;
    }
    private void button(LinearLayout parent,String title,Runnable action){
        Button b=new Button(this);
        b.setText(title);
        b.setAllCaps(false);
        b.setTextSize(17);
        b.setGravity(Gravity.CENTER_VERTICAL|Gravity.START);
        LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);
        p.setMargins(0,6,0,6);
        parent.addView(b,p);
        b.setOnClickListener(v->action.run());
    }
}
