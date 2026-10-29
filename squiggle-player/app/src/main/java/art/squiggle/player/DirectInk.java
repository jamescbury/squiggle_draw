package art.squiggle.player;

import android.graphics.Paint;
import android.graphics.PathMeasure;
import android.os.Build;
import android.os.SystemClock;
import android.util.Log;
import android.view.View;
import com.onyx.android.sdk.api.device.epd.EpdController;
import com.onyx.android.sdk.device.BaseDevice;
import com.onyx.android.sdk.device.Device;
import java.lang.reflect.Method;
import org.lsposed.hiddenapibypass.HiddenApiBypass;

/** The BOOX SDK calls these same framework methods but swallows invocation errors.
 * Invoke the stroke methods explicitly so unsupported firmware can fall back visibly. */
final class DirectInk {
    private final View view;
    private Method start, add, finish, up, map, penState;
    private float strokeWidth;
    private long penTime;
    private int pointCount;
    private boolean active;
    private boolean supported;
    private int lastStroke = -1;
    private final float[] point = new float[2];
    private final float[] mapped = new float[2];
    private final float[] panelTransform = new float[6];
    private String reason = "Live pen unavailable · using canvas";

    DirectInk(View view) {
        this.view=view;
        if (!(Build.MANUFACTURER+" "+Build.BRAND).toLowerCase(java.util.Locale.ROOT).matches(".*(onyx|boox).*")) return;
        try {
            // Approved compatibility access is limited to these BOOX SDK types.
            boolean visible=HiddenApiBypass.addHiddenApiExemptions(
                    "Landroid/onyx/ViewUpdateHelper;",
                    "Landroid/onyx/optimization/Constant;",
                    "Landroid/view/View;");
            Log.i("Squiggle","BOOX extension reflection enabled="+visible);
            Device.currentDevice(); // Initialize the firmware's waveform constants.
            Class<?> helper=Class.forName("android.onyx.ViewUpdateHelper");
            Class<?>[] strokeArgs={float.class,float.class,float.class,float.class,float.class,float.class};
            start=helper.getMethod("startStroke",strokeArgs);
            add=helper.getMethod("addStrokePoint",strokeArgs);
            finish=helper.getMethod("finishStroke",strokeArgs);
            up=helper.getMethod("penUp");
            penState=helper.getMethod("setScreenHandWritingPenState",int.class);
            map=helper.getMethod("mapToEpd",View.class,float[].class,float[].class);
            supported=true; reason="Direct pen ready";
            Log.i("Squiggle", "Direct pen methods found; device="+Device.currentDevice().getClass().getSimpleName());
        } catch (ReflectiveOperationException | LinkageError | RuntimeException e) {
            Log.w("Squiggle","Direct pen not supported",e);
        }
    }
    String status() { return reason; }
    boolean available() { return supported; }
    boolean active() { return active; }
    boolean begin(float width) {
        if(!supported) return false;
        try {
            EpdController.setStrokeColor(android.graphics.Color.BLACK);
            EpdController.setStrokeStyle(0);
            EpdController.setPainterStyle(true,Paint.Style.STROKE,Paint.Join.ROUND,Paint.Cap.ROUND);
            EpdController.setStrokeWidth(width);
            // Evaluate the firmware's view-to-panel transform once per session.
            float[] origin=panelPosition(0,0), xAxis=panelPosition(100,0), yAxis=panelPosition(0,100);
            panelTransform[0]=(xAxis[0]-origin[0])/100; panelTransform[1]=(yAxis[0]-origin[0])/100;
            panelTransform[2]=origin[0]; panelTransform[3]=(xAxis[1]-origin[1])/100;
            panelTransform[4]=(yAxis[1]-origin[1])/100; panelTransform[5]=origin[1];
            float determinant=panelTransform[0]*panelTransform[4]-panelTransform[1]*panelTransform[3];
            if(!Float.isFinite(determinant) || Math.abs(determinant)<0.0001f)
                throw new IllegalStateException("BOOX returned an invalid panel transform");
            Log.i("Squiggle","View-to-panel="+java.util.Arrays.toString(panelTransform));
            penState.invoke(null,1); // Allocate the hardware pen session, as EpdPenManager does.
            penState.invoke(null,2); // Resume live rendering.
            EpdController.enterScribbleMode(view);
            lastStroke=-1; strokeWidth=width; penTime=SystemClock.uptimeMillis(); pointCount=0;
            active=true; reason="Drawing with stroke points";
            Log.i("Squiggle","Direct pen started; width="+width+" waveform="+BaseDevice.UPDATE_MODE_DU);
            return true;
        } catch(ReflectiveOperationException | LinkageError | RuntimeException e) { failed(e); return false; }
    }
    boolean segment(int stroke,PathMeasure path,double from,double to,float width) {
        if(!active) return false;
        try {
            if(lastStroke!=stroke) {
                finishStroke();
                if(!path.getPosTan((float)from,point,null)) throw new IllegalStateException("Missing pen position");
                toPanel(point);
                float actualWidth=strokePoint(start);
                Log.i("Squiggle","Stroke-start returned width="+actualWidth);
                if(!Float.isFinite(actualWidth) || actualWidth<=0)
                    throw new IllegalStateException("Tablet did not accept the live stroke (width="+actualWidth+")");
                lastStroke=stroke;
                Log.i("Squiggle","Stroke "+stroke+" begins at canvas="+java.util.Arrays.toString(point)
                        +" panel="+java.util.Arrays.toString(mapped)+" length="+path.getLength());
            }
            // Subpixel samples follow the curve, without replacing it by a long chord.
            int count=Math.max(1,(int)Math.ceil((to-from)/0.75));
            for(int i=1;i<=count;i++) {
                if(!path.getPosTan((float)(from+(to-from)*i/count),point,null))
                    throw new IllegalStateException("Missing curve position");
                toPanel(point);
                float actualWidth=strokePoint(add);
                if(!Float.isFinite(actualWidth) || actualWidth<=0)
                    throw new IllegalStateException("Tablet did not accept a stroke point");
                if(pointCount++%1000==0) Log.i("Squiggle","Stroke-point "+pointCount
                        +" at panel="+java.util.Arrays.toString(mapped)+" width="+actualWidth);
            }
            return true;
        } catch(ReflectiveOperationException | LinkageError | RuntimeException e) { failed(e); return false; }
    }
    private float strokePoint(Method method) throws ReflectiveOperationException {
        float time=SystemClock.uptimeMillis()-penTime;
        return ((Number)method.invoke(null,strokeWidth,mapped[0],mapped[1],1f,1f,time)).floatValue();
    }
    private void finishStroke() throws ReflectiveOperationException {
        if(lastStroke>=0) strokePoint(finish);
        up.invoke(null); lastStroke=-1;
    }
    private float[] panelPosition(float x,float y) throws ReflectiveOperationException {
        float[] result=new float[2];
        map.invoke(null,view,new float[]{x,y},result);
        return result;
    }
    private void toPanel(float[] source) {
        mapped[0]=panelTransform[0]*source[0]+panelTransform[1]*source[1]+panelTransform[2];
        mapped[1]=panelTransform[3]*source[0]+panelTransform[4]*source[1]+panelTransform[5];
    }
    void end() {
        if(!active) return;
        active=false;
        try { finishStroke(); }
        catch(ReflectiveOperationException | RuntimeException e) { Log.w("Squiggle","Pen lift failed",e); }
        finally {
            try { penState.invoke(null,0); EpdController.leaveScribbleMode(view); }
            catch(ReflectiveOperationException | LinkageError | RuntimeException e) { Log.w("Squiggle","Scribble reset failed",e); }
        }
        reason=supported?"Direct pen ready":"Direct pen unavailable · using canvas";
    }
    private void failed(Throwable error) {
        Log.w("Squiggle","Direct pen failed; reverting to canvas",error);
        supported=false; end(); reason="Direct pen unavailable · using canvas";
    }
}
