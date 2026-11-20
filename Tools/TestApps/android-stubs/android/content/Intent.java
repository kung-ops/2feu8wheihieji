package android.content;
public class Intent {
    public Intent() {}
    public Intent(Context c, Class<?> cls) {}
    public Intent(String action) {}
    public Intent putExtra(String k, String v) { return this; }
    public Intent putExtra(String k, int v) { return this; }
    public String getStringExtra(String k) { return null; }
    public int getIntExtra(String k, int d) { return d; }
}
