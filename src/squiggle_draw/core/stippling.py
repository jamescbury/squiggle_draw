"""Stippling-based point generation for improved line art."""

from typing import List, Tuple, Optional, Dict, Any
import numpy as np
from scipy.spatial import cKDTree
from scipy.spatial.distance import cdist
import cv2


class StipplingAlgorithm:
    """Generate stipple points based on image tone using Poisson disk sampling."""
    
    def __init__(self) -> None:
        self.points: List[Tuple[float, float]] = []
    
    def weighted_poisson_disk_sampling(
        self,
        image: np.ndarray,
        min_distance: float = 5.0,
        max_distance: float = 20.0,
        k_attempts: int = 30,
        initial_points: Optional[int] = None
    ) -> np.ndarray:
        """
        Generate points using weighted Poisson disk sampling.
        
        Args:
            image: Grayscale image (0-255)
            min_distance: Minimum distance between points
            max_distance: Maximum distance between points
            k_attempts: Number of attempts to place each point
            initial_points: Number of initial seed points
            
        Returns:
            Array of (x, y) coordinates
        """
        height, width = image.shape
        
        # Normalize image to 0-1
        normalized = image.astype(np.float32) / 255.0
        
        # Invert so dark areas have higher density
        density_map = 1.0 - normalized
        
        # Initialize
        points = []
        active_list = []
        
        # Create grid for fast neighbor checking
        cell_size = min_distance / np.sqrt(2)
        grid_width = int(np.ceil(width / cell_size))
        grid_height = int(np.ceil(height / cell_size))
        grid = np.full((grid_height, grid_width), -1, dtype=int)
        
        # Helper function to get grid coordinates
        def get_grid_coords(x: float, y: float) -> Tuple[int, int]:
            return int(y / cell_size), int(x / cell_size)
        
        # Helper function to get variable radius based on image intensity
        def get_radius(x: float, y: float) -> float:
            # Sample image intensity
            ix, iy = int(x), int(y)
            if 0 <= ix < width and 0 <= iy < height:
                intensity = density_map[iy, ix]
                # Map intensity to radius
                return min_distance + (max_distance - min_distance) * (1.0 - intensity)
            return max_distance
        
        # Add initial points
        if initial_points is None:
            initial_points = max(1, int(np.sqrt(width * height) / 20))
        
        # Cap initial points to prevent excessive generation
        initial_points = min(initial_points, 50)
        
        for _ in range(initial_points):
            x = np.random.uniform(0, width)
            y = np.random.uniform(0, height)
            
            # Check if point is valid
            radius = get_radius(x, y)
            if self._is_valid_point(x, y, radius, points, grid, cell_size, width, height):
                points.append((x, y))
                active_list.append(len(points) - 1)
                gy, gx = get_grid_coords(x, y)
                grid[gy, gx] = len(points) - 1
        
        # Main algorithm with point limit
        max_points = 1000  # Hard cap for tone_aware
        while active_list and len(points) < max_points:
            # Pick a random point from active list
            idx = np.random.randint(0, len(active_list))
            point_idx = active_list[idx]
            px, py = points[point_idx]
            
            # Try to place k new points around it
            placed = False
            for _ in range(k_attempts):
                # Generate random point in annulus
                radius = get_radius(px, py)
                angle = np.random.uniform(0, 2 * np.pi)
                r = np.random.uniform(radius, 2 * radius)
                
                x = px + r * np.cos(angle)
                y = py + r * np.sin(angle)
                
                # Check if valid
                if 0 <= x < width and 0 <= y < height:
                    new_radius = get_radius(x, y)
                    if self._is_valid_point(x, y, new_radius, points, grid, cell_size, width, height):
                        points.append((x, y))
                        active_list.append(len(points) - 1)
                        gy, gx = get_grid_coords(x, y)
                        grid[gy, gx] = len(points) - 1
                        placed = True
            
            # Remove from active list if no valid points found
            if not placed:
                active_list.pop(idx)
        
        return np.array(points)
    
    def _is_valid_point(
        self,
        x: float,
        y: float,
        radius: float,
        points: List[Tuple[float, float]],
        grid: np.ndarray,
        cell_size: float,
        width: int,
        height: int
    ) -> bool:
        """Check if a point is valid (not too close to existing points)."""
        if x < 0 or x >= width or y < 0 or y >= height:
            return False
        
        # Get grid coordinates
        gy, gx = int(y / cell_size), int(x / cell_size)
        
        # Check neighboring cells
        min_gy = max(0, gy - 2)
        max_gy = min(grid.shape[0], gy + 3)
        min_gx = max(0, gx - 2)
        max_gx = min(grid.shape[1], gx + 3)
        
        for cy in range(min_gy, max_gy):
            for cx in range(min_gx, max_gx):
                point_idx = grid[cy, cx]
                if point_idx != -1:
                    px, py = points[point_idx]
                    dist = np.sqrt((x - px)**2 + (y - py)**2)
                    if dist < radius:
                        return False
        
        return True
    
    def adaptive_stippling(
        self,
        image: np.ndarray,
        target_points: int = 1000,
        iterations: int = 50
    ) -> np.ndarray:
        """
        Generate stipple points using adaptive density based on image tone.
        
        Args:
            image: Grayscale image
            target_points: Target number of points
            iterations: Number of Lloyd relaxation iterations
            
        Returns:
            Array of (x, y) coordinates
        """
        # Cap target points to prevent excessive computation
        target_points = min(target_points, 3000)
        iterations = min(iterations, 30)
        
        height, width = image.shape
        
        # Initial random points weighted by image darkness
        density = (255 - image).astype(np.float32) / 255.0
        density = density ** 2  # Emphasize darker areas
        
        # Normalize density
        density = density / np.sum(density)
        
        # Generate initial points
        points = []
        flat_density = density.flatten()
        indices = np.random.choice(
            len(flat_density),
            size=target_points,
            p=flat_density
        )
        
        for idx in indices:
            y = idx // width
            x = idx % width
            # Add some jitter
            x += np.random.uniform(-0.5, 0.5)
            y += np.random.uniform(-0.5, 0.5)
            points.append((x, y))
        
        points = np.array(points)
        
        # Lloyd's relaxation with density weighting
        for _ in range(iterations):
            # Build KD-tree
            tree = cKDTree(points)
            
            # For each point, find its Voronoi cell and move to weighted centroid
            new_points = []
            for i, (px, py) in enumerate(points):
                # Find nearby pixels
                radius = 20  # Voronoi cell approximation radius
                x_min = max(0, int(px - radius))
                x_max = min(width, int(px + radius))
                y_min = max(0, int(py - radius))
                y_max = min(height, int(py + radius))
                
                # Create pixel grid
                xx, yy = np.meshgrid(
                    np.arange(x_min, x_max),
                    np.arange(y_min, y_max)
                )
                pixels = np.column_stack((xx.ravel(), yy.ravel()))
                
                # Find which pixels belong to this point's Voronoi cell
                if len(pixels) > 0:
                    distances, indices = tree.query(pixels)
                    mask = indices == i
                    
                    if np.any(mask):
                        cell_pixels = pixels[mask]
                        # Weight by image density
                        weights = []
                        for x, y in cell_pixels:
                            if 0 <= x < width and 0 <= y < height:
                                weights.append(density[y, x])
                            else:
                                weights.append(0)
                        
                        weights = np.array(weights)
                        if np.sum(weights) > 0:
                            weights = weights / np.sum(weights)
                            # Weighted centroid
                            new_x = np.sum(cell_pixels[:, 0] * weights)
                            new_y = np.sum(cell_pixels[:, 1] * weights)
                            new_points.append((new_x, new_y))
                        else:
                            new_points.append((px, py))
                    else:
                        new_points.append((px, py))
                else:
                    new_points.append((px, py))
            
            points = np.array(new_points)
        
        return points
    
    def edge_aware_stippling(
        self,
        image: np.ndarray,
        edges: np.ndarray,
        edge_points: int = 500,
        tone_points: int = 500
    ) -> np.ndarray:
        """
        Generate stipples with emphasis on edges.
        
        Args:
            image: Grayscale image
            edges: Binary edge image
            edge_points: Number of points along edges
            tone_points: Number of points for tone
            
        Returns:
            Combined array of points
        """
        # Sample points along edges
        edge_coords = np.column_stack(np.where(edges > 0))
        if len(edge_coords) > edge_points:
            indices = np.random.choice(len(edge_coords), edge_points, replace=False)
            edge_stipples = edge_coords[indices]
            # Swap x and y
            edge_stipples = edge_stipples[:, [1, 0]]
        else:
            edge_stipples = edge_coords[:, [1, 0]]
        
        # Generate tone-based stipples avoiding edges
        tone_stipples = self.adaptive_stippling(image, tone_points, iterations=20)
        
        # Combine
        if len(edge_stipples) > 0 and len(tone_stipples) > 0:
            return np.vstack([edge_stipples, tone_stipples])
        elif len(edge_stipples) > 0:
            return edge_stipples
        else:
            return tone_stipples