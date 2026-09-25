#!/usr/bin/env python3
"""Test the true TheScribbler implementation."""

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


def test_scribbler_params():
    """Test different parameter combinations."""
    input_path = Path("input/Mittens.png")
    if not input_path.exists():
        print(f"Error: {input_path} not found!")
        return
    
    # Create output directory
    output_dir = Path("output/scribbler_test")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Test configurations
    configs = [
        {
            "name": "default",
            "params": {
                "num_stipples": 1000,
                "rmin": 2.0,
                "rmax": 16.0,
                "dtmin": 0.2,
                "dtmax": 8.0,
                "dtheta": 80.0
            }
        },
        {
            "name": "fine_detail",
            "params": {
                "num_stipples": 1500,
                "rmin": 1.0,
                "rmax": 8.0,
                "dtmin": 0.1,
                "dtmax": 4.0,
                "dtheta": 45.0
            }
        },
        {
            "name": "bold_strokes",
            "params": {
                "num_stipples": 800,
                "rmin": 4.0,
                "rmax": 24.0,
                "dtmin": 0.5,
                "dtmax": 12.0,
                "dtheta": 120.0
            }
        },
        {
            "name": "dense_scribbles",
            "params": {
                "num_stipples": 1200,
                "rmin": 2.0,
                "rmax": 12.0,
                "dtmin": 0.1,
                "dtmax": 2.0,
                "dtheta": 30.0
            }
        }
    ]
    
    print("Testing True Scribbler Implementation")
    print("=" * 70)
    print(f"Input: {input_path}")
    print(f"Output: {output_dir}\n")
    
    for config in configs:
        print(f"\nTesting configuration: {config['name']}")
        print("-" * 50)
        
        # Print parameters
        for key, value in config['params'].items():
            print(f"  {key}: {value}")
        
        output_path = output_dir / f"scribbler_{config['name']}.svg"
        
        pipeline = ScribblerPipeline(progress_callback=progress_callback)
        
        try:
            start_time = time.time()
            stats = pipeline.process(
                input_path,
                output_path,
                max_dimension=600,
                contrast=1.5,
                **config['params']
            )
            
            elapsed = time.time() - start_time
            print(f"\n✓ Completed in {elapsed:.1f}s")
            print(f"  Stipples: {stats['num_stipples']:,}")
            print(f"  Scribble points: {stats['path_length']:,}")
            print(f"  Estimated draw time: {stats['estimated_time_seconds']:.1f}s")
            print(f"  Output: {output_path}")
            
        except Exception as e:
            print(f"\n✗ Failed: {e}")
            import traceback
            traceback.print_exc()
    
    print("\n\nAll tests complete!")
    print("\nCompare outputs to see the effect of different parameters:")
    print("- default: Balanced parameters similar to original TheScribbler")
    print("- fine_detail: Smaller circles, tighter spacing for more detail")
    print("- bold_strokes: Larger circles, wider spacing for bold effect")
    print("- dense_scribbles: Very tight spacing for dense coverage")


if __name__ == "__main__":
    test_scribbler_params()