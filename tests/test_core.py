import pytest
import numpy as np
from pathlib import Path

from squiggle_draw.io.image_loader import ImageLoader
from squiggle_draw.processors.contrast_enhancer import ContrastEnhancer
from squiggle_draw.processors.edge_detector import EdgeDetector
from squiggle_draw.core.algorithms import SingleLineAlgorithm
from squiggle_draw.generators.svg_generator import SVGGenerator


class TestImageLoader:
    def test_init(self):
        loader = ImageLoader()
        assert loader is not None
    
    def test_resize(self):
        loader = ImageLoader()
        # Create test image
        image = np.zeros((1000, 800, 3), dtype=np.uint8)
        
        # Test resize
        resized = loader.resize(image, max_dimension=500)
        assert resized.shape[0] == 500  # Height should be 500
        assert resized.shape[1] == 400  # Width should be 400


class TestContrastEnhancer:
    def test_enhance(self):
        enhancer = ContrastEnhancer()
        image = np.ones((100, 100), dtype=np.uint8) * 128
        
        enhanced = enhancer.enhance(image, contrast_factor=2.0)
        assert enhanced.shape == image.shape
        assert enhanced.dtype == np.uint8
    
    def test_gamma_correction(self):
        enhancer = ContrastEnhancer()
        image = np.ones((100, 100), dtype=np.uint8) * 128
        
        # Darker (gamma > 1)
        dark = enhancer.adjust_gamma(image, gamma=2.0)
        assert np.mean(dark) < np.mean(image)
        
        # Brighter (gamma < 1)
        bright = enhancer.adjust_gamma(image, gamma=0.5)
        assert np.mean(bright) > np.mean(image)


class TestEdgeDetector:
    def test_canny(self):
        detector = EdgeDetector()
        # Create test image with edge
        image = np.zeros((100, 100), dtype=np.uint8)
        image[:, 50:] = 255
        
        edges = detector.canny(image)
        assert edges.shape == image.shape
        assert np.sum(edges > 0) > 0  # Should detect some edges


class TestSingleLineAlgorithm:
    def test_edges_to_points(self):
        algo = SingleLineAlgorithm()
        # Create simple edge image
        edges = np.zeros((10, 10), dtype=np.uint8)
        edges[5, :] = 255  # Horizontal line
        
        points = algo.edges_to_points(edges)
        assert len(points) == 10  # Should have 10 points
        assert all(p[1] == 5 for p in points)  # All y-coords should be 5
    
    def test_nearest_neighbor_path(self):
        algo = SingleLineAlgorithm()
        points = np.array([[0, 0], [1, 0], [2, 0], [3, 0]])
        
        path = algo.nearest_neighbor_path(points)
        assert len(path) == 4
        assert isinstance(path[0], tuple)
    
    def test_distance(self):
        algo = SingleLineAlgorithm()
        d = algo._distance((0, 0), (3, 4))
        assert d == 5.0  # 3-4-5 triangle


class TestSVGGenerator:
    def test_init(self):
        gen = SVGGenerator()
        assert gen.width_mm == 210
        assert gen.height_mm == 297
    
    def test_create_path_data(self):
        gen = SVGGenerator()
        path = [(0, 0), (10, 0), (10, 10)]
        
        path_data = gen._create_path_data(path, scale=1.0, offset_x=0, offset_y=0)
        assert path_data.startswith("M 0.00,0.00")
        assert "L 10.00,0.00" in path_data
        assert "L 10.00,10.00" in path_data
    
    def test_estimate_time(self):
        gen = SVGGenerator()
        # Square path
        path = [(0, 0), (100, 0), (100, 100), (0, 100), (0, 0)]
        
        time = gen.estimate_drawing_time(path, speed_mm_per_sec=50.0)
        assert time > 0  # Should take some time