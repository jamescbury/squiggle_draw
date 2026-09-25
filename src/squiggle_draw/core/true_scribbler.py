"""True implementation of TheScribbler algorithm."""

import numpy as np
from typing import List, Tuple, Optional, Callable
import math
from scipy.interpolate import splprep, splev


class TrueScribbler:
    """Implementation of 'Tone- and Feature-Aware Circular Scribble Art' algorithm."""
    
    def __init__(self, progress_callback: Optional[Callable] = None, 
                 preview_callback: Optional[Callable] = None):
        self.progress_callback = progress_callback
        self.preview_callback = preview_callback
        
    def generate_scribbles(
        self,
        image: np.ndarray,
        tracing_path: List[Tuple[float, float]],
        rmin: float = 2.0,
        rmax: float = 16.0,
        dtmin: float = 0.2,
        dtmax: float = 8.0,
        dtheta: float = 80.0
    ) -> List[Tuple[float, float]]:
        """
        Generate scribbles along a TSP path based on image intensity.
        
        Args:
            image: Grayscale image (0-255)
            tracing_path: TSP-optimized path through stipple points
            rmin: Minimum circle radius (bright areas)
            rmax: Maximum circle radius (dark areas)
            dtmin: Minimum step distance (dark areas - denser)
            dtmax: Maximum step distance (bright areas - sparser)
            dtheta: Rotation increment in degrees
            
        Returns:
            List of scribble points
        """
        if len(tracing_path) < 2:
            return []
            
        # Calculate total path length
        total_length = self._calculate_path_length(tracing_path)
        
        # Initialize
        scribble_points = []
        theta = 0.0  # Current rotation angle
        cur_distance = 0.0  # Distance traveled along path
        
        # Progress tracking
        last_progress = 0
        preview_points = []
        preview_update_interval = int(total_length / 20)  # Update preview 20 times
        last_preview_distance = 0
        
        while cur_distance < total_length:
            # Update progress
            progress = cur_distance / total_length
            if self.progress_callback and int(progress * 100) > last_progress:
                last_progress = int(progress * 100)
                self.progress_callback(
                    f"Generating scribbles... {last_progress}%", 
                    0.4 + progress * 0.4
                )
            
            # 1. Find current position along the TSP path
            center_x, center_y = self._interpolate_path_position(
                tracing_path, cur_distance, total_length
            )
            
            if center_x is None:
                break
                
            # 2. Sample image intensity at current position
            gray_value = self._sample_intensity(image, center_x, center_y)
            
            # 3. Map intensity to radius and step size
            # Apply tone mapping: darker = larger values
            tone_mapped = self._apply_tone_curve(gray_value)
            
            # Invert mapping: dark areas get larger circles
            radius = self._map_to_range(1.0 - tone_mapped, rmin, rmax)
            # Invert mapping: dark areas move slower (denser scribbles)
            dt = self._map_to_range(tone_mapped, dtmin, dtmax)
            
            # 4. Generate circular scribble point
            theta_rad = math.radians(theta)
            x_offset = radius * math.cos(theta_rad)
            y_offset = radius * math.sin(theta_rad)
            
            # Translate to path position
            scribble_x = center_x + x_offset
            scribble_y = center_y + y_offset
            
            # Ensure point is within image bounds
            if (0 <= scribble_x < image.shape[1] and 
                0 <= scribble_y < image.shape[0]):
                scribble_points.append((scribble_x, scribble_y))
                preview_points.append((scribble_x, scribble_y))
            
            # Send preview update if needed
            if (self.preview_callback and 
                cur_distance - last_preview_distance > preview_update_interval):
                self.preview_callback(preview_points.copy())
                last_preview_distance = cur_distance
            
            # 5. Update for next iteration
            theta += dtheta  # Rotate for next circle point
            cur_distance += dt  # Move along path
            
        if self.progress_callback:
            self.progress_callback("Scribble generation complete", 0.8)
            
        return scribble_points
    
    def _calculate_path_length(self, path: List[Tuple[float, float]]) -> float:
        """Calculate total length of the path."""
        total = 0.0
        for i in range(len(path)):
            p1 = path[i]
            p2 = path[(i + 1) % len(path)]
            total += np.linalg.norm(np.array(p2) - np.array(p1))
        return total
    
    def _interpolate_path_position(
        self, 
        path: List[Tuple[float, float]], 
        distance: float,
        total_length: float
    ) -> Tuple[Optional[float], Optional[float]]:
        """Find x,y position at given distance along path."""
        # Handle wrapping for closed path
        distance = distance % total_length
        
        accumulated_dist = 0.0
        
        for i in range(len(path)):
            p1 = path[i]
            p2 = path[(i + 1) % len(path)]
            
            segment_length = np.linalg.norm(np.array(p2) - np.array(p1))
            
            if accumulated_dist <= distance < accumulated_dist + segment_length:
                # Interpolate within this segment
                if segment_length > 0:
                    t = (distance - accumulated_dist) / segment_length
                    x = p1[0] + t * (p2[0] - p1[0])
                    y = p1[1] + t * (p2[1] - p1[1])
                    return x, y
                else:
                    return p1[0], p1[1]
            
            accumulated_dist += segment_length
        
        # Shouldn't reach here for closed path
        return path[0][0], path[0][1]
    
    def _sample_intensity(
        self, 
        image: np.ndarray, 
        x: float, 
        y: float
    ) -> float:
        """Sample image intensity with bilinear interpolation."""
        height, width = image.shape
        
        # Clamp to image bounds
        x = max(0, min(x, width - 1))
        y = max(0, min(y, height - 1))
        
        # Get integer coordinates
        x0 = int(x)
        y0 = int(y)
        x1 = min(x0 + 1, width - 1)
        y1 = min(y0 + 1, height - 1)
        
        # Get fractional parts
        fx = x - x0
        fy = y - y0
        
        # Bilinear interpolation
        v00 = image[y0, x0] / 255.0
        v10 = image[y0, x1] / 255.0
        v01 = image[y1, x0] / 255.0
        v11 = image[y1, x1] / 255.0
        
        v0 = v00 * (1 - fx) + v10 * fx
        v1 = v01 * (1 - fx) + v11 * fx
        
        return v0 * (1 - fy) + v1 * fy
    
    def _apply_tone_curve(self, value: float) -> float:
        """
        Apply tone mapping curve to emphasize darker tones.
        This creates more dramatic scribbles in shadow areas.
        """
        # Simple gamma curve - adjust gamma for different effects
        gamma = 2.2
        return value ** gamma
    
    def _map_to_range(
        self, 
        value: float, 
        min_val: float, 
        max_val: float
    ) -> float:
        """Map value from [0,1] to [min_val, max_val]."""
        return value * (max_val - min_val) + min_val
    
    def smooth_scribbles(
        self, 
        scribble_points: List[Tuple[float, float]],
        smoothing: float = 0.5
    ) -> List[Tuple[float, float]]:
        """
        Apply smoothing to scribble points using splines.
        
        Args:
            scribble_points: Raw scribble points
            smoothing: Smoothing factor (0-1)
            
        Returns:
            Smoothed points
        """
        if len(scribble_points) < 4:
            return scribble_points
            
        # Convert to arrays
        points = np.array(scribble_points)
        
        # Segment points into continuous sections
        # (to avoid connecting distant points)
        segments = self._segment_scribbles(points)
        
        smoothed = []
        for segment in segments:
            if len(segment) < 4:
                smoothed.extend([(p[0], p[1]) for p in segment])
                continue
                
            try:
                # Fit spline to segment
                tck, u = splprep(
                    [segment[:, 0], segment[:, 1]],
                    s=smoothing * len(segment),
                    per=False
                )
                
                # Evaluate at higher resolution
                u_new = np.linspace(0, 1, len(segment) * 2)
                smooth_segment = splev(u_new, tck)
                
                smoothed.extend(zip(smooth_segment[0], smooth_segment[1]))
            except:
                # If spline fitting fails, use original points
                smoothed.extend([(p[0], p[1]) for p in segment])
        
        return smoothed
    
    def _segment_scribbles(
        self, 
        points: np.ndarray,
        max_gap: float = 50.0
    ) -> List[np.ndarray]:
        """
        Segment scribble points into continuous sections.
        Breaks segments when distance between consecutive points is too large.
        """
        if len(points) == 0:
            return []
            
        segments = []
        current_segment = [points[0]]
        
        for i in range(1, len(points)):
            dist = np.linalg.norm(points[i] - points[i-1])
            
            if dist > max_gap:
                # Start new segment
                if len(current_segment) > 1:
                    segments.append(np.array(current_segment))
                current_segment = [points[i]]
            else:
                current_segment.append(points[i])
        
        # Add final segment
        if len(current_segment) > 1:
            segments.append(np.array(current_segment))
            
        return segments