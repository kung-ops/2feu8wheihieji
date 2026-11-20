package com.kungops.tapgame;

import android.app.Activity;
import android.os.Bundle;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setContentView(new GameView(this));
        setTitle("Tap Ball");
    }
}
