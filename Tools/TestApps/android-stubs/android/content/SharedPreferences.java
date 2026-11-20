package android.content;
public interface SharedPreferences {
    int getInt(String k, int d);
    String getString(String k, String d);
    boolean getBoolean(String k, boolean d);
    long getLong(String k, long d);
    Editor edit();
    interface Editor {
        Editor putInt(String k, int v);
        Editor putString(String k, String v);
        Editor putBoolean(String k, boolean v);
        Editor putLong(String k, long v);
        Editor remove(String k);
        Editor clear();
        void apply();
        boolean commit();
    }
}
