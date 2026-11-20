package com.kungops.memtest;

import android.app.Activity;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

/** Fills the heap with 1 MB blocks until Java throws OutOfMemoryError. */
public class MainActivity extends Activity {
    private TextView status;
    private List<byte[]> blocks = new ArrayList<byte[]>();

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        status = new TextView(this);
        status.setText("max heap " + (Runtime.getRuntime().maxMemory() >> 20) + " MB");
        root.addView(status);
        Button fill = new Button(this);
        fill.setText("Fill memory");
        fill.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { fill(); }
        });
        root.addView(fill);
        Button free = new Button(this);
        free.setText("Free memory");
        free.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                blocks.clear();
                System.gc();
                status.setText("freed, used " + used() + " MB");
            }
        });
        root.addView(free);
        Button hold = new Button(this);
        hold.setText("Hold 50 MB");
        hold.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                for (int i = 0; i < 50; i++) blocks.add(new byte[1024 * 1024]);
                status.setText("holding " + blocks.size() + " MB");
            }
        });
        root.addView(hold);
        setContentView(root);
    }

    private long used() {
        Runtime r = Runtime.getRuntime();
        return (r.totalMemory() - r.freeMemory()) >> 20;
    }

    private void fill() {
        int mb = 0;
        try {
            while (mb < 4096) {
                byte[] block = new byte[1024 * 1024];
                block[mb % 1000] = (byte) mb;
                blocks.add(block);
                mb++;
            }
            status.setText("no limit hit after " + mb + " MB");
        } catch (OutOfMemoryError e) {
            int got = blocks.size();
            blocks.clear();
            status.setText("OutOfMemoryError after " + got + " MB");
        }
    }
}
