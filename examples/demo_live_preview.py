#!/usr/bin/env python3
"""Demo of live preview functionality."""

import sys
from pathlib import Path
import time
import matplotlib.pyplot as plt
import matplotlib.animation as animation
from matplotlib.patches import Path as MPath
from matplotlib.patches import PathPatch
import numpy as np

# Add the src directory to Python path
sys.path.insert(0, str(Path(__file__).parent.parent / 'src'))

from squiggle_draw.core.scribbler_pipeline import ScribblerPipeline


# Global variables for animation
fig, ax = None, None
preview_points = []
line = None
point_text = None


def preview_callback(points):
    """Update preview with new points."""
    global preview_points
    preview_points = points
    

def update_plot(frame):
    """Update plot for animation."""
    global line, point_text, preview_points
    
    if len(preview_points) > 1:
        # Update line
        x_data = [p[0] for p in preview_points]
        y_data = [p[1] for p in preview_points]
        line.set_data(x_data, y_data)
        
        # Update text
        point_text.set_text(f'{len(preview_points):,} points')
        
    return line, point_text


def main():
    """Run live preview demo."""
    global fig, ax, line, point_text
    
    input_path = Path("input/Mittens.png")
    if not input_path.exists():
        print(f"Error: {input_path} not found!")
        return
    
    print("Live Preview Demo")
    print("=" * 50)
    print("This will show the drawing being built in real-time")
    print()
    
    # Set up the plot
    fig, ax = plt.subplots(figsize=(10, 10))
    ax.set_xlim(0, 600)
    ax.set_ylim(0, 600)
    ax.invert_yaxis()  # Match image coordinates
    ax.set_aspect('equal')
    ax.set_facecolor('white')
    ax.grid(True, alpha=0.3)
    
    # Initialize empty line
    line, = ax.plot([], [], 'k-', linewidth=0.5)
    
    # Add text for point count
    point_text = ax.text(10, 580, '0 points', fontsize=12, color='gray')
    
    plt.title("Squiggle Draw - Live Preview")
    
    # Create pipeline with preview callback
    def progress_callback(message, progress):
        print(f"[{int(progress*100):3}%] {message}")
    
    pipeline = ScribblerPipeline(
        progress_callback=progress_callback,
        preview_callback=preview_callback
    )
    
    # Set up animation
    ani = animation.FuncAnimation(
        fig, update_plot, interval=100, blit=True, cache_frame_data=False
    )
    
    # Show plot
    plt.ion()
    plt.show()
    
    # Process in a separate thread to allow animation
    import threading
    
    output_path = Path("output/demo_live_preview.svg")
    output_path.parent.mkdir(exist_ok=True)
    
    def process():
        stats = pipeline.process(
            input_path,
            output_path,
            max_dimension=600,
            num_stipples=300,
            rmin=2.0,
            rmax=10.0,
            dtmin=0.5,
            dtmax=8.0,
            dtheta=60.0,
            smooth_scribbles=False
        )
        print(f"\nCompleted! Generated {stats['path_length']:,} points")
        print(f"Output: {output_path}")
    
    # Start processing in background
    thread = threading.Thread(target=process)
    thread.start()
    
    # Keep plot open
    plt.show(block=True)
    thread.join()


if __name__ == "__main__":
    main()