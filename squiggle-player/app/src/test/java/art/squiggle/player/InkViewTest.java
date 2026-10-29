package art.squiggle.player;

import android.graphics.Bitmap;
import android.app.Activity;
import android.graphics.Canvas;
import android.graphics.Color;
import android.os.Looper;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Robolectric;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import static org.robolectric.Shadows.shadowOf;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=34,manifest=Config.NONE)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class InkViewTest {
    @Test public void shadowWidthsRenderAndSurviveResizeAndPenWidthChanges() throws Exception {
        Activity activity=Robolectric.buildActivity(Activity.class).setup().get();
        InkView view=new InkView(activity);activity.setContentView(view);shadowOf(Looper.getMainLooper()).idle();
        view.layout(0,0,800,800);view.setDirectEnabled(false);view.setWidth(2);
        String svg="<svg viewBox='0 0 100 100'><path data-squiggle-width-scale='1' d='M10 30L90 30'/><path data-squiggle-width-scale='4' d='M10 60L90 60'/></svg>";
        view.setDrawing(SvgDrawing.read(new ByteArrayInputStream(svg.getBytes(StandardCharsets.UTF_8)),"Widths"));
        view.setSpeed(500);view.play();shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(10));view.pause();
        assertTrue(view.isFinished());assertShadowWidths(view);
        view.layout(0,0,1000,800);assertShadowWidths(view);
        view.setWidth(1.8f);assertShadowWidths(view);
        view.restart();assertEquals(Color.WHITE,inside(view,50,60));
    }
    private void assertShadowWidths(InkView view) {
        assertEquals(Color.WHITE,inside(view,50,30.4f));
        assertNotEquals(Color.WHITE,inside(view,50,60.4f));
        assertNotEquals(Color.WHITE,inside(view,50,30));
    }
    @Test public void fillsEachPolygonOnlyAfterItsOutlineAndRestoresCompletedFills() throws Exception {
        Activity activity=Robolectric.buildActivity(Activity.class).setup().get();
        InkView view=new InkView(activity);activity.setContentView(view);shadowOf(Looper.getMainLooper()).idle();
        view.layout(0,0,800,800);view.setDirectEnabled(false);
        String svg="<svg viewBox='0 0 100 100'><polygon stroke='black' fill='#dd3039' points='10,10 40,10 10,40'/><polygon stroke='black' fill='#218b4c' points='60,60 90,60 60,90'/></svg>";
        view.setDrawing(SvgDrawing.read(new ByteArrayInputStream(svg.getBytes(StandardCharsets.UTF_8)),"Facets"));
        view.setSpeed(500);view.play();shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(500));view.pause();
        assertEquals(Color.WHITE,inside(view,20,20));assertEquals(Color.WHITE,inside(view,70,70));
        view.play();shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(1200));view.pause();
        assertEquals(0xffdd3039,inside(view,20,20));assertEquals(Color.WHITE,inside(view,70,70));assertFalse(view.isFinished());
        view.layout(0,0,1000,800);assertEquals(0xffdd3039,inside(view,20,20));assertEquals(Color.WHITE,inside(view,70,70));
        view.play();shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5));view.pause();
        assertTrue(view.isFinished());assertEquals(0xff218b4c,inside(view,70,70));
        view.restart();assertEquals(Color.WHITE,inside(view,20,20));assertEquals(Color.WHITE,inside(view,70,70));
    }
    @Test public void wireframeNeverFillsInterior() throws Exception {
        Activity activity=Robolectric.buildActivity(Activity.class).setup().get();InkView view=new InkView(activity);activity.setContentView(view);shadowOf(Looper.getMainLooper()).idle();
        view.layout(0,0,800,800);view.setDrawing(SvgDrawing.read(new ByteArrayInputStream("<svg viewBox='0 0 100 100'><polygon stroke='black' fill='none' points='10,10 90,10 10,90'/></svg>".getBytes(StandardCharsets.UTF_8)),"Wireframe"));
        view.setDirectEnabled(false);view.setSpeed(500);view.play();shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(10));view.pause();
        assertTrue(view.isFinished());assertEquals(Color.WHITE,inside(view,30,30));
    }
    private int inside(InkView view,float x,float y) {
        Bitmap image=Bitmap.createBitmap(view.getWidth(),view.getHeight(),Bitmap.Config.ARGB_8888);view.draw(new Canvas(image));
        float margin=24*view.getResources().getDisplayMetrics().density,scale=Math.min((view.getWidth()-2*margin)/100,(view.getHeight()-2*margin)/100);
        int px=Math.round((view.getWidth()-100*scale)/2+x*scale),py=Math.round((view.getHeight()-100*scale)/2+y*scale);
        int color=image.getPixel(px,py);image.recycle();return color;
    }
    @Test public void preservesColoredContoursAcrossPauseAndResize() throws Exception {
        Activity activity=Robolectric.buildActivity(Activity.class).setup().get();
        InkView view=new InkView(activity); activity.setContentView(view);
        shadowOf(Looper.getMainLooper()).idle();
        String svg="<svg viewBox='0 0 100 100'><path stroke='#dd3039' d='M10 20L90 20 M10 30L90 30'/><path stroke='#218b4c' d='M10 60L90 60'/><path stroke='#285bd7' d='M10 80L90 80'/></svg>";
        view.setDrawing(SvgDrawing.read(new ByteArrayInputStream(svg.getBytes(StandardCharsets.UTF_8)),"RGB"));
        view.setWidth(3); view.setSpeed(500); view.play(); shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(10)); view.pause();
        assertTrue(view.isFinished()); assertColors(view);
        view.layout(0,0,1000,800); assertColors(view);
    }
    private void assertColors(InkView view) {
        Bitmap image=Bitmap.createBitmap(view.getWidth(),view.getHeight(),Bitmap.Config.ARGB_8888); view.draw(new Canvas(image));
        java.util.Set<Integer> found=new java.util.HashSet<>();
        for(int y=0;y<image.getHeight();y++) for(int x=0;x<image.getWidth();x++) found.add(image.getPixel(x,y));
        assertTrue(found.contains(0xffdd3039)); assertTrue(found.contains(0xff218b4c)); assertTrue(found.contains(0xff285bd7));
    }
    @Test public void addsInkAndPreservesItAcrossPauseAndResize() throws Exception {
        Activity activity=Robolectric.buildActivity(Activity.class).setup().get();
        InkView view=new InkView(activity);
        activity.setContentView(view);
        shadowOf(Looper.getMainLooper()).idle();
        assertTrue(view.getWidth()>0);
        SvgDrawing d=SvgDrawing.read(new ByteArrayInputStream("<svg viewBox='0 0 100 100'><path d='M10 20C20 80 80 20 90 80'/></svg>".getBytes(StandardCharsets.UTF_8)),"Curve");
        view.setDrawing(d);
        double[] progress={0}; view.listener=(r,f,p)->progress[0]=p;
        view.play(); shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1)); view.pause();
        double before=progress[0]; assertTrue("No progress: " + before,before>0); assertTrue("Completed too early: " + before,before<1);
        Bitmap image=Bitmap.createBitmap(view.getWidth(),view.getHeight(),Bitmap.Config.ARGB_8888); view.draw(new Canvas(image));
        int marks=0;
        for(int y=0;y<image.getHeight();y++) for(int x=0;x<image.getWidth();x++) if(image.getPixel(x,y)!=Color.WHITE) marks++;
        assertTrue("The renderer must produce visible ink",marks>100);
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1)); assertEquals(before,progress[0],1e-6);
        view.layout(0,0,1000,800); assertEquals(before,progress[0],1e-6); assertFalse(view.isRunning());
        view.restart(); assertEquals(0,progress[0],1e-6);
    }
}
