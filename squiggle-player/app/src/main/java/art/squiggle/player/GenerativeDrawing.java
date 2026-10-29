package art.squiggle.player;

import android.graphics.Path;
import android.graphics.RectF;
import java.util.Collections;

/** A small wheel rolls inside a larger ring, tracing one continuous closed curve. */
final class GenerativeDrawing {
    static SvgDrawing spirograph() {
        double ring = 200, wheel = 70, offset = 100;
        double radius = ring - wheel;
        Path path = new Path();
        int samples = 16000;
        // R/r = 20/7: seven wheel circuits close a twenty-lobed pattern.
        for (int i = 0; i <= samples; i++) {
            double t = 14 * Math.PI * i / samples;
            float x = (float)(300 + radius * Math.cos(t) + offset * Math.cos(radius / wheel * t));
            float y = (float)(300 + radius * Math.sin(t) - offset * Math.sin(radius / wheel * t));
            if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
        }
        path.close();
        return new SvgDrawing(Collections.singletonList(path), new RectF(40,40,560,560), "Spirograph · twenty petals");
    }
}
