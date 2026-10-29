package art.squiggle.player;

import android.graphics.PathMeasure;
import android.graphics.RectF;
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
public class SvgDrawingTest {
    @Test public void importsShadowWidthRatiosAndPreservesLegacyUniformImports() throws Exception {
        SvgDrawing d=read("<svg><path data-squiggle-width-scale='1' d='M0 0L10 0'/><path data-squiggle-width-scale='4' d='M10 0L20 0'/><path stroke-width='7' d='M20 0L30 0'/></svg>");
        assertEquals(java.util.Arrays.asList(1f,4f,0f),d.widthFactors);assertTrue(d.hasVariableWidth());
        for(String invalid:new String[]{"NaN","Infinity","0","-1","6.1"}) {
            try { read("<svg><path data-squiggle-width-scale='"+invalid+"' d='M0 0L10 0'/></svg>");fail("Accepted "+invalid); }
            catch(IllegalArgumentException expected) { }
        }
    }
    @Test public void widthChangesDoNotAddPenLiftsButSeparateMarksDo() {
        Playback p=new Playback(new double[]{10,10,10},0.2,new boolean[]{false,true,false});
        p.advance(1.1,10,(stroke,from,to)->{});assertEquals(1,p.stroke);assertEquals(1,p.distance,1e-6);
        p.advance(1,10,(stroke,from,to)->{});assertEquals(2,p.stroke);assertEquals(0,p.distance,1e-6);
        p.advance(0.2,10,(stroke,from,to)->{});assertEquals(1,p.distance,1e-6);
    }
    @Test public void preservesPolygonFillsInheritanceOverridesAndTransforms() throws Exception {
        SvgDrawing d=read("<svg><g fill='#f00' transform='translate(10 20)'><polygon points='0,0 10,0 0,10'/><polygon style='fill:#00ff00' points='20,0 30,0 20,10'/><polygon fill='none' points='40,0 50,0 40,10'/></g><path fill='#00f' d='M0 0L10 10'/></svg>");
        assertEquals(java.util.Arrays.asList(android.graphics.Color.RED,android.graphics.Color.GREEN,android.graphics.Color.TRANSPARENT,android.graphics.Color.TRANSPARENT),d.fills);
        assertTrue(d.hasFill());assertTrue(d.hasColor());
        RectF b=new RectF();d.paths.get(0).computeBounds(b,true);assertEquals(10,b.left,.001);assertEquals(20,b.top,.001);
        assertTrue(new PathMeasure(d.paths.get(0),false).isClosed());
    }
    @Test public void wireframeAndOpenRoutesDoNotGainFills() throws Exception {
        SvgDrawing d=read("<svg><polygon fill='none' points='0,0 10,0 0,10'/><path fill='url(#brush)' d='M0 0L10 10'/><circle cx='5' cy='5' r='2'/></svg>");
        assertFalse(d.hasFill());
        assertEquals(java.util.Arrays.asList(android.graphics.Color.TRANSPARENT,android.graphics.Color.TRANSPARENT,android.graphics.Color.TRANSPARENT),d.fills);
    }
    @Test public void importsFillOnlyPolygonsAndSkipsEmptyPaint() throws Exception {
        SvgDrawing d=read("<svg><polygon stroke='none' fill='#123456' points='0,0 10,0 0,10'/><polygon stroke='none' fill='none' points='20,0 30,0 20,10'/></svg>");
        assertEquals(1,d.paths.size());assertEquals(0xff123456,(int)d.fills.get(0));
    }
    @Test public void preservesStrokeColorsAndInlineStyleOverrides() throws Exception {
        SvgDrawing d=read("<svg><g stroke='#dd3039'><path d='M0 0L10 10'/><path stroke='#218b4c' d='M0 10L10 20'/><path stroke='black' style='stroke: #285bd7' d='M0 20L10 30'/></g><path d='M0 30L10 40'/></svg>");
        assertEquals(java.util.Arrays.asList(0xffdd3039,0xff218b4c,0xff285bd7,android.graphics.Color.BLACK),d.colors);
        assertTrue(d.hasColor());
    }
    @Test public void supportsRgbAndShortHexAndSkipsNoStroke() throws Exception {
        SvgDrawing d=read("<svg><path stroke='#f00' d='M0 0L10 10'/><path stroke='rgb(0, 100%, 0)' d='M0 10L10 20'/><path stroke='none' d='M0 20L10 30'/></svg>");
        assertEquals(java.util.Arrays.asList(android.graphics.Color.RED,android.graphics.Color.GREEN),d.colors);
    }
    @Test public void denseLineParserPreservesContourEndpointsAndLength() {
        StringBuilder data=new StringBuilder("M0 0");
        for(int i=1;i<=100000;i++) data.append('L').append(i).append(' ').append(i%2);
        PathMeasure m=new PathMeasure(SvgDrawing.linePath(data.toString()),false);
        assertEquals(100000*Math.sqrt(2),m.getLength(),200);
        float[] end=new float[2]; assertTrue(m.getPosTan(m.getLength(),end,null));
        assertEquals(100000,end[0],.01); assertEquals(0,end[1],.01);
        assertFalse(m.nextContour());
    }
    @Test public void lineParserFallsBackForImplicitAndRelativeCommands() {
        PathMeasure m=new PathMeasure(SvgDrawing.linePath("M0 0 3 4 l3 4"),false);
        assertEquals(10,m.getLength(),.001);
    }
    SvgDrawing read(String contents) throws Exception {
        return SvgDrawing.read(new ByteArrayInputStream(contents.getBytes(StandardCharsets.UTF_8)),"Test");
    }
    @Test public void preservesSeparateContoursAndBezierCurves() throws Exception {
        SvgDrawing d=read("<svg><path d='M0 0 C0 10 10 10 10 0 M20 0 L30 0'/></svg>");
        PathMeasure m=new PathMeasure(d.paths.get(0),false);
        assertTrue(m.getLength()>10); assertTrue(m.nextContour()); assertEquals(10,m.getLength(),.001);
        assertFalse(m.nextContour());
    }
    @Test public void composesNestedTransformsInSvgOrder() throws Exception {
        SvgDrawing d=read("<svg><g transform='translate(10 20)'><path transform='scale(2)' d='M1 1 L3 4'/></g></svg>");
        RectF b=new RectF(); d.paths.get(0).computeBounds(b,true);
        assertEquals(12,b.left,.001); assertEquals(22,b.top,.001); assertEquals(16,b.right,.001); assertEquals(28,b.bottom,.001);
    }
    @Test public void transformListOrderIsCorrect() throws Exception {
        SvgDrawing d=read("<svg><path transform='translate(10 20) scale(2)' d='M1 1 L3 4'/></svg>");
        RectF b=new RectF(); d.paths.get(0).computeBounds(b,true);
        assertEquals(12,b.left,.001); assertEquals(22,b.top,.001);
    }
    @Test public void ignoresDefinitionsAndHiddenArtwork() throws Exception {
        SvgDrawing d=read("<svg><defs><path d='M0 0L100 100'/></defs><g display='none'><path d='M0 0L50 50'/></g><path d='M1 1L2 2'/></svg>");
        assertEquals(1,d.paths.size()); assertEquals(1,d.bounds.left,.001);
    }
    @Test public void handlesHorizontalAndVerticalBounds() throws Exception {
        SvgDrawing d=read("<svg><path d='M0 10L100 10'/><path d='M200 0L200 20'/></svg>");
        assertEquals(200,d.bounds.right,.001); assertEquals(20,d.bounds.bottom,.001);
    }
    @Test public void honorsViewBox() throws Exception {
        SvgDrawing d=read("<svg viewBox='-10 -20 300 400'><path d='M0 0L1 1'/></svg>");
        assertEquals(-10,d.bounds.left,.001); assertEquals(300,d.bounds.width(),.001);
    }
    @Test public void importsPolylinesAndShapeOutlines() throws Exception {
        SvgDrawing d=read("<svg><polyline points='0,0 10,10 20,0'/><rect x='0' y='0' width='20' height='10'/><circle cx='0' cy='0' r='10'/></svg>");
        assertEquals(3,d.paths.size());
        assertEquals(60,new PathMeasure(d.paths.get(1),false).getLength(),.001);
    }
    @Test public void rejectsExternalReferencesRatherThanLosingArtwork() throws Exception {
        try { read("<svg><use href='https://example.com/drawing.svg'/></svg>"); fail(); }
        catch(IllegalArgumentException expected) { assertTrue(expected.getMessage().contains("use")); }
    }
    @Test public void rejectsNonFiniteCoordinates() throws Exception {
        try { read("<svg><line x1='1e99' x2='10'/></svg>"); fail(); }
        catch(IllegalArgumentException expected) { }
    }
    @Test public void rejectsMalformedTransforms() throws Exception {
        try { read("<svg><path transform='translate(10) garbage' d='M0 0L1 1'/></svg>"); fail(); }
        catch(IllegalArgumentException expected) { }
    }
}
