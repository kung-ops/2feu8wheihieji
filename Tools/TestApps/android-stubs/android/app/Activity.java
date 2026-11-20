package android.app;
public class Activity extends android.content.ContextWrapper {
    protected void onCreate(android.os.Bundle b) {}
    protected void onStart() {}
    protected void onResume() {}
    protected void onPause() {}
    protected void onStop() {}
    protected void onDestroy() {}
    protected void onRestart() {}
    public void onBackPressed() {}
    public void setContentView(int id) {}
    public void setContentView(android.view.View v) {}
    public <T extends android.view.View> T findViewById(int id) { return null; }
    public void setTitle(CharSequence t) {}
    public void finish() {}
    public android.content.Intent getIntent() { return null; }
    public void runOnUiThread(Runnable r) {}
}
