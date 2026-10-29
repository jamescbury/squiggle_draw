package art.squiggle.player;

import android.app.Activity;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;
import android.view.WindowManager;
import com.onyx.android.sdk.device.Device;

/** Screen/CPU protection scoped to foreground playback, with a bounded lease. */
final class DrawingAwake {
    private final Activity activity;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private PowerManager.WakeLock lock;
    private boolean drawing;
    private final Runnable renew=new Runnable() {
        @Override public void run() {
            if(!drawing) return;
            try { if(lock!=null) lock.acquire(10*60*1000L); }
            catch(RuntimeException error) { Log.w("Squiggle","Could not keep drawing awake",error); }
            handler.postDelayed(this,60*1000L);
        }
    };
    DrawingAwake(Activity activity) { this.activity=activity; }
    @SuppressWarnings("deprecation")
    void setDrawing(boolean value) {
        if(drawing==value) return;
        drawing=value;
        if(value) {
            activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            try {
                if(lock==null) {
                    String maker=(Build.MANUFACTURER+" "+Build.BRAND).toLowerCase(java.util.Locale.ROOT);
                    // BOOX uses FULL_WAKE_LOCK and recognizes the onyx_ tag prefix.
                    // The device rejected an ordinary tag and the WindowManager lock.
                    if(maker.contains("onyx") || maker.contains("boox"))
                        lock=Device.currentDevice().newWakeLock(activity,"onyx_Squiggle:Drawing");
                    else {
                        PowerManager power=(PowerManager)activity.getSystemService(Activity.POWER_SERVICE);
                        lock=power.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK,"onyx_Squiggle:Drawing");
                    }
                    lock.setReferenceCounted(false);
                }
                renew.run();
                Log.i("Squiggle","Drawing wake lock held="+lock.isHeld());
            } catch(LinkageError | RuntimeException error) { Log.w("Squiggle","Drawing wake lock unavailable",error); }
        } else {
            handler.removeCallbacks(renew);
            activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            if(lock!=null && lock.isHeld()) lock.release();
            Log.i("Squiggle","Drawing wake lock released");
        }
    }
}
