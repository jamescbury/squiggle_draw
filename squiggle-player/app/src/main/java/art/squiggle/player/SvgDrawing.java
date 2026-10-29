package art.squiggle.player;

import android.graphics.Matrix;
import android.graphics.Color;
import android.graphics.Path;
import android.graphics.RectF;
import android.util.Xml;
import androidx.core.graphics.PathParser;
import org.xmlpull.v1.XmlPullParser;
import java.io.InputStream;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class SvgDrawing {
    final List<Path> paths;
    final List<Integer> colors;
    final List<Integer> fills;
    // Zero preserves legacy uniform-width imports; positive values are Studio shadow-width ratios.
    final List<Float> widthFactors;
    final RectF bounds;
    final String name;
    SvgDrawing(List<Path> paths, RectF bounds, String name) {
        this(paths,java.util.Collections.nCopies(paths.size(),Color.BLACK),bounds,name);
    }
    SvgDrawing(List<Path> paths,List<Integer> colors,RectF bounds,String name) {
        this(paths,colors,java.util.Collections.nCopies(paths.size(),Color.TRANSPARENT),bounds,name);
    }
    SvgDrawing(List<Path> paths,List<Integer> colors,List<Integer> fills,RectF bounds,String name) {
        this(paths,colors,fills,java.util.Collections.nCopies(paths.size(),0f),bounds,name);
    }
    SvgDrawing(List<Path> paths,List<Integer> colors,List<Integer> fills,List<Float> widthFactors,RectF bounds,String name) {
        require(paths.size()==colors.size() && paths.size()==fills.size() && paths.size()==widthFactors.size());
        for(float factor:widthFactors) require(Float.isFinite(factor) && (factor==0 || (factor>=0.25f && factor<=6)));
        this.widthFactors=widthFactors;
        this.paths=paths; this.colors=colors; this.fills=fills; this.bounds=bounds; this.name=name;
    }
    boolean hasColor() {
        for(int color:colors) if(color!=Color.BLACK) return true;
        for(int color:fills) if(color!=Color.TRANSPARENT && color!=Color.BLACK) return true;
        return false;
    }
    boolean hasVariableWidth() { for(float factor:widthFactors) if(factor>0) return true; return false; }
    boolean hasFill() {
        for(int color:fills) if(Color.alpha(color)>0) return true;
        return false;
    }
    static final Pattern NUMBER = Pattern.compile("[-+]?(?:\\d*\\.\\d+|\\d+\\.?\\d*)(?:[eE][-+]?\\d+)?");
    static final Pattern TRANSFORM = Pattern.compile("([A-Za-z]+)\\s*\\(([^)]*)\\)");
    static float[] numbers(String value) {
        if (value == null) return new float[0];
        List<Float> list = new ArrayList<>();
        Matcher matcher = NUMBER.matcher(value);
        while (matcher.find()) {
            float n = Float.parseFloat(matcher.group());
            if (!Float.isFinite(n)) throw new IllegalArgumentException("Coordinates must be finite");
            list.add(n);
        }
        float[] result = new float[list.size()];
        for (int i=0; i<result.length; i++) result[i] = list.get(i);
        return result;
    }
    private static Matrix transform(String value) {
        Matrix matrix = new Matrix();
        if (value == null || value.trim().isEmpty()) return matrix;
        Matcher matcher = TRANSFORM.matcher(value);
        int end = 0;
        while (matcher.find()) {
            if (!value.substring(end, matcher.start()).matches("[\\s,]*")) throw new IllegalArgumentException("Invalid transform");
            float[] v = numbers(matcher.group(2));
            Matrix next = new Matrix();
            String type = matcher.group(1);
            switch (type) {
                case "matrix":
                    require(v.length == 6);
                    next.setValues(new float[]{v[0],v[2],v[4],v[1],v[3],v[5],0,0,1}); break;
                case "translate": require(v.length == 1 || v.length == 2); next.setTranslate(v[0],v.length==2?v[1]:0); break;
                case "scale": require(v.length == 1 || v.length == 2); next.setScale(v[0],v.length==2?v[1]:v[0]); break;
                case "rotate":
                    require(v.length == 1 || v.length == 3);
                    if (v.length == 3) next.setRotate(v[0],v[1],v[2]); else next.setRotate(v[0]); break;
                case "skewX": require(v.length == 1); next.setSkew((float)Math.tan(Math.toRadians(v[0])),0); break;
                case "skewY": require(v.length == 1); next.setSkew(0,(float)Math.tan(Math.toRadians(v[0]))); break;
                default: throw new IllegalArgumentException("Unsupported transform: " + type);
            }
            matrix.preConcat(next); end = matcher.end();
        }
        if (!value.substring(end).matches("[\\s,]*")) throw new IllegalArgumentException("Invalid transform");
        return matrix;
    }
    // Dense plotter exports commonly have a million M/L points. Avoid allocating
    // one PathParser node and float array for each of these tiny segments.
    private static final Pattern LINE_POINT=Pattern.compile("([ML])("+NUMBER.pattern()+")[,\\s]*("+NUMBER.pattern()+")");
    static Path linePath(String data) {
        if(data.isEmpty() || data.charAt(0)!='M') return PathParser.createPathFromPathData(data);
        Matcher points=LINE_POINT.matcher(data);
        Path path=new Path(); int end=0, count=0;
        while(points.find()) {
            if(!data.substring(end,points.start()).trim().isEmpty()) return PathParser.createPathFromPathData(data);
            float x=Float.parseFloat(points.group(2)),y=Float.parseFloat(points.group(3));
            if(!Float.isFinite(x) || !Float.isFinite(y)) throw new IllegalArgumentException("Coordinates must be finite");
            if(points.group(1).equals("M")) path.moveTo(x,y); else path.lineTo(x,y);
            end=points.end();
            if(++count%4096==0 && Thread.currentThread().isInterrupted()) throw new IllegalArgumentException("Import cancelled");
        }
        if(count==0 || !data.substring(end).trim().isEmpty()) return PathParser.createPathFromPathData(data);
        return path;
    }
    static void require(boolean condition) { if (!condition) throw new IllegalArgumentException("Invalid SVG geometry"); }
    static String attr(XmlPullParser x, String name) { return x.getAttributeValue(null,name); }
    static float scalar(XmlPullParser x, String name, float fallback) {
        String raw = attr(x,name);
        if (raw == null) return fallback;
        if (!raw.matches("\\s*"+NUMBER.pattern()+"(?:px)?\\s*")) throw new IllegalArgumentException("Use numeric or px coordinates for " + name);
        return numbers(raw)[0];
    }
    static int strokeColor(String value,int inherited) {
        if(value==null || value.trim().equalsIgnoreCase("inherit")) return inherited;
        value=value.trim().toLowerCase(java.util.Locale.ROOT);
        if(value.equals("none")) return Color.TRANSPARENT;
        if(value.matches("#[0-9a-f]{3}"))
            value="#"+value.charAt(1)+value.charAt(1)+value.charAt(2)+value.charAt(2)+value.charAt(3)+value.charAt(3);
        if(value.startsWith("rgb(") && value.endsWith(")")) {
            String[] channels=value.substring(4,value.length()-1).split("\\s*,\\s*");
            require(channels.length==3); int[] c=new int[3];
            for(int i=0;i<3;i++) {
                String channel=channels[i].trim();
                c[i]=Math.round(channel.endsWith("%")?Float.parseFloat(channel.substring(0,channel.length()-1))*255/100:Float.parseFloat(channel));
                require(c[i]>=0 && c[i]<=255);
            }
            return Color.rgb(c[0],c[1],c[2]);
        }
        try { return Color.parseColor(value); }
        catch(IllegalArgumentException e) { throw new IllegalArgumentException("Unsupported SVG stroke color: "+value); }
    }
    static String styleStroke(String style,String stroke) { return stylePaint(style,"stroke",stroke); }
    static String stylePaint(String style,String property,String stroke) {
        if(style!=null) for(String declaration:style.split(";")) {
            int colon=declaration.indexOf(':');
            if(colon>=0 && declaration.substring(0,colon).trim().equalsIgnoreCase(property))
                stroke=declaration.substring(colon+1).trim();
        }
        return stroke;
    }
    static SvgDrawing read(InputStream input, String name) throws Exception {
        XmlPullParser xml = Xml.newPullParser();
        xml.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, true);
        xml.setInput(input, "UTF-8");
        ArrayDeque<Matrix> matrices = new ArrayDeque<>();
        ArrayDeque<Boolean> hidden = new ArrayDeque<>();
        matrices.push(new Matrix()); hidden.push(false);
        ArrayDeque<Integer> inheritedColors=new ArrayDeque<>(); inheritedColors.push(Color.BLACK);
        List<Path> paths = new ArrayList<>();
        List<Integer> colors=new ArrayList<>(),fills=new ArrayList<>();
        List<Float> widthFactors=new ArrayList<>();
        ArrayDeque<String> inheritedFills=new ArrayDeque<>(); inheritedFills.push("black");
        RectF geometry = new RectF();
        RectF viewport = null;
        int count = 0, dataSize = 0;
        boolean root = false;
        for (int event=xml.getEventType(); event!=XmlPullParser.END_DOCUMENT; event=xml.next()) {
            if (Thread.currentThread().isInterrupted()) throw new InterruptedException();
            if (event == XmlPullParser.DOCDECL) throw new IllegalArgumentException("SVG document declarations are unsupported");
            if (event == XmlPullParser.START_TAG) {
                if (++count > 20000 || matrices.size()>64) throw new IllegalArgumentException("SVG is too complex");
                String tag = xml.getName();
                if (!root) {
                    require(tag.equals("svg")); root = true;
                    float[] box = numbers(attr(xml,"viewBox"));
                    if (box.length != 0) { require(box.length==4 && box[2]>0 && box[3]>0); viewport = new RectF(box[0],box[1],box[0]+box[2],box[1]+box[3]); }
                } else if (tag.equals("svg")) throw new IllegalArgumentException("Nested SVG viewports are unsupported; flatten the SVG first");
                String style = attr(xml,"style");
                int color=strokeColor(styleStroke(style,attr(xml,"stroke")),inheritedColors.peek());
                inheritedColors.push(color);
                String fill=stylePaint(style,"fill",attr(xml,"fill"));
                if(fill==null || fill.trim().equalsIgnoreCase("inherit")) fill=inheritedFills.peek();
                inheritedFills.push(fill);
                String namespace = xml.getNamespace();
                boolean hide = hidden.peek() || (namespace != null && !namespace.isEmpty() && !namespace.equals("http://www.w3.org/2000/svg")) || tag.equals("defs") || tag.equals("metadata") || tag.equals("clipPath")
                        || tag.equals("mask") || tag.equals("symbol") || "none".equals(attr(xml,"display"))
                        || (style != null && style.matches("(?s).*display\\s*:\\s*none.*"));
                hidden.push(hide);
                Matrix matrix = new Matrix(matrices.peek());
                matrix.preConcat(transform(attr(xml,"transform"))); matrices.push(matrix);
                if (hide) continue;
                if (attr(xml,"clip-path") != null || attr(xml,"mask") != null)
                    throw new IllegalArgumentException("Flatten clipped or masked paths before importing");
                Path path = new Path();
                switch (tag) {
                    case "path":
                        String d = attr(xml,"d");
                        if (d == null || d.isEmpty()) continue;
                        dataSize += d.length();
                        if (dataSize > 28_000_000) throw new IllegalArgumentException("SVG path data is too large");
                        path = linePath(d); break;
                    case "polyline": case "polygon":
                        float[] pts = numbers(attr(xml,"points")); require(pts.length>=4 && pts.length%2==0);
                        path.moveTo(pts[0],pts[1]);
                        for (int i=2;i<pts.length;i+=2) path.lineTo(pts[i],pts[i+1]);
                        if (tag.equals("polygon")) path.close(); break;
                    case "line": path.moveTo(scalar(xml,"x1",0),scalar(xml,"y1",0)); path.lineTo(scalar(xml,"x2",0),scalar(xml,"y2",0)); break;
                    case "circle": case "ellipse":
                        float cx=scalar(xml,"cx",0), cy=scalar(xml,"cy",0);
                        float rx=scalar(xml,tag.equals("circle")?"r":"rx",0), ry=tag.equals("circle")?rx:scalar(xml,"ry",0);
                        require(rx>=0 && ry>=0); path.addOval(cx-rx,cy-ry,cx+rx,cy+ry,Path.Direction.CW); break;
                    case "rect":
                        float x=scalar(xml,"x",0), y=scalar(xml,"y",0), w=scalar(xml,"width",0), h=scalar(xml,"height",0);
                        require(w>=0 && h>=0);
                        float rX=scalar(xml,"rx",scalar(xml,"ry",0)), rY=scalar(xml,"ry",rX);
                        require(rX>=0 && rY>=0);
                        path.addRoundRect(x,y,x+w,y+h,Math.min(rX,w/2),Math.min(rY,h/2),Path.Direction.CW); break;
                    case "svg": case "g": case "title": case "desc": continue;
                    default: throw new IllegalArgumentException("Unsupported SVG element: " + tag + ". Export plain paths.");
                }
                // Only closed polygons gain fill-after-outline playback. Open pen
                // routes and legacy dot imports keep their existing behavior.
                int polygonFill=tag.equals("polygon") ? strokeColor(fill,Color.BLACK) : Color.TRANSPARENT;
                if(color==Color.TRANSPARENT && polygonFill==Color.TRANSPARENT) continue;
                require(path != null);
                path.transform(matrix);
                RectF b = new RectF(); path.computeBounds(b,true);
                require(Float.isFinite(b.left) && Float.isFinite(b.top) && Float.isFinite(b.right) && Float.isFinite(b.bottom));
                if (paths.isEmpty()) geometry.set(b); else {
                    geometry.left=Math.min(geometry.left,b.left); geometry.top=Math.min(geometry.top,b.top);
                    geometry.right=Math.max(geometry.right,b.right); geometry.bottom=Math.max(geometry.bottom,b.bottom);
                }
                String widthValue=attr(xml,"data-squiggle-width-scale");
                float widthFactor=widthValue==null ? 0 : Float.parseFloat(widthValue);
                require(Float.isFinite(widthFactor) && (widthValue==null || (widthFactor>=0.25f && widthFactor<=6)));
                paths.add(path); colors.add(color); fills.add(polygonFill);widthFactors.add(widthFactor);
            } else if (event == XmlPullParser.END_TAG) { matrices.pop(); hidden.pop(); inheritedColors.pop(); inheritedFills.pop(); }
        }
        require(root && !paths.isEmpty());
        RectF bounds = viewport != null ? viewport : geometry;
        if (bounds.width() <= 0) { bounds.left-=0.5f; bounds.right+=0.5f; }
        if (bounds.height() <= 0) { bounds.top-=0.5f; bounds.bottom+=0.5f; }
        return new SvgDrawing(paths,colors,fills,widthFactors,bounds,name);
    }
}
