from typing import Tuple, Optional
import numpy as np
import cv2
from skimage import feature, filters


class EdgeDetector:
    """Detect edges in images for line art generation."""
    
    def canny(
        self,
        image: np.ndarray,
        low_threshold: int = 50,
        high_threshold: int = 150,
        blur_sigma: float = 1.0
    ) -> np.ndarray:
        """
        Apply Canny edge detection.
        
        Args:
            image: Input image
            low_threshold: Lower threshold for edge linking
            high_threshold: Upper threshold for edge detection
            blur_sigma: Gaussian blur sigma
            
        Returns:
            Binary edge image
        """
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
        else:
            gray = image
        
        # Apply Gaussian blur
        if blur_sigma > 0:
            gray = cv2.GaussianBlur(gray, (0, 0), blur_sigma)
        
        # Canny edge detection
        edges = cv2.Canny(gray, low_threshold, high_threshold)
        
        return edges
    
    def sobel(
        self,
        image: np.ndarray,
        ksize: int = 3,
        threshold: Optional[int] = None
    ) -> np.ndarray:
        """
        Apply Sobel edge detection.
        
        Args:
            image: Input image
            ksize: Sobel kernel size
            threshold: Optional threshold for binary output
            
        Returns:
            Edge magnitude image
        """
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
        else:
            gray = image
        
        # Calculate gradients
        grad_x = cv2.Sobel(gray, cv2.CV_64F, 1, 0, ksize=ksize)
        grad_y = cv2.Sobel(gray, cv2.CV_64F, 0, 1, ksize=ksize)
        
        # Calculate magnitude
        magnitude = np.sqrt(grad_x**2 + grad_y**2)
        magnitude = np.clip(magnitude, 0, 255).astype(np.uint8)
        
        if threshold is not None:
            _, magnitude = cv2.threshold(magnitude, threshold, 255, cv2.THRESH_BINARY)
        
        return magnitude
    
    def laplacian(
        self,
        image: np.ndarray,
        ksize: int = 3,
        threshold: Optional[int] = None
    ) -> np.ndarray:
        """
        Apply Laplacian edge detection.
        
        Args:
            image: Input image
            ksize: Laplacian kernel size
            threshold: Optional threshold for binary output
            
        Returns:
            Edge image
        """
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
        else:
            gray = image
        
        # Apply Laplacian
        laplacian = cv2.Laplacian(gray, cv2.CV_64F, ksize=ksize)
        laplacian = np.absolute(laplacian)
        laplacian = np.clip(laplacian, 0, 255).astype(np.uint8)
        
        if threshold is not None:
            _, laplacian = cv2.threshold(laplacian, threshold, 255, cv2.THRESH_BINARY)
        
        return laplacian
    
    def detect_contours(
        self,
        image: np.ndarray,
        mode: int = cv2.RETR_EXTERNAL,
        method: int = cv2.CHAIN_APPROX_SIMPLE,
        min_area: float = 10
    ) -> list:
        """
        Detect contours in binary image.
        
        Args:
            image: Binary input image
            mode: Contour retrieval mode
            method: Contour approximation method
            min_area: Minimum contour area to keep
            
        Returns:
            List of contours
        """
        # Ensure binary image
        if len(np.unique(image)) > 2:
            _, binary = cv2.threshold(image, 127, 255, cv2.THRESH_BINARY)
        else:
            binary = image
        
        # Find contours
        contours, _ = cv2.findContours(binary, mode, method)
        
        # Filter by area
        filtered_contours = []
        for contour in contours:
            area = cv2.contourArea(contour)
            if area >= min_area:
                filtered_contours.append(contour)
        
        return filtered_contours
    
    def holistically_nested_edge_detection(
        self,
        image: np.ndarray,
        blur_size: int = 5
    ) -> np.ndarray:
        """
        Simple HED-like edge detection using multiple scales.
        
        Args:
            image: Input image
            blur_size: Initial blur kernel size
            
        Returns:
            Multi-scale edge image
        """
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
        else:
            gray = image
        
        edges_multi_scale = np.zeros_like(gray, dtype=np.float32)
        
        # Detect edges at multiple scales
        for scale in [1, 2, 4]:
            # Resize image
            scaled = cv2.resize(
                gray, 
                (gray.shape[1] // scale, gray.shape[0] // scale),
                interpolation=cv2.INTER_AREA
            )
            
            # Apply edge detection
            edges = self.canny(scaled, 50, 150, blur_sigma=scale)
            
            # Resize back
            edges_resized = cv2.resize(
                edges,
                (gray.shape[1], gray.shape[0]),
                interpolation=cv2.INTER_LINEAR
            )
            
            # Accumulate
            edges_multi_scale += edges_resized.astype(np.float32) / (scale * 255)
        
        # Normalize
        edges_multi_scale = np.clip(edges_multi_scale * 255, 0, 255).astype(np.uint8)
        
        return edges_multi_scale