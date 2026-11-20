package com.kungops.counter;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.text.TextUtils;
import android.util.Log;
import android.view.View;
import android.widget.CheckBox;
import android.widget.CompoundButton;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends Activity {
    private int count;
    private int ticks;
    private boolean running;
    private TextView countView;
    private TextView ticksView;
    private SharedPreferences prefs;
    private final Handler handler = new Handler();

    private final Runnable ticker = new Runnable() {
        @Override public void run() {
            ticks++;
            ticksView.setText("ticks: " + ticks);
            if (running && ticks < 5) handler.postDelayed(this, 100);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        prefs = getSharedPreferences("counter", MODE_PRIVATE);
        count = prefs.getInt("count", 0);
        countView = (TextView) findViewById(R.id.count);
        ticksView = (TextView) findViewById(R.id.ticks);
        render();

        findViewById(R.id.plus).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { count++; save(); render(); }
        });
        findViewById(R.id.minus).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { count--; save(); render(); }
        });
        final EditText name = (EditText) findViewById(R.id.name);
        findViewById(R.id.greet).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                String n = name.getText().toString().trim();
                if (TextUtils.isEmpty(n)) n = "stranger";
                Toast.makeText(MainActivity.this, "Hello, " + n + "!", Toast.LENGTH_SHORT).show();
            }
        });
        CheckBox fast = (CheckBox) findViewById(R.id.fast);
        fast.setOnCheckedChangeListener(new CompoundButton.OnCheckedChangeListener() {
            @Override public void onCheckedChanged(CompoundButton b, boolean on) {
                running = on;
                if (on) { ticks = 0; handler.postDelayed(ticker, 100); } else { handler.removeCallbacks(ticker); }
            }
        });
        findViewById(R.id.open).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                Intent i = new Intent(MainActivity.this, SecondActivity.class);
                i.putExtra("count", count);
                i.putExtra("who", "main screen");
                startActivity(i);
            }
        });
        findViewById(R.id.about).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                new AlertDialog.Builder(MainActivity.this)
                        .setTitle("This phone")
                        .setMessage(Build.MODEL + ", Android " + Build.VERSION.RELEASE + " (SDK " + Build.VERSION.SDK_INT + ")\n" + memoryInfo())
                        .setPositiveButton("OK", null)
                        .show();
            }
        });
        Log.d("Counter", "onCreate done, count=" + count);
        System.out.println("memory: " + memoryInfo());
    }

    String memoryInfo() {
        ActivityManager am = (ActivityManager) getSystemService("activity");
        ActivityManager.MemoryInfo mi = new ActivityManager.MemoryInfo();
        am.getMemoryInfo(mi);
        long heap = Runtime.getRuntime().maxMemory() / (1024 * 1024);
        return "RAM " + (mi.totalMem / (1024 * 1024)) + " MB, app heap " + heap + " MB, class " + am.getMemoryClass()
                + (am.isLowRamDevice() ? ", low-RAM device" : "");
    }

    public void onResetClicked(View v) {
        count = 0;
        save();
        render();
    }

    private void save() { prefs.edit().putInt("count", count).apply(); }

    private void render() { countView.setText(String.valueOf(count)); }

    @Override protected void onPause() { super.onPause(); Log.d("Counter", "onPause"); }
    @Override protected void onResume() { super.onResume(); Log.d("Counter", "onResume"); }
}
