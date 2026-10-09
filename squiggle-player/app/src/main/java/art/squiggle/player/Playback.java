package art.squiggle.player;

/** Timing independent of Android: lengths are screen pixels, speed is pixels/second. */
final class Playback {
    interface Sink { void segment(int stroke, double from, double to); }
    private final double[] lengths;
    private final double liftSeconds;
    private final boolean[] continues;
    int stroke;
    double distance;
    private double liftRemaining;
    private double drawn;
    final double total;

    Playback(double[] lengths, double liftSeconds) {
        this(lengths,liftSeconds,new boolean[lengths.length]);
    }
    Playback(double[] lengths,double liftSeconds,boolean[] continues) {
        if(continues.length!=lengths.length) throw new IllegalArgumentException("Invalid continuation count");
        this.continues=continues.clone();
        this.lengths = lengths.clone();
        this.liftSeconds = liftSeconds;
        double sum = 0;
        for (double length : lengths) {
            if (!Double.isFinite(length) || length <= 0) throw new IllegalArgumentException("Invalid stroke length");
            sum += length;
        }
        total = sum;
    }
    boolean done() { return stroke >= lengths.length; }
    double fraction() { return total == 0 ? 1 : drawn / total; }
    void restore(double fraction, Sink sink) {
        if (!Double.isFinite(fraction) || fraction < 0 || fraction > 1) throw new IllegalArgumentException("Invalid progress");
        stroke = 0; distance = 0; drawn = 0; liftRemaining = 0;
        double target = total * fraction;
        while (!done() && target > 0) {
            double step = Math.min(target, lengths[stroke]);
            sink.segment(stroke, 0, step);
            drawn += step; target -= step; distance = step;
            if (distance >= lengths[stroke] - 1e-7) { stroke++; distance = 0; }
            else break;
        }
    }
    void advance(double seconds, double speed, Sink sink) {
        if (!Double.isFinite(seconds) || !Double.isFinite(speed) || seconds < 0 || speed <= 0)
            throw new IllegalArgumentException("Invalid playback timing");
        while (seconds > 1e-9 && !done()) {
            if (liftRemaining > 0) {
                double used = Math.min(seconds, liftRemaining);
                liftRemaining -= used;
                seconds -= used;
                continue;
            }
            double remaining = lengths[stroke] - distance;
            double step = Math.min(remaining, seconds * speed);
            if (step > 0) sink.segment(stroke, distance, distance + step);
            distance += step;
            drawn += step;
            seconds -= step / speed;
            if (distance >= lengths[stroke] - 1e-7) {
                stroke++;
                distance = 0;
                liftRemaining = done() || continues[stroke] ? 0 : liftSeconds;
            }
        }
    }
}
