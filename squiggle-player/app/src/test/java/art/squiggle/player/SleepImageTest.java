package art.squiggle.player;

import android.graphics.*;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=34,manifest=Config.NONE)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class SleepImageTest {
    @Test public void completeExportPreservesColorFillsWidthsAndSourceGeometry() throws Exception {
        String svg="<svg viewBox='0 0 100 100'><path stroke='#dd3039' data-squiggle-width-scale='4' d='M10 20L90 20'/><path stroke='#285bd7' d='M10 80L90 80'/><polygon stroke='black' fill='#218b4c' points='30,40 70,40 50,70'/></svg>";
        SvgDrawing drawing=SvgDrawing.read(new ByteArrayInputStream(svg.getBytes(StandardCharsets.UTF_8)),"RGB");
        RectF before=new RectF();drawing.paths.get(0).computeBounds(before,true);
        Bitmap image=SleepImage.render(drawing,1000,1000,2);
        assertEquals(0xffdd3039,image.getPixel(500,227));
        assertEquals(0xffdd3039,image.getPixel(500,230));
        assertEquals(0xff285bd7,image.getPixel(500,773));
        assertEquals(Color.WHITE,image.getPixel(500,776));
        assertEquals(0xff218b4c,image.getPixel(500,500));
        assertEquals(Color.WHITE,image.getPixel(0,0));
        RectF after=new RectF();drawing.paths.get(0).computeBounds(after,true);assertEquals(before,after);image.recycle();
    }
}
