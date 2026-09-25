"""TSP solver for optimizing drawing paths."""

from typing import List, Tuple, Optional
import numpy as np
from scipy.spatial.distance import cdist


class TSPSolver:
    """Solve Traveling Salesman Problem to create optimal drawing paths."""
    
    def solve_nearest_neighbor(
        self,
        points: np.ndarray,
        start_idx: int = 0
    ) -> List[int]:
        """
        Simple nearest neighbor heuristic.
        
        Args:
            points: Array of (x, y) coordinates
            start_idx: Starting point index
            
        Returns:
            Ordered list of point indices
        """
        n = len(points)
        if n <= 1:
            return list(range(n))
        
        unvisited = set(range(n))
        path = [start_idx]
        unvisited.remove(start_idx)
        current = start_idx
        
        while unvisited:
            # Find nearest unvisited point
            min_dist = float('inf')
            nearest = None
            
            for next_idx in unvisited:
                dist = np.linalg.norm(points[current] - points[next_idx])
                if dist < min_dist:
                    min_dist = dist
                    nearest = next_idx
            
            path.append(nearest)
            unvisited.remove(nearest)
            current = nearest
        
        return path
    
    def solve_2opt(
        self,
        points: np.ndarray,
        initial_path: Optional[List[int]] = None,
        max_iterations: int = 1000
    ) -> List[int]:
        """
        2-opt optimization for TSP.
        
        Args:
            points: Array of (x, y) coordinates
            initial_path: Initial path (if None, uses nearest neighbor)
            max_iterations: Maximum optimization iterations
            
        Returns:
            Optimized path indices
        """
        n = len(points)
        if n <= 3:
            return list(range(n))
        
        # Start with initial path
        if initial_path is None:
            path = self.solve_nearest_neighbor(points)
        else:
            path = list(initial_path)
        
        # Precompute distance matrix for efficiency
        dist_matrix = cdist(points, points)
        
        improved = True
        iteration = 0
        
        while improved and iteration < max_iterations:
            improved = False
            iteration += 1
            
            for i in range(1, n - 2):
                for j in range(i + 1, n):
                    if j - i == 1:
                        continue
                    
                    # Calculate current distance
                    current_dist = (
                        dist_matrix[path[i-1], path[i]] +
                        dist_matrix[path[j-1], path[j % n]]
                    )
                    
                    # Calculate new distance if we reverse segment
                    new_dist = (
                        dist_matrix[path[i-1], path[j-1]] +
                        dist_matrix[path[i], path[j % n]]
                    )
                    
                    # If improvement, reverse segment
                    if new_dist < current_dist:
                        path[i:j] = reversed(path[i:j])
                        improved = True
                        break
                
                if improved:
                    break
        
        return path
    
    def solve_3opt(
        self,
        points: np.ndarray,
        initial_path: Optional[List[int]] = None,
        max_iterations: int = 100
    ) -> List[int]:
        """
        3-opt optimization for better quality paths.
        
        Args:
            points: Array of (x, y) coordinates
            initial_path: Initial path
            max_iterations: Maximum iterations
            
        Returns:
            Optimized path indices
        """
        n = len(points)
        if n <= 4:
            return list(range(n))
        
        # Start with 2-opt solution
        path = self.solve_2opt(points, initial_path, max_iterations // 2)
        
        # Precompute distances
        dist_matrix = cdist(points, points)
        
        def path_distance(p: List[int]) -> float:
            return sum(dist_matrix[p[i], p[(i+1) % n]] for i in range(n))
        
        improved = True
        iteration = 0
        
        while improved and iteration < max_iterations:
            improved = False
            iteration += 1
            
            for i in range(n - 2):
                for j in range(i + 1, n - 1):
                    for k in range(j + 1, n):
                        # Current segments
                        current = path_distance(path)
                        
                        # Try all 3-opt moves
                        # Type 1: Reverse first segment
                        new_path = path[:]
                        new_path[i:j] = reversed(path[i:j])
                        if path_distance(new_path) < current:
                            path = new_path
                            improved = True
                            break
                        
                        # Type 2: Reverse second segment
                        new_path = path[:]
                        new_path[j:k] = reversed(path[j:k])
                        if path_distance(new_path) < current:
                            path = new_path
                            improved = True
                            break
                        
                        # Type 3: Reverse both segments
                        new_path = path[:]
                        new_path[i:j] = reversed(path[i:j])
                        new_path[j:k] = reversed(path[j:k])
                        if path_distance(new_path) < current:
                            path = new_path
                            improved = True
                            break
                    
                    if improved:
                        break
                if improved:
                    break
        
        return path
    
    def solve_christofides(
        self,
        points: np.ndarray
    ) -> List[int]:
        """
        Simplified Christofides algorithm approximation.
        
        Args:
            points: Array of (x, y) coordinates
            
        Returns:
            Path indices
        """
        n = len(points)
        if n <= 3:
            return list(range(n))
        
        # For now, use 3-opt as approximation
        # Full Christofides would require MST and perfect matching
        return self.solve_3opt(points)
    
    def connect_components(
        self,
        components: List[np.ndarray],
        component_paths: List[List[int]]
    ) -> Tuple[List[int], List[np.ndarray]]:
        """
        Connect multiple components into single path.
        
        Args:
            components: List of point arrays for each component
            component_paths: TSP solution for each component
            
        Returns:
            Global path indices and merged points array
        """
        if not components:
            return [], np.array([])
        
        if len(components) == 1:
            return component_paths[0], components[0]
        
        # Merge all points
        merged_points = np.vstack(components)
        
        # Calculate component representatives (centroids)
        centroids = [np.mean(comp, axis=0) for comp in components]
        centroids = np.array(centroids)
        
        # Solve TSP on centroids to determine component order
        component_order = self.solve_2opt(centroids)
        
        # Build global path
        global_path = []
        offset = 0
        
        for comp_idx in component_order:
            # Add this component's path with offset
            local_path = component_paths[comp_idx]
            global_path.extend([idx + offset for idx in local_path])
            offset += len(components[comp_idx])
        
        return global_path, merged_points