package android.graphics;
public class Paint {
    public static final int ANTI_ALIAS_FLAG = 1;
    public Paint() {}
    public Paint(int flags) {}
    public void setColor(int c) {}
    public int getColor() { return 0; }
    public void setStyle(Style s) {}
    public void setStrokeWidth(float w) {}
    public void setTextSize(float s) {}
    public void setTextAlign(Align a) {}
    public void setAntiAlias(boolean a) {}
    public float measureText(String s) { return 0; }
    public enum Style { FILL, STROKE, FILL_AND_STROKE }
    public enum Align { LEFT, CENTER, RIGHT }
}
