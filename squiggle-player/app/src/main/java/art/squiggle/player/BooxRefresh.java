package art.squiggle.player;

import android.os.Build;
import android.util.Log;
import android.view.View;
import com.onyx.android.sdk.api.device.epd.EpdController;
import com.onyx.android.sdk.api.device.epd.UpdateMode;

/** Only view-scoped settings. No global refresh or stylus settings are changed. */
final class BooxRefresh {
    private boolean available = (Build.MANUFACTURER + " " + Build.BRAND).toLowerCase(java.util.Locale.ROOT).matches(".*(onyx|boox).*" );
    private boolean applied;
    String apply(View view, String choice) {
        applied = false;
        if (!available) return "Use your tablet’s per-app refresh setting";
        try {
            if (choice.equals("System")) {
                applied = EpdController.resetViewUpdateMode(view);
            } else {
                UpdateMode mode = choice.equals("Fast") ? UpdateMode.DU
                        : choice.equals("Animation") ? UpdateMode.ANIMATION : UpdateMode.GU;
                applied = EpdController.setViewDefaultUpdateMode(view, mode);
            }
            return applied ? "Refresh setting accepted" : "Use EinkWise to choose refresh mode";
        } catch (LinkageError | RuntimeException error) {
            available = false;
            Log.w("Squiggle", "BOOX refresh API unavailable", error);
            return "Use EinkWise to choose refresh mode";
        }
    }
    void clean(View view) {
        view.invalidate();
        if (available) {
            try { EpdController.refreshScreen(view, UpdateMode.GC); }
            catch (LinkageError | RuntimeException error) { Log.w("Squiggle", "Cleanup unavailable", error); }
        }
    }
    void release(View view) {
        if (!available || !applied) return;
        try { EpdController.resetViewUpdateMode(view); }
        catch (LinkageError | RuntimeException error) { Log.w("Squiggle", "Reset unavailable", error); }
        applied = false;
    }
}
