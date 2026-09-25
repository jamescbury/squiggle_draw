#!/usr/bin/env python3
"""Test the progress pipeline with different algorithms."""

import sys
from pathlib import Path

# Add the src directory to Python path
sys.path.insert(0, str(Path(__file__).parent.parent / 'src'))

from squiggle_draw.core.progress_pipeline import ProgressPipeline
import time


def progress_callback(message: str, progress: float):
    """Print progress updates."""
    if progress >= 0:
        bar_length = 40
        filled = int(bar_length * progress)
        bar = "█" * filled + "░" * (bar_length - filled)
        print(f"\r[{bar}] {int(progress*100):3}% - {message:<40}", end="", flush=True)
    else:
        print(f"\nError: {message}")


def test_algorithm(algorithm: str, input_path: str, output_dir: str):
    """Test a specific algorithm with progress updates."""
    print(f"\n\nTesting {algorithm} algorithm:")
    print("-" * 60)
    
    pipeline = ProgressPipeline(progress_callback=progress_callback)
    output_path = Path(output_dir) / f"test_{algorithm}.svg"
    
    try:
        start_time = time.time()
        stats = pipeline.process(
            input_path,
            output_path,
            algorithm_type=algorithm,
            stipple_density=0.8,  # Lower density for faster testing
            optimization_level="2-opt",
            max_dimension=600
        )
        
        elapsed = time.time() - start_time
        print(f"\n✓ Completed in {elapsed:.1f}s")
        print(f"  Points: {stats['path_length']:,}")
        print(f"  Output: {output_path}")
        
    except Exception as e:
        print(f"\n✗ Failed: {e}")


def main():
    """Test all algorithms."""
    # Check for input file
    input_path = Path("input/Mittens.png")
    if not input_path.exists():
        print(f"Error: {input_path} not found!")
        return
    
    # Create output directory
    output_dir = Path("output/progress_test")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Test each algorithm
    algorithms = ["stipple_tsp", "tone_aware", "scribble"]
    
    print("Progress Pipeline Test")
    print("=" * 60)
    print(f"Input: {input_path}")
    print(f"Output: {output_dir}")
    
    for algo in algorithms:
        test_algorithm(algo, str(input_path), str(output_dir))
    
    print("\n\nAll tests complete!")


if __name__ == "__main__":
    main()