from pathlib import Path
from typing import Union, Optional
import numpy as np
from PIL import Image
import pillow_heif
import cv2


class ImageLoader:
    """Load images from various formats including HEIC."""
    
    SUPPORTED_FORMATS = {'.jpg', '.jpeg', '.png', '.heic', '.heif', '.bmp', '.tiff'}
    
    def __init__(self) -> None:
        # Register HEIF/HEIC opener with Pillow
        pillow_heif.register_heif_opener()
    
    def load(self, path: Union[str, Path]) -> np.ndarray:
        """
        Load an image from file and return as numpy array.
        
        Args:
            path: Path to the image file
            
        Returns:
            Image as numpy array in RGB format
            
        Raises:
            ValueError: If file format is not supported
            FileNotFoundError: If file doesn't exist
        """
        path = Path(path)
        
        if not path.exists():
            raise FileNotFoundError(f"Image file not found: {path}")
        
        if path.suffix.lower() not in self.SUPPORTED_FORMATS:
            raise ValueError(
                f"Unsupported format: {path.suffix}. "
                f"Supported formats: {', '.join(self.SUPPORTED_FORMATS)}"
            )
        
        # Load image using Pillow
        image = Image.open(path)
        
        # Convert to RGB if necessary
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        # Convert to numpy array
        return np.array(image)
    
    def load_as_grayscale(self, path: Union[str, Path]) -> np.ndarray:
        """
        Load an image and convert to grayscale.
        
        Args:
            path: Path to the image file
            
        Returns:
            Grayscale image as numpy array
        """
        image = self.load(path)
        # Convert RGB to grayscale using OpenCV
        return cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
    
    def resize(
        self, 
        image: np.ndarray, 
        max_dimension: int = 1024,
        maintain_aspect: bool = True
    ) -> np.ndarray:
        """
        Resize image to fit within max dimension.
        
        Args:
            image: Input image array
            max_dimension: Maximum width or height
            maintain_aspect: Whether to maintain aspect ratio
            
        Returns:
            Resized image
        """
        height, width = image.shape[:2]
        
        if not maintain_aspect:
            return cv2.resize(image, (max_dimension, max_dimension))
        
        # Calculate scaling factor
        scale = min(max_dimension / width, max_dimension / height)
        
        if scale >= 1.0:
            return image
        
        new_width = int(width * scale)
        new_height = int(height * scale)
        
        return cv2.resize(image, (new_width, new_height), interpolation=cv2.INTER_AREA)