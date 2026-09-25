#!/usr/bin/env python3
"""Simple test of the true scribbler implementation."""

import sys
from pathlib import Path
import time

# Add the src directory to Python path
sys.path.insert(0, str(Path(__file__).parent.parent / 'src'))

from squiggle_draw.core.scribbler_pipeline import ScribblerPipeline


def progress_callback(message: str, progress: float):
    """Print progress updates."""
    if progress >= 0:
        bar_length = 40
        filled = int(bar_length * progress)
        bar = "█" * filled + "░" * (bar_length - filled)
        print(f"\r[{bar}] {int(progress*100):3}% - {message:<50}", end="", flush=True)
    else:
        print(f"\nError: {message}")


def main():
    """Test with simple parameters."""
    input_path = Path("input/Mittens.png")
    if not input_path.exists():
        print(f"Error: {input_path} not found!")
        return
    
    # Create output directory
    output_dir = Path("output/scribbler_test")
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / "scribbler_simple.svg"
    
    print("Testing True Scribbler Implementation (Simple)")
    print("=" * 70)
    print(f"Input: {input_path}")
    print(f"Output: {output_path}\n")
    
    # Use moderate parameters
    params = {
        "num_stipples": 500,  # Fewer stipples for faster processing
        "rmin": 2.0,
        "rmax": 12.0,
        "dtmin": 0.5,  # Larger step size for fewer scribble points
        "dtmax": 10.0,
        "dtheta": 90.0,  # Larger rotation for fewer points
        "smooth_scribbles": False  # Skip smoothing for speed
    }
    
    print("Parameters:")
    for key, value in params.items():
        print(f"  {key}: {value}")
    
    pipeline = ScribblerPipeline(progress_callback=progress_callback)
    
    try:
        start_time = time.time()
        stats = pipeline.process(
            input_path,
            output_path,
            max_dimension=600,
            contrast=1.5,
            **params
        )
        
        elapsed = time.time() - start_time
        print(f"\n\n✓ Completed in {elapsed:.1f}s")
        print(f"  Stipples: {stats['num_stipples']:,}")
        print(f"  Scribble points: {stats['path_length']:,}")
        print(f"  Estimated draw time: {stats['estimated_time_seconds']:.1f}s")
        print(f"  Output: {output_path}")
        
        # Show file size
        file_size = output_path.stat().st_size / 1024
        print(f"  File size: {file_size:.1f} KB")
        
    except Exception as e:
        print(f"\n✗ Failed: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()