package art.squiggle.player;

import java.util.ArrayList;
import java.util.List;

public class PlaybackTest {
    static int checks;
    static void near(double got,double expected) {
        checks++;
        if(Math.abs(got-expected)>1e-6) throw new AssertionError(got+" != "+expected);
    }
    public static void main(String[] args) {
        List<String> emitted=new ArrayList<>();
        Playback p=new Playback(new double[]{10,20},.2);
        Playback.Sink record=(stroke,from,to)->emitted.add(stroke+":"+from+":"+to);
        p.advance(.5,10,record); near(p.distance,5); near(p.fraction(),1.0/6);
        p.advance(.5,10,record); near(p.stroke,1); near(p.distance,0);
        p.advance(.1,10,record); near(p.distance,0); // lifting consumes time, never draws a connecting stroke
        p.advance(.2,20,record); near(p.distance,2); // speed change preserves the last tip position
        p.advance(1,20,record); near(p.fraction(),1); near(p.done()?1:0,1);
        near(emitted.size(),4);
        p.advance(100,100,record); near(emitted.size(),4); // completion cannot add ink

        Playback split=new Playback(new double[]{3,7,10},.2);
        Playback batched=new Playback(new double[]{3,7,10},.2);
        Playback.Sink ignore=(s,a,b)->{};
        for(int i=0;i<50;i++) split.advance(.02,10,ignore);
        batched.advance(1,10,ignore);
        near(split.stroke,batched.stroke); near(split.distance,batched.distance); near(split.fraction(),batched.fraction());
        split.restore(.5,ignore); near(split.stroke,2); near(split.distance,0); near(split.fraction(),.5);
        split.restore(.75,ignore); near(split.stroke,2); near(split.distance,5);
        split.restore(1,ignore); near(split.done()?1:0,1);
        split.restore(0,ignore); near(split.stroke,0); near(split.fraction(),0);
        Playback empty=new Playback(new double[0],.2); near(empty.done()?1:0,1); near(empty.fraction(),1);
        try { new Playback(new double[]{Double.NaN},.2); throw new AssertionError("NaN accepted"); } catch(IllegalArgumentException expected) { checks++; }
        try { p.advance(.1,0,ignore); throw new AssertionError("Zero speed accepted"); } catch(IllegalArgumentException expected) { checks++; }
        System.out.println("Playback: "+checks+" checks passed");
    }
}
