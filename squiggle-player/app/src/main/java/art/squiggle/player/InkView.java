package art.squiggle.player;

import android.content.Context;
import android.graphics.*;
import android.os.SystemClock;
import android.view.View;
import java.util.ArrayList;
import java.util.List;

final class InkView extends View {
    interface Listener { void changed(boolean running, boolean finished, double fraction); }
    private final Paint ink = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint paper = new Paint();
    private final Paint fillInk = new Paint(Paint.ANTI_ALIAS_FLAG);
    private Bitmap bitmap;
    private Canvas surface;
    private SvgDrawing drawing;
    private final List<PathMeasure> strokes = new ArrayList<>();
    private final List<Integer> strokeColors=new ArrayList<>();
    private final List<Float> strokeWidths=new ArrayList<>();
    private final List<Path> strokeFills=new ArrayList<>();
    private final List<Integer> fillColors=new ArrayList<>();
    private Playback playback;
    private boolean running;
    private long lastTick;
    private float speedDp = 70, widthDp = 1;
    private int fps = 60;
    private final DirectInk direct;
    private boolean directEnabled = true;
    private boolean beginDirect;
    private long directStartAt;
    Listener listener;
    private final RectF dirty = new RectF();
    private final Path segment = new Path();

    InkView(Context context) {
        super(context);
        direct=new DirectInk(this);
        setBackgroundColor(Color.WHITE);
        setLayerType(View.LAYER_TYPE_SOFTWARE,null);
        ink.setColor(Color.BLACK); ink.setStyle(Paint.Style.STROKE);
        ink.setStrokeCap(Paint.Cap.ROUND); ink.setStrokeJoin(Paint.Join.ROUND);
        paper.setColor(Color.WHITE);fillInk.setStyle(Paint.Style.FILL);
        setContentDescription("Drawing canvas");
    }
    void setDrawing(SvgDrawing value) { pause(); drawing=value; rebuild(0); }
    float penWidthPixels() { return widthDp*getResources().getDisplayMetrics().density; }
    void setSpeed(float value) { speedDp=value; }
    void setFps(int value) { fps=value; }
    void setWidth(float value) { widthDp=value; rebuild(playback==null?0:playback.fraction()); }
    String rendererStatus() { return drawing!=null && drawing.hasVariableWidth()?"Shadow widths · canvas":drawing!=null && drawing.hasFill()?"Filled shapes · canvas":drawing!=null && drawing.hasColor()?"Color drawing · canvas":directEnabled?direct.status():"Drawing with canvas"; }
    void setDirectEnabled(boolean enabled) { pause(); directEnabled=enabled; }
    boolean isRunning() { return running; }
    boolean isFinished() { return playback != null && playback.done(); }
    void play() {
        if (playback==null || running) return;
        if (playback.done()) restart();
        running=true; setKeepScreenOn(true); lastTick=SystemClock.uptimeMillis();
        beginDirect=directEnabled && direct.available() && !drawing.hasColor() && !drawing.hasFill() && !drawing.hasVariableWidth();
        directStartAt=lastTick+250;
        changed(); postDelayed(tick,1000/fps);
    }
    void pause() {
        running=false; beginDirect=false; removeCallbacks(tick); setKeepScreenOn(false);
        if(direct.active()) { direct.end(); invalidate(); }
        changed();
    }
    void restart() { pause(); rebuild(0); }
    private void changed() { if(listener!=null) listener.changed(running,isFinished(),playback==null?0:playback.fraction()); }
    @Override protected void onSizeChanged(int w,int h,int oldw,int oldh) {
        double progress=playback==null?0:playback.fraction(); pause(); rebuild(progress);
    }
    private void rebuild(double fraction) {
        pause();
        if (getWidth()<=0 || getHeight()<=0 || drawing==null) return;
        if(bitmap!=null) bitmap.recycle();
        bitmap=Bitmap.createBitmap(getWidth(),getHeight(),Bitmap.Config.ARGB_8888);
        bitmap.eraseColor(Color.WHITE); surface=new Canvas(bitmap);
        ink.setStrokeWidth(widthDp*getResources().getDisplayMetrics().density);
        strokes.clear(); strokeColors.clear();strokeWidths.clear();strokeFills.clear();fillColors.clear();
        float margin=24*getResources().getDisplayMetrics().density;
        float scale=Math.min(Math.max(1,getWidth()-2*margin)/drawing.bounds.width(),Math.max(1,getHeight()-2*margin)/drawing.bounds.height());
        Matrix fit=new Matrix();
        fit.setValues(new float[]{scale,0,(getWidth()-drawing.bounds.width()*scale)/2-drawing.bounds.left*scale,
                0,scale,(getHeight()-drawing.bounds.height()*scale)/2-drawing.bounds.top*scale,0,0,1});
        for (int pathIndex=0;pathIndex<drawing.paths.size();pathIndex++) {
            Path source=drawing.paths.get(pathIndex);
            Path transformed=new Path(source); transformed.transform(fit);
            PathMeasure measure=new PathMeasure(transformed,false);
            do {
                float length=measure.getLength();
                if (!Float.isFinite(length)) throw new IllegalArgumentException("SVG contains invalid curves");
                if(length>0) {
                    Path contour=new Path(); measure.getSegment(0,length,contour,true);
                    strokes.add(new PathMeasure(contour,false));
                    strokeColors.add(drawing.colors.get(pathIndex));
                    strokeWidths.add(drawing.widthFactors.get(pathIndex));
                    strokeFills.add(drawing.fills.get(pathIndex)==Color.TRANSPARENT ? null : transformed);
                    fillColors.add(drawing.fills.get(pathIndex));
                    if(strokes.size()>20000) throw new IllegalArgumentException("Too many strokes");
                }
            } while(measure.nextContour());
        }
        double[] lengths=new double[strokes.size()];
        for(int i=0;i<lengths.length;i++) lengths[i]=strokes.get(i).getLength();
        boolean[] continues=new boolean[lengths.length];
        float[] end=new float[2],start=new float[2];
        for(int i=1;i<lengths.length;i++) {
            if(strokeWidths.get(i)>0 && strokeWidths.get(i-1)>0 && strokeColors.get(i).equals(strokeColors.get(i-1))) {
                strokes.get(i-1).getPosTan((float)lengths[i-1],end,null);
                strokes.get(i).getPosTan(0,start,null);
                continues[i]=Math.hypot(end[0]-start[0],end[1]-start[1])<0.01;
            }
        }
        playback=new Playback(lengths,0.2,continues);
        playback.restore(fraction,this::drawSegment);
        invalidate(); changed();
    }
    private void drawSegment(int stroke,double from,double to) {
        segment.reset(); strokes.get(stroke).getSegment((float)from,(float)to,segment,true);
        ink.setColor(strokeColors.get(stroke));
        ink.setStrokeWidth(widthDp*getResources().getDisplayMetrics().density*(strokeWidths.get(stroke)==0 ? 1 : strokeWidths.get(stroke)));
        surface.drawPath(segment,ink);
        if(running && direct.active()) {
            if(!direct.segment(stroke,strokes.get(stroke),from,to,ink.getStrokeWidth())) {
                invalidate(); changed(); // Publish all accumulated ink after a failed live stroke.
            }
        }
        RectF b=new RectF(); segment.computeBounds(b,true);
        float pad=ink.getStrokeWidth()/2+2; b.inset(-pad,-pad);
        dirty.union(b);
        // Complete each outline before applying that facet's fill. Progress
        // restoration calls this same path, so resize/pause never loses fills.
        Path fill=strokeFills.get(stroke);
        if(fill!=null && to>=strokes.get(stroke).getLength()-1e-7) {
            fillInk.setColor(fillColors.get(stroke));surface.drawPath(fill,fillInk);
            fill.computeBounds(b,true);b.inset(-2,-2);dirty.union(b);
        }
    }
    private final Runnable tick=new Runnable() {
        @Override public void run() {
            if(!running || playback==null || surface==null) return;
            if(beginDirect) {
                // Let the Draw/Pause control change reach the panel before disabling
                // normal updates. Do not redraw controls after entering scribble mode.
                if(SystemClock.uptimeMillis()<directStartAt) { postDelayed(this,16); return; }
                beginDirect=false; direct.begin(ink.getStrokeWidth()); lastTick=SystemClock.uptimeMillis();
            }
            long now=SystemClock.uptimeMillis();
            // A delayed screen update slows playback instead of jumping across a long stretch.
            double dt=Math.min(0.1,(now-lastTick)/1000.0); lastTick=now;
            dirty.setEmpty();
            playback.advance(dt,speedDp*getResources().getDisplayMetrics().density,InkView.this::drawSegment);
            if(!direct.active() && !dirty.isEmpty()) invalidate((int)Math.floor(dirty.left),(int)Math.floor(dirty.top),
                    (int)Math.ceil(dirty.right),(int)Math.ceil(dirty.bottom));
            if(playback.done()) { pause(); return; }
            postDelayed(this,Math.max(1,1000/fps-(SystemClock.uptimeMillis()-now)));
        }
    };
    @Override protected void onDraw(Canvas canvas) { super.onDraw(canvas); if(bitmap!=null) canvas.drawBitmap(bitmap,0,0,paper); }
    @Override protected void onDetachedFromWindow() { pause(); super.onDetachedFromWindow(); }
}
