package art.squiggle.player;

import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=34,manifest=Config.NONE)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class NavigationTest {
    private Button find(View view,String label) {
        if(view instanceof Button && ((Button)view).getText().toString().equals(label)) return (Button)view;
        if(view instanceof ViewGroup) for(int i=0;i<((ViewGroup)view).getChildCount();i++) {Button b=find(((ViewGroup)view).getChildAt(i),label);if(b!=null)return b;}
        return null;
    }
    @Test public void libraryAndBothReturnControlsKeepTheCanvasInstance() {
        MainActivity activity=Robolectric.buildActivity(MainActivity.class).setup().get();
        View root=activity.getWindow().getDecorView();Button draw=find(root,"Draw");
        find(root,"Library").performClick();assertFalse(draw.isShown());
        find(root,"Back to canvas").performClick();assertTrue(draw.isShown());
        find(root,"Library").performClick();activity.onBackPressed();assertTrue(draw.isShown());
        assertSame(draw,find(root,"Draw"));
        activity.finish();
    }
}
