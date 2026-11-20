package android.widget;
public class AdapterView<T extends Adapter> extends android.view.ViewGroup {
    public AdapterView(android.content.Context c) { super(c); }
    public void setAdapter(T a) {}
    public T getAdapter() { return null; }
    public Object getItemAtPosition(int p) { return null; }
    public void setOnItemClickListener(OnItemClickListener l) {}
    public void setEmptyView(android.view.View v) {}
    public interface OnItemClickListener { void onItemClick(AdapterView<?> parent, android.view.View view, int position, long id); }
}
