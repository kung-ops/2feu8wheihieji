package android.graphics;
public class Canvas {
    public Canvas() {}
    public Canvas(Bitmap b) {}
    public int getWidth() { return 0; }
    public int getHeight() { return 0; }
    public void drawColor(int c) {}
    public void drawRect(float l, float t, float r, float b, Paint p) {}
    public void drawRect(RectF r, Paint p) {}
    public void drawRoundRect(RectF r, float rx, float ry, Paint p) {}
    public void drawCircle(float cx, float cy, float r, Paint p) {}
    public void drawLine(float x0, float y0, float x1, float y1, Paint p) {}
    public void drawText(String s, float x, float y, Paint p) {}
    public void drawPath(Path path, Paint p) {}
    public void drawBitmap(Bitmap b, float l, float t, Paint p) {}
    public void drawArc(RectF r, float start, float sweep, boolean useCenter, Paint p) {}
    public int save() { return 0; }
    public void restore() {}
    public void translate(float dx, float dy) {}
    public void rotate(float d) {}
}
