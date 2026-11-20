package com.kungops.todo;

import android.app.Activity;
import android.os.Bundle;
import android.view.View;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.EditText;
import android.widget.ListView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;

/** A ListView + ArrayAdapter to-do list: add, tap to finish (remove). */
public class MainActivity extends Activity {
    private final ArrayList<String> tasks = new ArrayList<String>();
    private ArrayAdapter<String> adapter;
    private TextView count;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setContentView(R.layout.activity_main);
        count = (TextView) findViewById(R.id.count);
        final EditText input = (EditText) findViewById(R.id.input);
        ListView list = (ListView) findViewById(R.id.list);
        tasks.add("Buy milk");
        tasks.add("Call mum");
        adapter = new ArrayAdapter<String>(this, R.layout.row, R.id.row_text, tasks);
        list.setAdapter(adapter);
        list.setEmptyView(findViewById(R.id.empty));
        list.setOnItemClickListener(new AdapterView.OnItemClickListener() {
            @Override public void onItemClick(AdapterView<?> parent, View view, int position, long id) {
                String done = tasks.remove(position);
                adapter.notifyDataSetChanged();
                Toast.makeText(MainActivity.this, "Done: " + done + " (row " + id + ")", Toast.LENGTH_SHORT).show();
                update();
            }
        });
        findViewById(R.id.add).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                String t = input.getText().toString().trim();
                if (t.length() == 0) t = "Task " + (tasks.size() + 1);
                adapter.add(t);
                input.setText("");
                update();
            }
        });
        update();
    }

    private void update() {
        count.setText(adapter.getCount() + (adapter.getCount() == 1 ? " task" : " tasks"));
    }
}
