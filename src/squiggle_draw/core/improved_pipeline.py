"""Improved pipeline using stippling and TSP optimization."""

from pathlib import Path
from typing import Union, List, Tuple, Dict, Any, Optional
import numpy as np

from ..io.image_loader import ImageLoader
from ..processors.contrast_enhancer import ContrastEnhancer
from ..processors.edge_detector import EdgeDetector
from .scribble_algorithm import ScribbleLineAlgorithm
from ..generators.svg_generator import SVGGenerator


class ImprovedPipeline:
    """Pipeline using improved stippling-based algorithm."""
    
    def __init__(self) -> None:
        self.loader = ImageLoader()
        self.enhancer = ContrastEnhancer()
        self.detector = EdgeDetector()
        self.algorithm = ScribbleLineAlgorithm()
        self.generator = SVGGenerator()
    
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
        """
        Process image with improved algorithm.
        
        Args:
            input_path: Input image path
            output_path: Output SVG path
            algorithm_type: "stipple_tsp", "tone_aware", or "scribble"
            contrast: Contrast enhancement
            brightness: Brightness adjustment
            use_edges: Whether to use edge detection
            edge_weight: Weight for edges vs tone (0-1)
            stipple_density: Point density multiplier
            optimization_level: TSP optimization level
            smoothing: Path smoothing factor
            max_dimension: Maximum image dimension
            **kwargs: Additional parameters
            
        Returns:
            Processing statistics
        """
        # Load and preprocess image
        image = self.loader.load(input_path)
        original_dims = (image.shape[1], image.shape[0])
        image = self.loader.resize(image, max_dimension)
        resized_dims = (image.shape[1], image.shape[0])
        
        # Convert to grayscale
        gray = self.loader.load_as_grayscale(input_path)
        gray = self.loader.resize(gray, max_dimension)
        
        # Enhance contrast
        enhanced = self.enhancer.enhance(gray, contrast, brightness)
        
        # Apply CLAHE if requested
        if kwargs.get('use_clahe', False):
            enhanced = self.enhancer.adaptive_histogram_equalization(enhanced)
        
        # Edge detection if needed
        edges = None
        if use_edges and edge_weight > 0:
            edges = self.detector.canny(
                enhanced,
                low_threshold=kwargs.get('low_threshold', 30),
                high_threshold=kwargs.get('high_threshold', 100),
                blur_sigma=kwargs.get('blur_sigma', 1.0)
            )
        
        # Generate path based on algorithm type
        if algorithm_type == "tone_aware":
            path = self.algorithm.generate_tone_aware_path(
                enhanced,
                min_spacing=kwargs.get('min_spacing', 3.0),
                max_spacing=kwargs.get('max_spacing', 15.0),
                curve_segments=kwargs.get('curve_segments', 20)
            )
        elif algorithm_type == "scribble":
            path = self.algorithm.generate_scribble_style_path(
                enhanced,
                scribble_radius=kwargs.get('scribble_radius', 5.0),
                scribble_density=stipple_density
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
        self.generator.create_svg(
            path,
            resized_dims,
            str(output_path),
            fit_to_page=kwargs.get('fit_to_page', True),
            margin_mm=kwargs.get('margin_mm', 10)
        )
        
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
    
    def compare_algorithms(
        self,
        input_path: Union[str, Path],
        output_dir: Union[str, Path],
        **kwargs: Any
    ) -> Dict[str, Dict[str, Any]]:
        """
        Compare different algorithms on the same image.
        
        Args:
            input_path: Input image
            output_dir: Directory for outputs
            **kwargs: Common parameters
            
        Returns:
            Statistics for each algorithm
        """
        output_dir = Path(output_dir)
        output_dir.mkdir(exist_ok=True)
        
        algorithms = ["stipple_tsp", "tone_aware", "scribble"]
        results = {}
        
        for algo in algorithms:
            output_path = output_dir / f"{Path(input_path).stem}_{algo}.svg"
            
            try:
                stats = self.process(
                    input_path,
                    output_path,
                    algorithm_type=algo,
                    **kwargs
                )
                results[algo] = stats
                print(f"✓ {algo}: {stats['path_length']} points, "
                      f"{stats['estimated_time_seconds']:.1f}s")
            except Exception as e:
                print(f"✗ {algo} failed: {e}")
                results[algo] = {"error": str(e)}
        
        return results