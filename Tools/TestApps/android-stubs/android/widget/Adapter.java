package android.widget;
public interface Adapter {
    int getCount();
    Object getItem(int position);
    long getItemId(int position);
    android.view.View getView(int position, android.view.View convertView, android.view.ViewGroup parent);
}
