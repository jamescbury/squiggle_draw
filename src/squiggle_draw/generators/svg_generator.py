from typing import List, Tuple, Optional, Dict, Any
import svgwrite
from svgwrite import mm
import numpy as np


class SVGGenerator:
    """Generate SVG files compatible with AxiDraw plotters."""
    
    def __init__(
        self,
        width_mm: float = 210,  # A4 width
        height_mm: float = 297,  # A4 height
        stroke_width: float = 0.5,
        stroke_color: str = "black"
    ) -> None:
        self.width_mm = width_mm
        self.height_mm = height_mm
        self.stroke_width = stroke_width
        self.stroke_color = stroke_color
    
    def create_svg(
        self,
        path: List[Tuple[int, int]],
        image_dimensions: Tuple[int, int],
        output_path: str,
        fit_to_page: bool = True,
        margin_mm: float = 10
    ) -> None:
        """
        Create SVG file from path.
        
        Args:
            path: List of (x, y) coordinates
            image_dimensions: Original image (width, height)
            output_path: Output SVG file path
            fit_to_page: Scale to fit page
            margin_mm: Page margin in mm
        """
        if not path:
            raise ValueError("Path is empty")
        
        # Create SVG drawing
        dwg = svgwrite.Drawing(
            output_path,
            size=(f'{self.width_mm}mm', f'{self.height_mm}mm'),
            viewBox=f'0 0 {self.width_mm} {self.height_mm}'
        )
        
        # Calculate scaling
        if fit_to_page:
            scale_x = (self.width_mm - 2 * margin_mm) / image_dimensions[0]
            scale_y = (self.height_mm - 2 * margin_mm) / image_dimensions[1]
            scale = min(scale_x, scale_y)
            
            # Calculate offsets to center
            scaled_width = image_dimensions[0] * scale
            scaled_height = image_dimensions[1] * scale
            offset_x = (self.width_mm - scaled_width) / 2
            offset_y = (self.height_mm - scaled_height) / 2
        else:
            scale = 1.0
            offset_x = margin_mm
            offset_y = margin_mm
        
        # Convert path to SVG path data
        path_data = self._create_path_data(path, scale, offset_x, offset_y)
        
        # Add path to drawing
        dwg.add(dwg.path(
            d=path_data,
            stroke=self.stroke_color,
            stroke_width=self.stroke_width,
            fill='none',
            stroke_linecap='round',
            stroke_linejoin='round'
        ))
        
        # Save SVG
        dwg.save()
    
    def create_multi_path_svg(
        self,
        paths: List[List[Tuple[int, int]]],
        colors: List[str],
        image_dimensions: Tuple[int, int],
        output_path: str,
        fit_to_page: bool = True,
        margin_mm: float = 10
    ) -> None:
        """
        Create SVG with multiple colored paths.
        
        Args:
            paths: List of paths
            colors: List of colors for each path
            image_dimensions: Original image dimensions
            output_path: Output file path
            fit_to_page: Scale to fit page
            margin_mm: Page margin
        """
        if not paths:
            raise ValueError("No paths provided")
        
        # Create SVG drawing
        dwg = svgwrite.Drawing(
            output_path,
            size=(f'{self.width_mm}mm', f'{self.height_mm}mm'),
            viewBox=f'0 0 {self.width_mm} {self.height_mm}'
        )
        
        # Calculate scaling
        if fit_to_page:
            scale_x = (self.width_mm - 2 * margin_mm) / image_dimensions[0]
            scale_y = (self.height_mm - 2 * margin_mm) / image_dimensions[1]
            scale = min(scale_x, scale_y)
            
            scaled_width = image_dimensions[0] * scale
            scaled_height = image_dimensions[1] * scale
            offset_x = (self.width_mm - scaled_width) / 2
            offset_y = (self.height_mm - scaled_height) / 2
        else:
            scale = 1.0
            offset_x = margin_mm
            offset_y = margin_mm
        
        # Create groups for each color
        for i, (path, color) in enumerate(zip(paths, colors)):
            if not path:
                continue
            
            # Create group with layer name
            group = dwg.g(id=f'layer{i+1}', inkscape_label=f'Color_{color}')
            
            # Convert path to SVG path data
            path_data = self._create_path_data(path, scale, offset_x, offset_y)
            
            # Add path to group
            group.add(dwg.path(
                d=path_data,
                stroke=color,
                stroke_width=self.stroke_width,
                fill='none',
                stroke_linecap='round',
                stroke_linejoin='round'
            ))
            
            dwg.add(group)
        
        # Save SVG
        dwg.save()
    
    def _create_path_data(
        self,
        path: List[Tuple[int, int]],
        scale: float,
        offset_x: float,
        offset_y: float
    ) -> str:
        """
        Convert coordinate list to SVG path data.
        
        Args:
            path: List of (x, y) coordinates
            scale: Scaling factor
            offset_x: X offset in mm
            offset_y: Y offset in mm
            
        Returns:
            SVG path data string
        """
        if not path:
            return ""
        
        # Start with move to first point
        x, y = path[0]
        x_mm = x * scale + offset_x
        y_mm = y * scale + offset_y
        path_data = f"M {x_mm:.2f},{y_mm:.2f}"
        
        # Add line segments
        for x, y in path[1:]:
            x_mm = x * scale + offset_x
            y_mm = y * scale + offset_y
            path_data += f" L {x_mm:.2f},{y_mm:.2f}"
        
        return path_data
    
    def add_registration_marks(
        self,
        dwg: svgwrite.Drawing,
        size: float = 5.0
    ) -> None:
        """
        Add registration marks for alignment.
        
        Args:
            dwg: SVG drawing object
            size: Mark size in mm
        """
        # Corner positions
        positions = [
            (size, size),  # Top-left
            (self.width_mm - size, size),  # Top-right
            (size, self.height_mm - size),  # Bottom-left
            (self.width_mm - size, self.height_mm - size)  # Bottom-right
        ]
        
        for x, y in positions:
            # Cross mark
            dwg.add(dwg.line(
                start=(x - size/2, y),
                end=(x + size/2, y),
                stroke='black',
                stroke_width=0.25
            ))
            dwg.add(dwg.line(
                start=(x, y - size/2),
                end=(x, y + size/2),
                stroke='black',
                stroke_width=0.25
            ))
    
    def estimate_drawing_time(
        self,
        path: List[Tuple[int, int]],
        speed_mm_per_sec: float = 50.0
    ) -> float:
        """
        Estimate drawing time in seconds.
        
        Args:
            path: Drawing path
            speed_mm_per_sec: Plotter speed
            
        Returns:
            Estimated time in seconds
        """
        if len(path) < 2:
            return 0.0
        
        total_distance = 0.0
        for i in range(1, len(path)):
            x1, y1 = path[i-1]
            x2, y2 = path[i]
            distance = np.sqrt((x2 - x1)**2 + (y2 - y1)**2)
            total_distance += distance
        
        # Convert to mm (assuming 1 pixel = 0.1 mm for estimation)
        total_distance_mm = total_distance * 0.1
        
        return total_distance_mm / speed_mm_per_sec