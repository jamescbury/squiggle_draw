"""Pipeline with progress callback support for real-time UI updates."""

from pathlib import Path
from typing import Union, List, Tuple, Dict, Any, Optional, Callable
import numpy as np
import threading
import time

from ..io.image_loader import ImageLoader
from ..processors.contrast_enhancer import ContrastEnhancer
from ..processors.edge_detector import EdgeDetector
from .scribble_algorithm import ScribbleLineAlgorithm
from ..generators.svg_generator import SVGGenerator
from .stippling import StipplingAlgorithm
from .tsp_solver import TSPSolver


class ProgressStipplingAlgorithm(StipplingAlgorithm):
    """Stippling algorithm with progress callback."""
    
    def __init__(self, progress_callback: Optional[Callable] = None):
        super().__init__()
        self.progress_callback = progress_callback
        
    def adaptive_stippling(
        self,
        image: np.ndarray,
        target_points: int = 1000,
        iterations: int = 50
    ) -> np.ndarray:
        """Generate adaptive stipple points with progress updates."""
        if self.progress_callback:
            self.progress_callback("Initializing stippling...", 0.05)
            
        # Start with much fewer points to prevent hanging
        target_points = min(target_points, 2000)  # Cap at 2000 points
        
        result = super().adaptive_stippling(image, target_points, iterations)
        
        if self.progress_callback:
            self.progress_callback(f"Generated {len(result)} stipple points", 0.4)
            
        return result


class ProgressTSPSolver(TSPSolver):
    """TSP solver with progress callback."""
    
    def __init__(self, progress_callback: Optional[Callable] = None):
        super().__init__()
        self.progress_callback = progress_callback
        
    def solve_2opt(
        self,
        points: np.ndarray,
        initial_path: Optional[List[int]] = None,
        max_iterations: int = 1000
    ) -> List[int]:
        """Solve TSP with 2-opt and progress updates."""
        n = len(points)
        
        if self.progress_callback:
            self.progress_callback(f"Finding initial path for {n} points...", 0.5)
            
        # For large point sets, use a much simpler approach
        if n > 1000:
            if self.progress_callback:
                self.progress_callback(f"Using fast mode for {n} points...", 0.7)
            # Just return nearest neighbor solution for very large sets
            return super().solve_nearest_neighbor(points)
            
        # Cap iterations based on point count
        if n > 500:
            max_iterations = min(max_iterations, 50)
        elif n > 200:
            max_iterations = min(max_iterations, 200)
        else:
            max_iterations = min(max_iterations, 500)
        
        # Get initial greedy path
        path = super().solve_nearest_neighbor(points) if initial_path is None else initial_path.copy()
        
        if self.progress_callback:
            self.progress_callback(f"Optimizing {n} points (max {max_iterations} iterations)...", 0.6)
        
        improved = True
        iteration = 0
        
        while improved and iteration < max_iterations:
            improved = False
            
            # Progress update - more frequent for fewer iterations
            update_freq = max(1, min(10, max_iterations // 20))
            if iteration % update_freq == 0 and self.progress_callback:
                progress = 0.6 + (0.3 * iteration / max_iterations)
                self.progress_callback(f"Optimizing path... iteration {iteration}/{max_iterations}", progress)
            
            # Standard 2-opt optimization
            for i in range(n - 1):
                for j in range(i + 2, n):
                    if j - i == n - 1:
                        continue
                        
                    # Calculate delta
                    # Calculate distances directly
                    def dist(p1, p2):
                        return np.linalg.norm(p1 - p2)
                    
                    delta = (
                        dist(points[path[i]], points[path[j]]) +
                        dist(points[path[i + 1]], points[path[(j + 1) % n]]) -
                        dist(points[path[i]], points[path[i + 1]]) -
                        dist(points[path[j]], points[path[(j + 1) % n]])
                    )
                    
                    if delta < -1e-9:
                        # Reverse segment
                        path[i + 1:j + 1] = path[i + 1:j + 1][::-1]
                        improved = True
                        
            iteration += 1
        
        if self.progress_callback:
            self.progress_callback("Path optimization complete", 0.9)
            
        return path


class ProgressScribbleAlgorithm(ScribbleLineAlgorithm):
    """Scribble algorithm with progress callback."""
    
    def __init__(self, progress_callback: Optional[Callable] = None):
        super().__init__()
        self.progress_callback = progress_callback
        self.stippler = ProgressStipplingAlgorithm(progress_callback)
        self.tsp_solver = ProgressTSPSolver(progress_callback)


class ProgressPipeline:
    """Pipeline with progress callback for real-time updates."""
    
    def __init__(self, progress_callback: Optional[Callable] = None):
        self.progress_callback = progress_callback
        self.loader = ImageLoader()
        self.enhancer = ContrastEnhancer()
        self.detector = EdgeDetector()
        self.algorithm = ProgressScribbleAlgorithm(progress_callback)
        self.generator = SVGGenerator()
        
    def _update_progress(self, message: str, progress: float):
        """Update progress if callback is available."""
        if self.progress_callback:
            self.progress_callback(message, progress)
    
    def process(
        self,
        input_path: Union[str, Path],
        output_path: Union[str, Path],
        algorithm_type: str = "stipple_tsp",
        contrast: float = 1.5,
        brightness: int = 0,
        use_edges: bool = True,
        edge_weight: float = 0.3,
        stipple_density: float = 1.0,
        optimization_level: str = "2-opt",
        smoothing: float = 0.1,
        max_dimension: int = 1024,
        **kwargs: Any
    ) -> Dict[str, Any]:
        """Process image with progress updates."""
        try:
            # Load and preprocess
            self._update_progress("Loading image...", 0.05)
            image = self.loader.load(input_path)
            original_dims = (image.shape[1], image.shape[0])
            image = self.loader.resize(image, max_dimension)
            resized_dims = (image.shape[1], image.shape[0])
            
            # Convert to grayscale
            self._update_progress("Converting to grayscale...", 0.1)
            gray = self.loader.load_as_grayscale(input_path)
            gray = self.loader.resize(gray, max_dimension)
            
            # Enhance contrast
            self._update_progress("Enhancing contrast...", 0.15)
            enhanced = self.enhancer.enhance(gray, contrast, brightness)
            
            # Apply CLAHE if requested
            if kwargs.get('use_clahe', False):
                self._update_progress("Applying adaptive histogram...", 0.2)
                enhanced = self.enhancer.adaptive_histogram_equalization(enhanced)
            
            # Edge detection if needed
            edges = None
            if use_edges and edge_weight > 0:
                self._update_progress("Detecting edges...", 0.25)
                edges = self.detector.canny(
                    enhanced,
                    low_threshold=kwargs.get('low_threshold', 30),
                    high_threshold=kwargs.get('high_threshold', 100),
                    blur_sigma=kwargs.get('blur_sigma', 1.0)
                )
            
            # Generate path based on algorithm type
            self._update_progress(f"Generating {algorithm_type} path...", 0.3)
            
            # Limit parameters for non-stipple algorithms to prevent hanging
            if algorithm_type == "tone_aware":
                # Reduce default complexity significantly
                self._update_progress("Generating tone-aware stipples...", 0.35)
                path = self.algorithm.generate_tone_aware_path(
                    enhanced,
                    min_spacing=kwargs.get('min_spacing', 20.0),  # Much higher spacing
                    max_spacing=kwargs.get('max_spacing', 60.0),  # Much higher spacing
                    curve_segments=kwargs.get('curve_segments', 3)  # Far fewer segments
                )
            elif algorithm_type == "scribble":
                # Reduce density for scribble
                path = self.algorithm.generate_scribble_style_path(
                    enhanced,
                    scribble_radius=kwargs.get('scribble_radius', 8.0),  # Increased from 5.0
                    scribble_density=min(stipple_density, 0.5)  # Cap density
                )
            else:  # Default stipple_tsp
                path = self.algorithm.generate_line_art(
                    enhanced,
                    edges=edges,
                    stipple_density=stipple_density,
                    edge_weight=edge_weight,
                    optimization_level=optimization_level,
                    smoothing=smoothing
                )
            
            if not path:
                raise ValueError("Failed to generate path")
            
            # Generate SVG
            self._update_progress("Generating SVG...", 0.95)
            self.generator.create_svg(
                path,
                resized_dims,
                str(output_path),
                fit_to_page=kwargs.get('fit_to_page', True),
                margin_mm=kwargs.get('margin_mm', 10)
            )
            
            self._update_progress("Complete!", 1.0)
            
            # Calculate statistics
            stats = {
                'original_dimensions': original_dims,
                'processed_dimensions': resized_dims,
                'algorithm': algorithm_type,
                'path_length': len(path),
                'estimated_time_seconds': self.generator.estimate_drawing_time(path),
                'stipple_density': stipple_density,
                'optimization_level': optimization_level
            }
            
            return stats
            
        except Exception as e:
            self._update_progress(f"Error: {str(e)}", -1)
            raise