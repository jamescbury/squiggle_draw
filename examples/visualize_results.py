#!/usr/bin/env python3
"""Visualize the difference between algorithms."""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import xml.etree.ElementTree as ET
import numpy as np
from pathlib import Path
import re


def extract_path_from_svg(svg_file):
    """Extract path data from SVG file."""
    tree = ET.parse(svg_file)
    root = tree.getroot()
    
    # Find the path element
    for elem in root.iter():
        if elem.tag.endswith('path'):
            return elem.get('d')
    return None


def parse_svg_path(path_data):
    """Parse SVG path data into points."""
    points = []
    commands = path_data.split()
    
    i = 0
    while i < len(commands):
        cmd = commands[i]
        if cmd in ['M', 'L']:  # Move or Line
            i += 1
            if i < len(commands):
                coords = commands[i].split(',')
                if len(coords) == 2:
                    x, y = float(coords[0]), float(coords[1])
                    points.append((x, y))
        i += 1
    
    return points


def main():
    """Compare different SVG outputs."""
    # Files to compare
    files = {
        'Original Edge Trace': 'output/mittens_line_art.svg',
        'Improved Stipple TSP': 'output/mittens_improved.svg',
        'Dense Stipple TSP': 'output/mittens_dense.svg'
    }
    
    # Create figure
    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    
    for idx, (title, svg_file) in enumerate(files.items()):
        ax = axes[idx]
        
        if Path(svg_file).exists():
            # Extract path
            path_data = extract_path_from_svg(svg_file)
            if path_data:
                points = parse_svg_path(path_data)
                
                if points:
                    # Convert to numpy array
                    points = np.array(points)
                    
                    # Plot
                    ax.plot(points[:, 0], points[:, 1], 'k-', linewidth=0.5)
                    ax.set_aspect('equal')
                    ax.invert_yaxis()  # SVG has Y pointing down
                    ax.set_title(f'{title}\n{len(points)} points')
                    ax.set_xlim(0, 210)  # A4 width in mm
                    ax.set_ylim(297, 0)  # A4 height in mm
                    
                    # Add file size
                    file_size = Path(svg_file).stat().st_size / 1024
                    ax.text(0.5, -0.1, f'{file_size:.1f} KB', 
                           transform=ax.transAxes, ha='center')
                else:
                    ax.text(0.5, 0.5, 'No points found', 
                           transform=ax.transAxes, ha='center')
            else:
                ax.text(0.5, 0.5, 'No path found', 
                       transform=ax.transAxes, ha='center')
        else:
            ax.text(0.5, 0.5, 'File not found', 
                   transform=ax.transAxes, ha='center')
        
        ax.set_xlabel('X (mm)')
        ax.set_ylabel('Y (mm)')
        ax.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig('output/algorithm_comparison.png', dpi=150, bbox_inches='tight')
    print("Comparison saved to output/algorithm_comparison.png")
    
    # Print statistics
    print("\nAlgorithm Comparison:")
    print("-" * 60)
    for title, svg_file in files.items():
        if Path(svg_file).exists():
            path_data = extract_path_from_svg(svg_file)
            if path_data:
                points = parse_svg_path(path_data)
                file_size = Path(svg_file).stat().st_size / 1024
                print(f"{title:<25} {len(points):>6} points  {file_size:>6.1f} KB")


if __name__ == "__main__":
    main()