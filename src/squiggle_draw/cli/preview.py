"""Preview edge detection results."""

import click
from pathlib import Path
import matplotlib.pyplot as plt
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend

from ..core.pipeline import SingleLinePipeline


@click.command()
@click.argument('input_path', type=click.Path(exists=True, path_type=Path))
@click.option(
    '-o', '--output',
    type=click.Path(path_type=Path),
    help='Save preview image to file (default: display only)'
)
@click.option(
    '--contrast',
    default=1.5,
    type=float,
    help='Contrast enhancement factor (default: 1.5)'
)
@click.option(
    '--brightness',
    default=0,
    type=int,
    help='Brightness adjustment -255 to 255 (default: 0)'
)
@click.option(
    '--edge-method',
    type=click.Choice(['canny', 'sobel', 'laplacian', 'multi_scale']),
    default='canny',
    help='Edge detection method (default: canny)'
)
@click.option(
    '--low-threshold',
    default=50,
    type=int,
    help='Lower threshold for Canny edge detection (default: 50)'
)
@click.option(
    '--high-threshold',
    default=150,
    type=int,
    help='Upper threshold for Canny edge detection (default: 150)'
)
@click.option(
    '--max-dimension',
    default=800,
    type=int,
    help='Maximum image dimension for preview (default: 800)'
)
@click.option(
    '--use-clahe',
    is_flag=True,
    help='Use CLAHE (Contrast Limited Adaptive Histogram Equalization)'
)
@click.option(
    '--gamma',
    default=1.0,
    type=float,
    help='Gamma correction value (< 1 darker, > 1 brighter, default: 1.0)'
)
def preview_command(
    input_path: Path,
    output: Path,
    contrast: float,
    brightness: int,
    edge_method: str,
    low_threshold: int,
    high_threshold: int,
    max_dimension: int,
    use_clahe: bool,
    gamma: float
):
    """
    Preview edge detection results before generating line art.
    
    INPUT_PATH: Path to input image (jpg, png, heic)
    
    Example:
        squiggle-draw preview photo.jpg --contrast 2.0 --edge-method canny
    """
    pipeline = SingleLinePipeline()
    
    click.echo(f"Generating preview for: {input_path}")
    
    try:
        # Get edge detection preview
        edges = pipeline.preview_edges(
            input_path,
            contrast=contrast,
            brightness=brightness,
            edge_method=edge_method,
            max_dimension=max_dimension,
            low_threshold=low_threshold,
            high_threshold=high_threshold,
            use_clahe=use_clahe,
            gamma=gamma
        )
        
        # Create figure
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 6))
        
        # Load original for comparison
        image = pipeline.loader.load(input_path)
        image = pipeline.loader.resize(image, max_dimension)
        
        # Show original
        ax1.imshow(image)
        ax1.set_title('Original Image')
        ax1.axis('off')
        
        # Show edges
        ax2.imshow(edges, cmap='gray')
        ax2.set_title(f'Edge Detection ({edge_method})')
        ax2.axis('off')
        
        plt.tight_layout()
        
        if output:
            # Save preview
            output.parent.mkdir(parents=True, exist_ok=True)
            plt.savefig(output, dpi=150, bbox_inches='tight')
            click.echo(f"Preview saved to: {output}")
        else:
            # Save to temp file and notify user
            temp_path = Path("preview_edges.png")
            plt.savefig(temp_path, dpi=150, bbox_inches='tight')
            click.echo(f"Preview saved to: {temp_path}")
        
        plt.close()
        
        # Show edge pixel count
        edge_count = (edges > 0).sum()
        click.echo(f"Edge pixels detected: {edge_count:,}")
        
    except Exception as e:
        click.echo(click.style(f"✗ Error: {e}", fg="red"), err=True)
        raise