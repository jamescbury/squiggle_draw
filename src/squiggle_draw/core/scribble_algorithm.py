"""Improved single line art algorithm inspired by TheScribbler."""

from typing import List, Tuple, Optional, Dict, Any
import numpy as np
import cv2
from scipy.interpolate import splprep, splev
from scipy.spatial import cKDTree

from .stippling import StipplingAlgorithm
from .tsp_solver import TSPSolver


class ScribbleLineAlgorithm:
    """Generate single line art using stippling and TSP optimization."""
    
    def __init__(self) -> None:
        self.stippler = StipplingAlgorithm()
        self.tsp_solver = TSPSolver()
    
    def generate_line_art(
        self,
        image: np.ndarray,
        edges: Optional[np.ndarray] = None,
        stipple_density: float = 1.0,
        edge_weight: float = 0.5,
        optimization_level: str = "2-opt",
        smoothing: float = 0.1
    ) -> List[Tuple[float, float]]:
        """
        Generate single line art from image.
        
        Args:
            image: Grayscale image
            edges: Optional edge image
            stipple_density: Density multiplier (higher = more points)
            edge_weight: Weight for edge points vs tone points (0-1)
            optimization_level: TSP optimization level
            smoothing: Spline smoothing factor
            
        Returns:
            Smooth continuous path
        """
        height, width = image.shape
        
        # Calculate target points based on image size and density
        base_points = int(np.sqrt(width * height) * 0.1 * stipple_density)
        edge_points = int(base_points * edge_weight)
        tone_points = int(base_points * (1 - edge_weight))
        
        # Generate stipple points
        if edges is not None and edge_weight > 0:
            points = self.stippler.edge_aware_stippling(
                image, edges, edge_points, tone_points
            )
        else:
            points = self.stippler.adaptive_stippling(image, base_points)
        
        if len(points) < 3:
            # Fallback to simple grid
            points = self._generate_grid_points(width, height, 20)
        
        # Solve TSP
        if optimization_level == "3-opt":
            path_indices = self.tsp_solver.solve_3opt(points)
        elif optimization_level == "christofides":
            path_indices = self.tsp_solver.solve_christofides(points)
        else:  # Default 2-opt
            path_indices = self.tsp_solver.solve_2opt(points)
        
        # Create ordered path
        path = [points[i] for i in path_indices]
        
        # Smooth path using splines
        if smoothing > 0 and len(path) > 3:
            path = self._smooth_path_spline(path, smoothing)
        
        return path
    
    def generate_tone_aware_path(
        self,
        image: np.ndarray,
        min_spacing: float = 8.0,
        max_spacing: float = 25.0,
        curve_segments: int = 10
    ) -> List[Tuple[float, float]]:
        """
        Generate path with tone-aware spacing (inspired by scribbles).
        
        Args:
            image: Grayscale image
            min_spacing: Minimum point spacing (dark areas)
            max_spacing: Maximum point spacing (light areas)
            curve_segments: Segments per curve
            
        Returns:
            Continuous path with variable density
        """
        # Use Poisson disk sampling with variable radius
        points = self.stippler.weighted_poisson_disk_sampling(
            image, min_spacing, max_spacing
        )
        
        if len(points) < 3:
            return []
        
        # Optimize path
        path_indices = self.tsp_solver.solve_2opt(points)
        
        # Create tone-aware interpolated path
        path = []
        for i in range(len(path_indices)):
            idx1 = path_indices[i]
            idx2 = path_indices[(i + 1) % len(path_indices)]
            
            p1 = points[idx1]
            p2 = points[idx2]
            
            # Sample image intensity along line
            num_samples = 10
            x_samples = np.linspace(p1[0], p2[0], num_samples)
            y_samples = np.linspace(p1[1], p2[1], num_samples)
            
            avg_intensity = 0
            valid_samples = 0
            for x, y in zip(x_samples, y_samples):
                ix, iy = int(x), int(y)
                if 0 <= ix < image.shape[1] and 0 <= iy < image.shape[0]:
                    avg_intensity += image[iy, ix] / 255.0
                    valid_samples += 1
            
            if valid_samples > 0:
                avg_intensity /= valid_samples
            else:
                avg_intensity = 0.5
            
            # Determine number of curve points based on intensity
            # Darker areas get more points (denser curves)
            density = 1.0 - avg_intensity
            n_points = int(curve_segments * (0.5 + density))
            n_points = max(2, n_points)
            
            # Generate curve points
            if i == 0:
                path.append(p1)
            
            # Simple linear interpolation (could be enhanced with curves)
            for j in range(1, n_points):
                t = j / n_points
                x = p1[0] * (1 - t) + p2[0] * t
                y = p1[1] * (1 - t) + p2[1] * t
                path.append((x, y))
        
        return path
    
    def _generate_grid_points(
        self,
        width: int,
        height: int,
        spacing: int
    ) -> np.ndarray:
        """Generate regular grid points as fallback."""
        x_points = np.arange(spacing//2, width, spacing)
        y_points = np.arange(spacing//2, height, spacing)
        xx, yy = np.meshgrid(x_points, y_points)
        return np.column_stack((xx.ravel(), yy.ravel()))
    
    def _smooth_path_spline(
        self,
        path: List[Tuple[float, float]],
        smoothing: float = 0.1
    ) -> List[Tuple[float, float]]:
        """Smooth path using B-splines."""
        if len(path) < 4:
            return path
        
        # Convert to arrays
        path_array = np.array(path)
        
        # Close the path if endpoints are close
        dist_to_start = np.linalg.norm(path_array[-1] - path_array[0])
        close_path = dist_to_start < 50
        
        try:
            # Fit spline
            if close_path:
                # Closed path
                path_extended = np.vstack([path_array, path_array[0]])
                tck, u = splprep(
                    [path_extended[:, 0], path_extended[:, 1]],
                    s=smoothing * len(path_extended),
                    per=True
                )
            else:
                # Open path
                tck, u = splprep(
                    [path_array[:, 0], path_array[:, 1]],
                    s=smoothing * len(path_array)
                )
            
            # Evaluate spline at higher resolution
            u_new = np.linspace(0, 1, len(path) * 3)
            smooth_path = splev(u_new, tck)
            
            # Convert back to list of tuples
            return [(x, y) for x, y in zip(smooth_path[0], smooth_path[1])]
            
        except Exception:
            # If spline fitting fails, return original
            return path
    
    def generate_scribble_style_path(
        self,
        image: np.ndarray,
        scribble_radius: float = 5.0,
        scribble_density: float = 0.8
    ) -> List[Tuple[float, float]]:
        """
        Generate path with circular scribble patterns in dark areas.
        
        Args:
            image: Grayscale image
            scribble_radius: Base radius for scribbles
            scribble_density: Density of scribbles
            
        Returns:
            Path with scribble patterns
        """
        # Generate base points - limit for scribble algorithm
        target = min(int(300 * scribble_density), 500)  # Much fewer points for scribbles
        points = self.stippler.adaptive_stippling(
            image,
            target_points=target,
            iterations=20  # Fewer iterations for speed
        )
        
        # Optimize base path
        path_indices = self.tsp_solver.solve_2opt(points)
        
        # Generate scribbles along path
        final_path = []
        
        for i in range(len(path_indices)):
            idx = path_indices[i]
            x, y = points[idx]
            
            # Sample image intensity
            ix, iy = int(x), int(y)
            if 0 <= ix < image.shape[1] and 0 <= iy < image.shape[0]:
                intensity = image[iy, ix] / 255.0
            else:
                intensity = 1.0
            
            # Add scribble if dark enough
            if intensity < 0.7:
                # Scribble parameters based on intensity
                darkness = 1.0 - intensity
                radius = scribble_radius * darkness
                n_loops = int(3 * darkness)
                
                # Generate circular scribble
                for loop in range(n_loops):
                    for angle in np.linspace(0, 2 * np.pi, 20):
                        sx = x + radius * np.cos(angle) * (1 - loop * 0.3)
                        sy = y + radius * np.sin(angle) * (1 - loop * 0.3)
                        final_path.append((sx, sy))
            else:
                # Just pass through light areas
                final_path.append((x, y))
            
            # Connect to next point
            if i < len(path_indices) - 1:
                next_idx = path_indices[i + 1]
                next_x, next_y = points[next_idx]
                
                # Simple linear connection
                for t in np.linspace(0.1, 0.9, 5):
                    cx = x * (1 - t) + next_x * t
                    cy = y * (1 - t) + next_y * t
                    final_path.append((cx, cy))
        
        return final_path