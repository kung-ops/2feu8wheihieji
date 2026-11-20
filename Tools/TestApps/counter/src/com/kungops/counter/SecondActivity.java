package com.kungops.counter;

import android.app.Activity;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class SecondActivity extends Activity {
    enum Shape { CIRCLE, SQUARE, TRIANGLE }

    interface Op { long apply(long a, long b); }

    static abstract class Named {
        abstract String name();
        String hello() { return "I am " + name(); }
    }

    static final class Cat extends Named {
        String name() { return "cat"; }
    }

    static int calls;
    static { calls = 41; }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        calls++;
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int c = getIntent().getIntExtra("count", -1);
        add(root, "Second screen: count=" + c + " from " + getIntent().getStringExtra("who"));

        List<Integer> primes = new ArrayList<Integer>();
        for (int n = 2; primes.size() < 10; n++) {
            boolean p = true;
            for (int d = 2; d * d <= n; d++) if (n % d == 0) { p = false; break; }
            if (p) primes.add(n);
        }
        add(root, "primes=" + primes);

        Map<String, Integer> words = new HashMap<String, Integer>();
        for (String w : "the cat and the hat and the bat".split(" ")) {
            Integer old = words.get(w);
            words.put(w, old == null ? 1 : old + 1);
        }
        add(root, "the=" + words.get("the") + " and=" + words.get("and"));

        StringBuilder sb = new StringBuilder();
        for (Shape s : Shape.values()) sb.append(s.name().toLowerCase()).append(s.ordinal()).append(',');
        add(root, "shapes=" + sb);

        long fact = 1;
        for (int i = 2; i <= 20; i++) fact *= i;
        add(root, "20!=" + fact);
        add(root, String.format("sqrt2=%.3f", Math.sqrt(2)));

        int[] arr = {5, 3, 9, 1, 7};
        Arrays.sort(arr);
        add(root, "sorted=" + Arrays.toString(arr));

        try {
            Integer.parseInt("12x");
            add(root, "parse: no error?!");
        } catch (NumberFormatException e) {
            add(root, "parse error caught");
        }

        String mode = "fast";
        switch (mode) {
            case "slow": add(root, "mode slow"); break;
            case "fast": add(root, "mode fast"); break;
            default: add(root, "mode ?");
        }

        Op mul = new Op() { public long apply(long a, long x) { return a * x; } };
        add(root, "op=" + mul.apply(6, 7) + " " + new Cat().hello() + " calls=" + calls);

        double avg = 0;
        for (int i = 0; i < 1000; i++) avg += i;
        avg /= 1000;
        char[] chars = {'o', 'k'};
        add(root, "avg=" + avg + " " + new String(chars) + " " + (char) ('A' + 2));

        File note = new File(getFilesDir(), "note.txt");
        try {
            FileOutputStream out = new FileOutputStream(note);
            out.write(("hello file " + c).getBytes());
            out.close();
            FileInputStream in = new FileInputStream(note);
            byte[] buf = new byte[64];
            int n = in.read(buf);
            in.close();
            add(root, "file=" + new String(buf, 0, n) + " exists=" + note.exists() + " len=" + note.length());
        } catch (IOException e) {
            add(root, "file error " + e);
        }
        add(root, "sandboxed=" + !new File("/etc/hosts").exists());

        Button back = new Button(this);
        back.setText("Back");
        back.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { finish(); }
        });
        root.addView(back);
        setContentView(root);
        setTitle("Second");
    }

    private void add(LinearLayout root, String text) {
        TextView t = new TextView(this);
        t.setText(text);
        root.addView(t);
    }
}
