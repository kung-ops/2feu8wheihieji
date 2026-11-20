package android.content;
public class ContextWrapper extends Context {
    public SharedPreferences getSharedPreferences(String name, int mode) { return null; }
    public String getPackageName() { return null; }
    public String getString(int resId) { return null; }
    public Object getSystemService(String name) { return null; }
    public java.io.File getFilesDir() { return null; }
    public java.io.File getCacheDir() { return null; }
    public void startActivity(Intent intent) {}
}
