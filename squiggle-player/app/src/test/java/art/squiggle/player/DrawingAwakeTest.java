package art.squiggle.player;

import android.app.Activity;
import android.os.Looper;
import android.os.PowerManager;
import android.view.WindowManager;
import java.time.Duration;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowPowerManager;
import static org.robolectric.Shadows.shadowOf;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=34,manifest=Config.NONE)
public class DrawingAwakeTest {
    @Test public void holdsThroughLongPlaybackAndReleasesWithoutReacquiring() {
        Activity activity=Robolectric.buildActivity(Activity.class).setup().get();
        DrawingAwake awake=new DrawingAwake(activity);
        awake.setDrawing(true);
        PowerManager.WakeLock lock=ShadowPowerManager.getLatestWakeLock();
        assertTrue(lock.isHeld());
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMinutes(25));
        assertTrue(lock.isHeld());
        assertTrue((activity.getWindow().getAttributes().flags & WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)!=0);
        awake.setDrawing(false);
        assertFalse(lock.isHeld());
        assertEquals(0,activity.getWindow().getAttributes().flags & WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMinutes(12));
        assertFalse(lock.isHeld());
    }
}
