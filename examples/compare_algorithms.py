#!/usr/bin/env python3
"""Compare old vs new algorithms."""

import subprocess
import sys
from pathlib import Path


def main():
    """Compare different algorithms."""
    input_file = Path("Mittens.png")
    output_dir = Path("output/algorithm_comparison")
    output_dir.mkdir(exist_ok=True)
    
    # Test configurations
    tests = [
        {
            "name": "edge_trace_original",
            "args": ["--algorithm", "edge_trace", "--sample-rate", "0.3"],
            "description": "Original edge tracing algorithm"
        },
        {
            "name": "stipple_tsp_low",
            "args": ["--algorithm", "stipple_tsp", "--stipple-density", "0.5"],
            "description": "Stipple TSP with low density"
        },
        {
            "name": "stipple_tsp_medium",
            "args": ["--algorithm", "stipple_tsp", "--stipple-density", "1.0", "--edge-weight", "0.4"],
            "description": "Stipple TSP with medium density"
        },
        {
            "name": "stipple_tsp_high",
            "args": ["--algorithm", "stipple_tsp", "--stipple-density", "2.0", "--edge-weight", "0.6", "--optimization-level", "3-opt"],
            "description": "Stipple TSP with high density and 3-opt"
        },
        {
            "name": "scribble_style",
            "args": ["--algorithm", "scribble", "--stipple-density", "0.8"],
            "description": "Scribble style algorithm"
        }
    ]
    
    print("Algorithm Comparison")
    print("=" * 80)
    print(f"Input: {input_file}")
    print(f"Output directory: {output_dir}\n")
    
    results = []
    
    for test in tests:
        output_file = output_dir / f"{test['name']}.svg"
        print(f"\n{test['description']}:")
        print(f"  Output: {output_file}")
        
        # Build command
        cmd = [
            'squiggle-draw', 'single',
            str(input_file),
            '-o', str(output_file),
            '--max-dimension', '800',
            '--contrast', '1.8'
        ] + test['args']
        
        print(f"  Command: {' '.join(cmd)}")
        
        try:
            # Run command
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            
            # Extract statistics
            stats = {}
            for line in result.stdout.split('\n'):
                if 'Path length:' in line:
                    stats['path_length'] = line.split(':')[1].strip()
                elif 'Estimated drawing time:' in line:
                    stats['time'] = line.split(':')[1].strip()
            
            # Get file size
            file_size = output_file.stat().st_size
            stats['file_size'] = f"{file_size / 1024:.1f} KB"
            
            print(f"  ✓ Success!")
            print(f"    - Path length: {stats.get('path_length', 'N/A')}")
            print(f"    - Drawing time: {stats.get('time', 'N/A')}")
            print(f"    - File size: {stats['file_size']}")
            
            results.append({
                'name': test['name'],
                'description': test['description'],
                **stats
            })
            
        except subprocess.CalledProcessError as e:
            print(f"  ✗ Failed: {e.stderr}")
            results.append({
                'name': test['name'],
                'description': test['description'],
                'error': 'Failed'
            })
    
    # Summary table
    print("\n" + "=" * 80)
    print("Summary:")
    print(f"{'Algorithm':<25} {'Path Length':<15} {'Time':<15} {'File Size':<10}")
    print("-" * 80)
    
    for r in results:
        if 'error' not in r:
            print(f"{r['name']:<25} {r.get('path_length', 'N/A'):<15} {r.get('time', 'N/A'):<15} {r['file_size']:<10}")
        else:
            print(f"{r['name']:<25} {'ERROR':<15} {'':<15} {'':<10}")


if __name__ == "__main__":
    main()