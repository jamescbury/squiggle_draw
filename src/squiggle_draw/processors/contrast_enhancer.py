from typing import Tuple, Optional
import numpy as np
import cv2
from skimage import exposure


class ContrastEnhancer:
    """Enhance image contrast for better line art generation."""
    
    def enhance(
        self,
        image: np.ndarray,
        contrast_factor: float = 1.5,
        brightness_offset: int = 0
    ) -> np.ndarray:
        """
        Enhance image contrast and brightness.
        
        Args:
            image: Input image (grayscale or RGB)
            contrast_factor: Contrast multiplication factor (1.0 = no change)
            brightness_offset: Brightness adjustment (-255 to 255)
            
        Returns:
            Enhanced image
        """
        # Convert to float for calculations
        enhanced = image.astype(np.float32)
        
        # Apply contrast
        enhanced = (enhanced - 127.5) * contrast_factor + 127.5
        
        # Apply brightness
        enhanced += brightness_offset
        
        # Clip values and convert back to uint8
        return np.clip(enhanced, 0, 255).astype(np.uint8)
    
    def adaptive_histogram_equalization(
        self,
        image: np.ndarray,
        clip_limit: float = 2.0,
        tile_size: Tuple[int, int] = (8, 8)
    ) -> np.ndarray:
        """
        Apply Contrast Limited Adaptive Histogram Equalization (CLAHE).
        
        Args:
            image: Input grayscale image
            clip_limit: Threshold for contrast limiting
            tile_size: Size of grid for histogram equalization
            
        Returns:
            Enhanced image
        """
        if len(image.shape) == 3:
            image = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
        
        # Create CLAHE object
        clahe = cv2.createCLAHE(clipLimit=clip_limit, tileGridSize=tile_size)
        
        # Apply CLAHE
        return clahe.apply(image)
    
    def adjust_gamma(self, image: np.ndarray, gamma: float = 1.0) -> np.ndarray:
        """
        Apply gamma correction to adjust image brightness.
        
        Args:
            image: Input image
            gamma: Gamma value (< 1.0 = darker, > 1.0 = brighter)
            
        Returns:
            Gamma corrected image
        """
        # Build lookup table
        table = np.array([
            ((i / 255.0) ** gamma) * 255 
            for i in np.arange(0, 256)
        ]).astype("uint8")
        
        # Apply gamma correction using the lookup table
        return cv2.LUT(image, table)
    
    def create_high_contrast(
        self,
        image: np.ndarray,
        threshold: Optional[int] = None,
        adaptive: bool = True
    ) -> np.ndarray:
        """
        Create high contrast black and white image.
        
        Args:
            image: Input grayscale image
            threshold: Manual threshold value (None for automatic)
            adaptive: Use adaptive thresholding
            
        Returns:
            Binary image
        """
        if len(image.shape) == 3:
            image = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
        
        if adaptive:
            # Adaptive thresholding
            binary = cv2.adaptiveThreshold(
                image,
                255,
                cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                cv2.THRESH_BINARY,
                11,  # Block size
                2    # Constant subtracted from mean
            )
        else:
            # Simple thresholding
            if threshold is None:
                # Use Otsu's method to find optimal threshold
                _, binary = cv2.threshold(
                    image, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU
                )
            else:
                _, binary = cv2.threshold(image, threshold, 255, cv2.THRESH_BINARY)
        
        return binary
    
    def enhance_edges(
        self,
        image: np.ndarray,
        blur_size: int = 5,
        low_threshold: int = 50,
        high_threshold: int = 150
    ) -> np.ndarray:
        """
        Enhance edges using Gaussian blur and Canny edge detection.
        
        Args:
            image: Input image
            blur_size: Gaussian blur kernel size
            low_threshold: Lower threshold for Canny
            high_threshold: Upper threshold for Canny
            
        Returns:
            Edge-enhanced image
        """
        if len(image.shape) == 3:
            image = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
        
        # Apply Gaussian blur to reduce noise
        blurred = cv2.GaussianBlur(image, (blur_size, blur_size), 0)
        
        # Apply Canny edge detection
        edges = cv2.Canny(blurred, low_threshold, high_threshold)
        
        return edges