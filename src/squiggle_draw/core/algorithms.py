from typing import List, Tuple, Optional, Dict, Any
import numpy as np
import cv2


class SingleLineAlgorithm:
    """Generate single continuous line from edge image."""
    
    def __init__(self) -> None:
        self.path: List[Tuple[int, int]] = []
    
    def edges_to_points(
        self,
        edge_image: np.ndarray,
        sample_rate: float = 1.0
    ) -> np.ndarray:
        """
        Convert edge pixels to point coordinates.
        
        Args:
            edge_image: Binary edge image
            sample_rate: Fraction of points to keep (0-1)
            
        Returns:
            Array of (x, y) coordinates
        """
        # Find all edge pixels
        y_coords, x_coords = np.where(edge_image > 0)
        points = np.column_stack((x_coords, y_coords))
        
        if sample_rate < 1.0 and len(points) > 100:
            # Random sampling
            n_samples = int(len(points) * sample_rate)
            indices = np.random.choice(len(points), n_samples, replace=False)
            points = points[indices]
        
        return points
    
    def nearest_neighbor_path(
        self,
        points: np.ndarray,
        start_point: Optional[Tuple[int, int]] = None
    ) -> List[Tuple[int, int]]:
        """
        Create path using nearest neighbor algorithm.
        
        Args:
            points: Array of (x, y) coordinates
            start_point: Optional starting point
            
        Returns:
            Ordered list of points forming a path
        """
        if len(points) == 0:
            return []
        
        # Convert to list for manipulation
        remaining = points.tolist()
        path = []
        
        # Start from first point or specified point
        if start_point is None:
            current = remaining.pop(0)
        else:
            # Find closest point to start
            distances = [
                (i, np.sqrt((p[0] - start_point[0])**2 + (p[1] - start_point[1])**2))
                for i, p in enumerate(remaining)
            ]
            idx, _ = min(distances, key=lambda x: x[1])
            current = remaining.pop(idx)
        
        path.append(tuple(current))
        
        # Build path by always going to nearest unvisited point
        while remaining:
            distances = [
                (i, np.sqrt((p[0] - current[0])**2 + (p[1] - current[1])**2))
                for i, p in enumerate(remaining)
            ]
            idx, _ = min(distances, key=lambda x: x[1])
            current = remaining.pop(idx)
            path.append(tuple(current))
        
        return path
    
    def tsp_optimization(
        self,
        points: np.ndarray,
        method: str = "greedy"
    ) -> List[Tuple[int, int]]:
        """
        Optimize path using TSP algorithms.
        
        Args:
            points: Array of (x, y) coordinates
            method: Optimization method ("greedy", "2-opt")
            
        Returns:
            Optimized path
        """
        if len(points) <= 2:
            return [tuple(p) for p in points]
        
        if method == "greedy":
            return self.nearest_neighbor_path(points)
        
        elif method == "2-opt":
            # Start with nearest neighbor path
            path = self.nearest_neighbor_path(points)
            
            # Apply 2-opt improvements
            improved = True
            while improved:
                improved = False
                for i in range(1, len(path) - 2):
                    for j in range(i + 1, len(path)):
                        if j - i == 1:
                            continue
                        
                        # Calculate distances
                        old_dist = (
                            self._distance(path[i-1], path[i]) +
                            self._distance(path[j-1], path[j % len(path)])
                        )
                        new_dist = (
                            self._distance(path[i-1], path[j-1]) +
                            self._distance(path[i], path[j % len(path)])
                        )
                        
                        if new_dist < old_dist:
                            # Reverse segment
                            path[i:j] = reversed(path[i:j])
                            improved = True
            
            return path
        
        return [tuple(p) for p in points]
    
    def _distance(self, p1: Tuple[int, int], p2: Tuple[int, int]) -> float:
        """Calculate Euclidean distance between two points."""
        return np.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)
    
    def connect_components(
        self,
        edge_image: np.ndarray,
        max_gap: int = 50
    ) -> List[List[Tuple[int, int]]]:
        """
        Find and connect separate components.
        
        Args:
            edge_image: Binary edge image
            max_gap: Maximum gap to bridge between components
            
        Returns:
            List of connected component paths
        """
        # Find connected components
        num_labels, labels = cv2.connectedComponents(edge_image.astype(np.uint8))
        
        components = []
        for label in range(1, num_labels):
            # Get points for this component
            mask = (labels == label).astype(np.uint8) * 255
            points = self.edges_to_points(mask)
            
            if len(points) > 5:  # Minimum size
                components.append(points)
        
        # Sort components by size (largest first)
        components.sort(key=len, reverse=True)
        
        # Convert each component to a path
        component_paths = []
        for comp_points in components:
            path = self.tsp_optimization(comp_points, method="greedy")
            component_paths.append(path)
        
        return component_paths
    
    def merge_paths(
        self,
        paths: List[List[Tuple[int, int]]],
        max_gap: int = 100
    ) -> List[Tuple[int, int]]:
        """
        Merge multiple paths into a single continuous path.
        
        Args:
            paths: List of paths to merge
            max_gap: Maximum gap to bridge
            
        Returns:
            Single merged path
        """
        if not paths:
            return []
        
        if len(paths) == 1:
            return paths[0]
        
        # Start with the longest path
        merged = list(paths[0])
        remaining = paths[1:]
        
        while remaining:
            # Find closest path endpoint to current path
            best_dist = float('inf')
            best_idx = -1
            best_reverse = False
            best_insert_pos = -1
            
            for idx, path in enumerate(remaining):
                if not path:
                    continue
                
                # Check all combinations of endpoints
                for i, merged_point in enumerate([merged[0], merged[-1]]):
                    for j, path_point in enumerate([path[0], path[-1]]):
                        dist = self._distance(merged_point, path_point)
                        
                        if dist < best_dist and dist <= max_gap:
                            best_dist = dist
                            best_idx = idx
                            best_reverse = (j == 0)  # Reverse if connecting to start
                            best_insert_pos = 0 if i == 0 else len(merged)
            
            if best_idx >= 0:
                # Merge the best path
                path_to_add = remaining.pop(best_idx)
                if best_reverse:
                    path_to_add = list(reversed(path_to_add))
                
                if best_insert_pos == 0:
                    merged = path_to_add + merged
                else:
                    merged = merged + path_to_add
            else:
                # No more paths can be connected
                break
        
        return merged
    
    def smooth_path(
        self,
        path: List[Tuple[int, int]],
        window_size: int = 5
    ) -> List[Tuple[int, int]]:
        """
        Smooth path using moving average.
        
        Args:
            path: Input path
            window_size: Smoothing window size
            
        Returns:
            Smoothed path
        """
        if len(path) < window_size:
            return path
        
        smoothed = []
        half_window = window_size // 2
        
        for i in range(len(path)):
            start = max(0, i - half_window)
            end = min(len(path), i + half_window + 1)
            
            window_points = path[start:end]
            avg_x = sum(p[0] for p in window_points) / len(window_points)
            avg_y = sum(p[1] for p in window_points) / len(window_points)
            
            smoothed.append((int(avg_x), int(avg_y)))
        
        return smoothed