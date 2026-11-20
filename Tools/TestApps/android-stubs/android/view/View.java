package android.view;
public class View {
    public static final int VISIBLE = 0, INVISIBLE = 4, GONE = 8;
    public View(android.content.Context c) {}
    public int getId() { return 0; }
    public void setId(int id) {}
    public void setVisibility(int v) {}
    public void setOnClickListener(OnClickListener l) {}
    public void setEnabled(boolean e) {}
    public void setBackgroundColor(int c) {}
    public void setPadding(int l, int t, int r, int b) {}
    public interface OnClickListener { void onClick(View v); }
}
