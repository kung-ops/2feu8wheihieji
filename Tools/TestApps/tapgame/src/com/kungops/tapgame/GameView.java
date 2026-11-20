package com.kungops.tapgame;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.view.MotionEvent;
import android.view.View;

/** A tiny game drawn with Canvas: a bouncing ball, tap it to score. */
public class GameView extends View {
    private final Paint ball = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint frame = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path arrow = new Path();
    private final RectF bar = new RectF();
    private float x, y, vx, vy, radius;
    private int w, h, score, misses, frames;

    public GameView(Context c) {
        super(c);
        ball.setColor(Color.rgb(255, 112, 67));
        text.setColor(Color.WHITE);
        text.setTextAlign(Paint.Align.CENTER);
        frame.setStyle(Paint.Style.STROKE);
        frame.setColor(0xff4fc3f7);
        frame.setStrokeWidth(6f);
        float density = getResources().getDisplayMetrics().density;
        radius = 40 * density;
        text.setTextSize(28 * density);
    }

    @Override
    protected void onSizeChanged(int nw, int nh, int ow, int oh) {
        w = nw;
        h = nh;
        x = w / 2f;
        y = h / 2f;
        vx = w / 60f;
        vy = h / 90f;
        arrow.reset();
        arrow.moveTo(w / 2f, 20);
        arrow.lineTo(w / 2f - 30, 70);
        arrow.lineTo(w / 2f + 30, 70);
        arrow.close();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        canvas.drawColor(0xff102027);
        bar.set(20, h - 60, 20 + (w - 40) * Math.min(1f, score / 10f), h - 30);
        canvas.drawRoundRect(bar, 15, 15, frame);
        canvas.drawPath(arrow, frame);
        canvas.drawCircle(x, y, radius, ball);
        canvas.drawText("Score: " + score + "  Missed: " + misses, w / 2f, 120, text);
        frames++;
        x += vx;
        y += vy;
        if (x < radius || x > w - radius) vx = -vx;
        if (y < radius + 140 || y > h - radius - 80) vy = -vy;
        invalidate();
    }

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        if (e.getAction() == MotionEvent.ACTION_DOWN) {
            float dx = e.getX() - x, dy = e.getY() - y;
            if (dx * dx + dy * dy <= radius * radius * 1.5f) {
                score++;
                vx *= 1.1f;
                vy *= -1.1f;
            } else {
                misses++;
            }
            invalidate();
            return true;
        }
        return true;
    }
}
