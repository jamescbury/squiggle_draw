"""Live preview support for progressive rendering."""

from typing import List, Tuple, Optional, Callable, Any
import numpy as np
from pathlib import Path
import time
from threading import Lock
from ..generators.svg_generator import SVGGenerator


class LivePreviewManager:
    """Manages live preview updates during processing."""
    
    def __init__(self, 
                 preview_callback: Optional[Callable] = None,
                 update_interval: float = 0.5):
        """
        Initialize preview manager.
        
        Args:
            preview_callback: Function to call with preview data
            update_interval: Minimum time between updates (seconds)
        """
        self.preview_callback = preview_callback
        self.update_interval = update_interval
        self.last_update = 0
        self.points_buffer = []
        self.stipple_points = []  # Store stipple points separately
        self.lock = Lock()
        self.generator = SVGGenerator()
        self.dimensions = (800, 600)  # Default dimensions
        self.current_phase = "init"  # Track current phase
        
    def set_dimensions(self, dimensions: Tuple[int, int]):
        """Set the image dimensions for SVG generation."""
        self.dimensions = dimensions
        
    def set_stipple_points(self, stipple_points: np.ndarray):
        """Set the stipple points for display."""
        with self.lock:
            self.stipple_points = [(p[0], p[1]) for p in stipple_points]
            self.current_phase = "stipples"
        self._update_preview()
        
    def set_tsp_path(self, path_points: List[Tuple[float, float]]):
        """Set the TSP path for display."""
        with self.lock:
            self.current_phase = "tsp"
        self._update_preview()
        
    def add_points(self, points: List[Tuple[float, float]], force_update: bool = False):
        """
        Add points to the preview buffer.
        
        Args:
            points: New points to add
            force_update: Force an immediate preview update
        """
        with self.lock:
            self.points_buffer.extend(points)
            
        # Check if we should update preview
        current_time = time.time()
        if force_update or (current_time - self.last_update) >= self.update_interval:
            self._update_preview()
            self.last_update = current_time
            
    def _update_preview(self):
        """Generate and send preview update."""
        if not self.preview_callback or not self.points_buffer:
            return
            
        with self.lock:
            # Create a copy of current points
            preview_points = self.points_buffer.copy()
            
        # Generate preview SVG
        preview_data = self._generate_preview_svg(preview_points)
        
        # Send to callback
        self.preview_callback({
            'type': 'preview',
            'points_count': len(preview_points),
            'svg_content': preview_data
        })
    
    def _generate_preview_svg(self, points: List[Tuple[float, float]]) -> str:
        """Generate SVG content for preview."""
        # Create SVG with current points
        import svgwrite
        from svgwrite import mm
        
        # Get actual dimensions
        img_width, img_height = self.dimensions
        
        # Create SVG with actual image dimensions (not A4)
        # This ensures the preview matches the final output
        dwg = svgwrite.Drawing(
            size=(f'{img_width}px', f'{img_height}px'), 
            viewBox=f'0 0 {img_width} {img_height}'
        )
        
        # Add white background
        dwg.add(dwg.rect(insert=(0, 0), size=(img_width, img_height), fill='white'))
        
        # Draw stipple points if in stipple phase
        if self.stipple_points and self.current_phase in ["stipples", "tsp"]:
            stipple_group = dwg.g(id='stipples', fill='lightblue', stroke='none', opacity=0.5)
            for x, y in self.stipple_points:
                stipple_group.add(dwg.circle(center=(x, y), r=2))
            dwg.add(stipple_group)
        
        # Build path data for scribbles
        if points and len(points) > 1:
            path_data = []
            for i, (x, y) in enumerate(points):
                if i == 0:
                    path_data.append(f"M {x:.2f},{y:.2f}")
                else:
                    path_data.append(f"L {x:.2f},{y:.2f}")
            
            # Add path to drawing
            path = dwg.path(
                d=" ".join(path_data),
                stroke='black',
                stroke_width='0.5',
                fill='none',
                stroke_linecap='round',
                stroke_linejoin='round'
            )
            dwg.add(path)
        
        # Add progress indicator
        phase_text = {
            "stipples": "Generating stipples",
            "tsp": "Optimizing path",
            "scribbles": "Drawing scribbles"
        }.get(self.current_phase, "Processing")
        
        progress_text = dwg.text(
            f'{phase_text} - {len(points):,} points',
            insert=(10, img_height - 10),
            fill='gray',
            font_size='12px',
            font_family='Arial'
        )
        dwg.add(progress_text)
        
        return dwg.tostring()
    
    def _generate_empty_svg(self) -> str:
        """Generate empty SVG placeholder."""
        import svgwrite
        dwg = svgwrite.Drawing(size=(f'210mm', f'297mm'), viewBox=f'0 0 210 297')
        # Add placeholder text
        text = dwg.text(
            'Preview will appear here...',
            insert=(105, 148.5),
            text_anchor='middle',
            fill='lightgray',
            font_size='12pt'
        )
        dwg.add(text)
        return dwg.tostring()
    
    def finalize(self, final_points: Optional[List[Tuple[float, float]]] = None):
        """Send final preview update."""
        if final_points:
            with self.lock:
                self.points_buffer = final_points
                
        self._update_preview()
        
        if self.preview_callback:
            self.preview_callback({
                'type': 'complete',
                'points_count': len(self.points_buffer)
            })