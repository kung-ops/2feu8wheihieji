package android.content;
public interface DialogInterface {
    int BUTTON_POSITIVE = -1;
    void dismiss();
    interface OnClickListener { void onClick(DialogInterface d, int which); }
}
