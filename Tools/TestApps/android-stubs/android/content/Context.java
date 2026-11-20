package android.content;
public abstract class Context {
    public static final int MODE_PRIVATE = 0;
    public abstract SharedPreferences getSharedPreferences(String name, int mode);
    public abstract String getPackageName();
    public abstract String getString(int resId);
    public abstract Object getSystemService(String name);
    public abstract java.io.File getFilesDir();
    public abstract java.io.File getCacheDir();
    public abstract void startActivity(Intent intent);
}
