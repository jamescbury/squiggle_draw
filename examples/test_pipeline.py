#!/usr/bin/env python3
"""Test the single line pipeline with Mittens.png"""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.squiggle_draw.core.pipeline import SingleLinePipeline


def main():
    """Test pipeline with sample image."""
    pipeline = SingleLinePipeline()
    
    # Input and output paths
    input_path = Path(__file__).parent.parent / "Mittens.png"
    output_path = Path(__file__).parent.parent / "output" / "mittens_line_art.svg"
    
    # Ensure output directory exists
    output_path.parent.mkdir(exist_ok=True)
    
    print(f"Processing {input_path}...")
    
    try:
        # Process image
        stats = pipeline.process(
            input_path,
            output_path,
            contrast=1.5,
            brightness=0,
            edge_method="canny",
            path_optimization="greedy",
            max_dimension=800,
            sample_rate=0.3,
            smooth_window=3,
            low_threshold=50,
            high_threshold=150
        )
        
        print(f"\nProcessing complete!")
        print(f"Output saved to: {output_path}")
        print(f"\nStatistics:")
        for key, value in stats.items():
            print(f"  {key}: {value}")
            
    except Exception as e:
        print(f"Error: {e}")
        return 1
    
    return 0


if __name__ == "__main__":
    sys.exit(main())