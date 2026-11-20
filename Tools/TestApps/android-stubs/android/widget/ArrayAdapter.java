package android.widget;
public class ArrayAdapter<T> extends BaseAdapter {
    public ArrayAdapter(android.content.Context c, int resource) {}
    public ArrayAdapter(android.content.Context c, int resource, java.util.List<T> objects) {}
    public ArrayAdapter(android.content.Context c, int resource, int textViewResourceId, java.util.List<T> objects) {}
    public ArrayAdapter(android.content.Context c, int resource, T[] objects) {}
    public void add(T o) {}
    public void remove(T o) {}
    public void clear() {}
    public int getCount() { return 0; }
    public T getItem(int p) { return null; }
    public long getItemId(int p) { return p; }
    public android.view.View getView(int p, android.view.View v, android.view.ViewGroup g) { return null; }
}
