"""Pipeline using the true TheScribbler algorithm."""

from pathlib import Path
from typing import Union, List, Tuple, Dict, Any, Optional, Callable
import numpy as np

from ..io.image_loader import ImageLoader
from ..processors.contrast_enhancer import ContrastEnhancer
from .stippling import StipplingAlgorithm
from .tsp_solver import TSPSolver
from .true_scribbler import TrueScribbler
from ..generators.svg_generator import SVGGenerator
from .live_preview import LivePreviewManager


class ScribblerPipeline:
    """Pipeline implementing TheScribbler algorithm with stippling and TSP."""
    
    def __init__(self, progress_callback: Optional[Callable] = None,
                 preview_callback: Optional[Callable] = None):
        self.progress_callback = progress_callback
        self.preview_callback = preview_callback
        self.loader = ImageLoader()
        self.enhancer = ContrastEnhancer()
        self.stippler = StipplingAlgorithm()
        self.tsp_solver = TSPSolver()
        self.generator = SVGGenerator()
        
        # Set up live preview if callback provided
        if preview_callback:
            self.preview_manager = LivePreviewManager(preview_callback)
            # Create scribbler with preview support
            self.scribbler = TrueScribbler(
                progress_callback, 
                lambda points: self.preview_manager.add_points(points[-100:])  # Send last 100 points
            )
        else:
            self.preview_manager = None
            self.scribbler = TrueScribbler(progress_callback)
        
    def _update_progress(self, message: str, progress: float):
        """Update progress if callback is available."""
        if self.progress_callback:
            self.progress_callback(message, progress)
    
    def process(
        self,
        input_path: Union[str, Path],
        output_path: Union[str, Path],
        # Image processing
        contrast: float = 1.5,
        brightness: int = 0,
        gamma: float = 1.0,
        max_dimension: int = 800,
        # Stippling parameters
        num_stipples: int = 5000,
        # Scribbler parameters
        rmin: float = 2.0,
        rmax: float = 16.0,
        dtmin: float = 0.2,
        dtmax: float = 8.0,
        dtheta: float = 80.0,
        # Other options
        smooth_scribbles: bool = True,
        smoothing_factor: float = 0.5,
        **kwargs: Any
    ) -> Dict[str, Any]:
        """
        Process image using TheScribbler algorithm.
        
        Args:
            input_path: Input image path
            output_path: Output SVG path
            contrast: Contrast enhancement
            brightness: Brightness adjustment
            gamma: Gamma correction
            max_dimension: Maximum image dimension
            num_stipples: Number of stipple points
            rmin: Minimum circle radius (bright areas)
            rmax: Maximum circle radius (dark areas)
            dtmin: Minimum step distance (dark areas)
            dtmax: Maximum step distance (bright areas)
            dtheta: Rotation increment in degrees
            smooth_scribbles: Apply smoothing to output
            smoothing_factor: Smoothing strength
            
        Returns:
            Processing statistics
        """
        # Load and preprocess image
        self._update_progress("Loading image...", 0.05)
        image = self.loader.load(input_path)
        original_dims = (image.shape[1], image.shape[0])
        
        # Convert to grayscale
        self._update_progress("Converting to grayscale...", 0.1)
        gray = self.loader.load_as_grayscale(input_path)
        gray = self.loader.resize(gray, max_dimension)
        resized_dims = (gray.shape[1], gray.shape[0])
        
        # Enhance image
        self._update_progress("Enhancing image...", 0.15)
        enhanced = self.enhancer.enhance(gray, contrast, brightness)
        if gamma != 1.0:
            enhanced = self.enhancer.adjust_gamma(enhanced, gamma)
        
        # Set dimensions for preview manager
        if self.preview_manager:
            self.preview_manager.set_dimensions(resized_dims)
        
        # Generate stipple points
        self._update_progress("Generating stipple points...", 0.2)
        
        # Use adaptive stippling based on image tone
        stipple_points = self.stippler.adaptive_stippling(
            enhanced,
            target_points=num_stipples,
            iterations=30  # Lloyd's relaxation iterations
        )
        
        self._update_progress(f"Generated {len(stipple_points)} stipples", 0.3)
        
        # Send stipple points to preview
        if self.preview_manager:
            self.preview_manager.set_stipple_points(stipple_points)
        
        # Solve TSP to create path through stipples
        self._update_progress("Optimizing path (TSP)...", 0.35)
        
        # Use appropriate solver based on number of points
        if len(stipple_points) > 2000:
            # Use nearest neighbor only for large sets
            self._update_progress(f"Using fast TSP for {len(stipple_points)} points...", 0.37)
            path_indices = self.tsp_solver.solve_nearest_neighbor(stipple_points)
        elif len(stipple_points) > 1000:
            # Use basic 2-opt for medium sets
            self._update_progress(f"Optimizing {len(stipple_points)} points (limited)...", 0.37)
            path_indices = self.tsp_solver.solve_2opt(
                stipple_points,
                max_iterations=50
            )
        else:
            # Use better optimization for smaller sets
            self._update_progress(f"Optimizing {len(stipple_points)} points...", 0.37)
            path_indices = self.tsp_solver.solve_2opt(
                stipple_points,
                max_iterations=200
            )
        
        # Create ordered path
        tracing_path = [(stipple_points[i][0], stipple_points[i][1]) 
                        for i in path_indices]
        
        # Send TSP path to preview
        if self.preview_manager:
            self.preview_manager.set_tsp_path(tracing_path)
            # Update phase for scribbles
            self.preview_manager.current_phase = "scribbles"
        
        self._update_progress("Generating scribbles...", 0.4)
        
        # Generate scribbles using TheScribbler algorithm
        scribble_points = self.scribbler.generate_scribbles(
            enhanced,
            tracing_path,
            rmin=rmin,
            rmax=rmax,
            dtmin=dtmin,
            dtmax=dtmax,
            dtheta=dtheta
        )
        
        self._update_progress(f"Generated {len(scribble_points)} scribble points", 0.8)
        
        # Apply smoothing if requested
        if smooth_scribbles and len(scribble_points) > 0:
            self._update_progress("Smoothing scribbles...", 0.85)
            scribble_points = self.scribbler.smooth_scribbles(
                scribble_points,
                smoothing=smoothing_factor
            )
        
        # Send final preview
        if self.preview_manager:
            self.preview_manager.finalize(scribble_points)
        
        # Generate SVG
        self._update_progress("Generating SVG...", 0.9)
        self.generator.create_svg(
            scribble_points,
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
            'algorithm': 'true_scribbler',
            'num_stipples': len(stipple_points),
            'path_length': len(scribble_points),
            'estimated_time_seconds': self.generator.estimate_drawing_time(scribble_points),
            'parameters': {
                'rmin': rmin,
                'rmax': rmax,
                'dtmin': dtmin,
                'dtmax': dtmax,
                'dtheta': dtheta
            }
        }
        
        return stats