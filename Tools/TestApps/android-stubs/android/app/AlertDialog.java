package android.app;
public class AlertDialog {
    public void show() {}
    public static class Builder {
        public Builder(android.content.Context c) {}
        public Builder setTitle(CharSequence t) { return this; }
        public Builder setMessage(CharSequence t) { return this; }
        public Builder setPositiveButton(CharSequence t, android.content.DialogInterface.OnClickListener l) { return this; }
        public Builder setNegativeButton(CharSequence t, android.content.DialogInterface.OnClickListener l) { return this; }
        public AlertDialog show() { return null; }
        public AlertDialog create() { return null; }
    }
}
