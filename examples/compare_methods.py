#!/usr/bin/env python3
"""Compare different edge detection methods."""

import subprocess
import sys
from pathlib import Path


def main():
    """Compare different edge detection methods on Mittens.png."""
    input_file = Path(__file__).parent.parent / "Mittens.png"
    output_dir = Path(__file__).parent.parent / "output" / "comparisons"
    output_dir.mkdir(exist_ok=True)
    
    methods = ['canny', 'sobel', 'laplacian', 'multi_scale']
    
    print("Comparing edge detection methods...")
    print(f"Input: {input_file}")
    print(f"Output directory: {output_dir}\n")
    
    for method in methods:
        output_file = output_dir / f"mittens_{method}.svg"
        preview_file = output_dir / f"mittens_{method}_preview.png"
        
        print(f"Processing with {method} method...")
        
        # Generate preview
        cmd = [
            'squiggle-draw', 'preview',
            str(input_file),
            '-o', str(preview_file),
            '--edge-method', method,
            '--contrast', '1.8'
        ]
        subprocess.run(cmd, check=True)
        
        # Generate SVG
        cmd = [
            'squiggle-draw', 'single',
            str(input_file),
            '-o', str(output_file),
            '--edge-method', method,
            '--contrast', '1.8',
            '--max-dimension', '800',
            '--sample-rate', '0.4'
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        
        # Extract stats
        for line in result.stdout.split('\n'):
            if 'Path length:' in line:
                print(f"  {line.strip()}")
            elif 'Estimated drawing time:' in line:
                print(f"  {line.strip()}")
        
        print(f"  Preview: {preview_file}")
        print(f"  SVG: {output_file}\n")
    
    print("Comparison complete!")


if __name__ == "__main__":
    main()