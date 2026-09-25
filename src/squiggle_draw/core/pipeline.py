from pathlib import Path
from typing import Union, List, Tuple, Dict, Any, Optional
import numpy as np

from ..io.image_loader import ImageLoader
from ..processors.contrast_enhancer import ContrastEnhancer
from ..processors.edge_detector import EdgeDetector
from .algorithms import SingleLineAlgorithm
from ..generators.svg_generator import SVGGenerator


class SingleLinePipeline:
    """Pipeline for converting images to single line art."""
    
    def __init__(self) -> None:
        self.loader = ImageLoader()
        self.enhancer = ContrastEnhancer()
        self.detector = EdgeDetector()
        self.algorithm = SingleLineAlgorithm()
        self.generator = SVGGenerator()
    
    def process(
        self,
        input_path: Union[str, Path],
        output_path: Union[str, Path],
        contrast: float = 1.5,
        brightness: int = 0,
        edge_method: str = "canny",
        path_optimization: str = "greedy",
        max_dimension: int = 1024,
        sample_rate: float = 0.5,
        smooth_window: int = 3,
        **kwargs: Any
    ) -> Dict[str, Any]:
        """
        Process image to create single line art.
        
        Args:
            input_path: Input image path
            output_path: Output SVG path
            contrast: Contrast enhancement factor
            brightness: Brightness adjustment
            edge_method: Edge detection method
            path_optimization: Path optimization method
            max_dimension: Maximum image dimension
            sample_rate: Point sampling rate
            smooth_window: Path smoothing window
            **kwargs: Additional parameters
            
        Returns:
            Processing results and statistics
        """
        # Load and resize image
        image = self.loader.load(input_path)
        original_dims = (image.shape[1], image.shape[0])
        image = self.loader.resize(image, max_dimension)
        resized_dims = (image.shape[1], image.shape[0])
        
        # Convert to grayscale
        gray = self.loader.load_as_grayscale(input_path)
        gray = self.loader.resize(gray, max_dimension)
        
        # Enhance contrast
        enhanced = self.enhancer.enhance(gray, contrast, brightness)
        
        # Apply additional enhancements if specified
        if kwargs.get('use_clahe', False):
            enhanced = self.enhancer.adaptive_histogram_equalization(enhanced)
        
        if kwargs.get('gamma', 1.0) != 1.0:
            enhanced = self.enhancer.adjust_gamma(enhanced, kwargs['gamma'])
        
        # Detect edges
        if edge_method == "canny":
            edges = self.detector.canny(
                enhanced,
                low_threshold=kwargs.get('low_threshold', 50),
                high_threshold=kwargs.get('high_threshold', 150),
                blur_sigma=kwargs.get('blur_sigma', 1.0)
            )
        elif edge_method == "sobel":
            edges = self.detector.sobel(
                enhanced,
                ksize=kwargs.get('sobel_ksize', 3),
                threshold=kwargs.get('sobel_threshold', 50)
            )
        elif edge_method == "laplacian":
            edges = self.detector.laplacian(
                enhanced,
                ksize=kwargs.get('laplacian_ksize', 3),
                threshold=kwargs.get('laplacian_threshold', 30)
            )
        elif edge_method == "multi_scale":
            edges = self.detector.holistically_nested_edge_detection(enhanced)
        else:
            raise ValueError(f"Unknown edge method: {edge_method}")
        
        # Convert edges to points
        points = self.algorithm.edges_to_points(edges, sample_rate)
        
        if len(points) == 0:
            raise ValueError("No edges detected in image")
        
        # Find connected components
        components = self.algorithm.connect_components(edges, max_gap=kwargs.get('max_gap', 50))
        
        # Merge components into single path
        if components:
            path = self.algorithm.merge_paths(components, max_gap=kwargs.get('max_gap', 100))
        else:
            # Fallback to simple path
            path = self.algorithm.tsp_optimization(points, method=path_optimization)
        
        # Smooth path
        if smooth_window > 1:
            path = self.algorithm.smooth_path(path, smooth_window)
        
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
            'num_edge_pixels': np.sum(edges > 0),
            'num_points_sampled': len(points),
            'num_components': len(components) if components else 1,
            'path_length': len(path),
            'estimated_time_seconds': self.generator.estimate_drawing_time(path)
        }
        
        return stats
    
    def preview_edges(
        self,
        input_path: Union[str, Path],
        contrast: float = 1.5,
        brightness: int = 0,
        edge_method: str = "canny",
        max_dimension: int = 1024,
        **kwargs: Any
    ) -> np.ndarray:
        """
        Preview edge detection results.
        
        Args:
            input_path: Input image path
            contrast: Contrast enhancement
            brightness: Brightness adjustment
            edge_method: Edge detection method
            max_dimension: Maximum dimension
            **kwargs: Additional parameters
            
        Returns:
            Edge detection result
        """
        # Load and process image
        gray = self.loader.load_as_grayscale(input_path)
        gray = self.loader.resize(gray, max_dimension)
        
        # Enhance
        enhanced = self.enhancer.enhance(gray, contrast, brightness)
        
        # Detect edges
        if edge_method == "canny":
            edges = self.detector.canny(
                enhanced,
                low_threshold=kwargs.get('low_threshold', 50),
                high_threshold=kwargs.get('high_threshold', 150)
            )
        elif edge_method == "sobel":
            edges = self.detector.sobel(enhanced)
        elif edge_method == "laplacian":
            edges = self.detector.laplacian(enhanced)
        else:
            edges = self.detector.holistically_nested_edge_detection(enhanced)
        
        return edges