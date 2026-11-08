package com.ogneliss.nativehttp;

// Аватар отправителя для уведомления о письме — средствами Android (Canvas в
// памяти, без видеокарты), канал ogneliss/avatar (08.11.2026).
//
// Зачем: раньше кружок с буквой, фото в круге и отметку VIP рисовал Flutter
// (picture.toImage + toByteData) — это работа видеокарты. Уведомление
// строится, когда приложение свёрнуто и окна нет. Журнал владельца
// 08.11.2026 (HUAWEI DEL-LX9): уведомление о новом письме в 09:59:21, через
// 2,4 с — падение движка Impeller на OpenGL ES при копировании картинки в
// видеопамяти (blit_pass_gles.cc(88)). Обычный Canvas Android рисует
// процессором и падать так не может.
//
// Здесь, а не в MainActivity: плагины пакетов Flutter подключает к каждому
// движку, в том числе к фоновому движку WorkManager (как ogneliss/native_http).
// Вид — тот же, что рисовал Flutter (messenger_notifications.dart):
// кружок цвета из списка писем с буквой, фото — середина снимка в круге,
// VIP — золотое кольцо и звёздочка внизу справа.

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.BitmapShader;
import android.graphics.Canvas;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import java.io.ByteArrayOutputStream;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

final class AvatarPainter implements MethodChannel.MethodCallHandler {
    static final String CHANNEL = "ogneliss/avatar";

    private static final ExecutorService WORK = Executors.newSingleThreadExecutor();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        final String m = call.method;
        if (!"initials".equals(m) && !"circle".equals(m) && !"vip".equals(m)) {
            result.notImplemented();
            return;
        }
        final int size = Math.max(16, Math.min(512, intArg(call, "size", 192)));
        final String letter = call.argument("letter");
        final byte[] bytes = call.argument("bytes");
        final int fill = intArg(call, "fill", 0xFF9E9E9E);
        final int letterColor = intArg(call, "letterColor", 0xFFFFFFFF);
        final int gold = intArg(call, "gold", 0xFFE0A100);
        WORK.execute(() -> {
            byte[] out = null;
            try {
                if ("initials".equals(m)) {
                    out = initials(letter == null ? "" : letter, fill, letterColor, size);
                } else if ("circle".equals(m)) {
                    out = bytes == null ? null : circle(bytes, size);
                } else {
                    out = bytes == null ? null : vip(bytes, gold, size);
                }
            } catch (Throwable e) {
                out = null;
            }
            final byte[] r = out;
            MAIN.post(() -> result.success(r));
        });
    }

    /** Цвет из Dart: 0xFFxxxxxx больше Integer.MAX_VALUE и приходит как Long. */
    private static int intArg(MethodCall call, String key, int def) {
        Object v = call.argument(key);
        return v instanceof Number ? (int) ((Number) v).longValue() : def;
    }

    private static byte[] png(Bitmap b) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        b.compress(Bitmap.CompressFormat.PNG, 100, out);
        b.recycle();
        return out.toByteArray();
    }

    /** Кружок цвета [fill] с буквой цвета [letterColor] (полужирный, 45 % высоты). */
    static byte[] initials(String letter, int fill, int letterColor, int size) {
        Bitmap bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(bmp);
        float s = size;
        Paint bg = new Paint(Paint.ANTI_ALIAS_FLAG);
        bg.setColor(fill);
        c.drawCircle(s / 2, s / 2, s / 2, bg);
        if (!letter.isEmpty()) {
            Paint tp = new Paint(Paint.ANTI_ALIAS_FLAG);
            tp.setColor(letterColor);
            tp.setTextSize(s * 0.45f);
            tp.setTextAlign(Paint.Align.CENTER);
            tp.setTypeface(Build.VERSION.SDK_INT >= 28
                    ? Typeface.create(Typeface.DEFAULT, 600, false)
                    : Typeface.DEFAULT_BOLD);
            Paint.FontMetrics fm = tp.getFontMetrics();
            c.drawText(letter, s / 2, s / 2 - (fm.ascent + fm.descent) / 2, tp);
        }
        return png(bmp);
    }

    /** Снимок, уменьшенный при чтении: короткая сторона — не меньше [size]. */
    private static Bitmap decode(byte[] bytes, int size) {
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(bytes, 0, bytes.length, o);
        if (o.outWidth <= 0 || o.outHeight <= 0) return null;
        int sample = 1;
        while (Math.min(o.outWidth, o.outHeight) / (sample * 2) >= size) sample *= 2;
        BitmapFactory.Options d = new BitmapFactory.Options();
        d.inSampleSize = sample;
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.length, d);
    }

    private static Paint shaderPaint(Bitmap src, RectF from, RectF to) {
        Matrix m = new Matrix();
        m.setRectToRect(from, to, Matrix.ScaleToFit.FILL);
        BitmapShader sh = new BitmapShader(src, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP);
        sh.setLocalMatrix(m);
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
        p.setShader(sh);
        return p;
    }

    /** Середина снимка в круге, прозрачные углы. */
    static byte[] circle(byte[] bytes, int size) {
        Bitmap src = decode(bytes, size);
        if (src == null) return null;
        float w = src.getWidth(), h = src.getHeight(), side = Math.min(w, h), s = size;
        RectF from = new RectF((w - side) / 2, (h - side) / 2, (w + side) / 2, (h + side) / 2);
        Bitmap bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        new Canvas(bmp).drawCircle(s / 2, s / 2, s / 2, shaderPaint(src, from, new RectF(0, 0, s, s)));
        src.recycle();
        return png(bmp);
    }

    /** Золотое кольцо вокруг портрета и звёздочка в белой обводке внизу справа. */
    static byte[] vip(byte[] circle, int gold, int size) {
        Bitmap src = decode(circle, size);
        if (src == null) return null;
        float s = size;
        float ring = s * 0.05f;
        float inset = ring + s * 0.025f;
        Bitmap bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(bmp);
        RectF inner = new RectF(inset, inset, s - inset, s - inset);
        c.drawOval(inner, shaderPaint(src, new RectF(0, 0, src.getWidth(), src.getHeight()), inner));
        src.recycle();
        Paint ringP = new Paint(Paint.ANTI_ALIAS_FLAG);
        ringP.setStyle(Paint.Style.STROKE);
        ringP.setStrokeWidth(ring);
        ringP.setColor(gold);
        c.drawCircle(s / 2, s / 2, s / 2 - ring / 2, ringP);
        float cx = s * 0.81f, cy = s * 0.81f, r = s * 0.17f;
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setColor(0xFFFFFFFF);
        c.drawCircle(cx, cy, r, p);
        p.setColor(gold);
        c.drawCircle(cx, cy, r - s * 0.025f, p);
        p.setColor(0xFFFFFFFF);
        c.drawPath(star(cx, cy, r * 0.62f), p);
        return png(bmp);
    }

    private static Path star(float cx, float cy, float r) {
        Path path = new Path();
        float inner = r * 0.45f;
        for (int i = 0; i < 10; i++) {
            float rad = i % 2 == 0 ? r : inner;
            double a = -Math.PI / 2 + i * Math.PI / 5;
            float x = cx + (float) (rad * Math.cos(a));
            float y = cy + (float) (rad * Math.sin(a));
            if (i == 0) path.moveTo(x, y);
            else path.lineTo(x, y);
        }
        path.close();
        return path;
    }
}
