"""Single line mode CLI commands."""

import click
from pathlib import Path
import sys
from typing import Optional

from ..core.pipeline import SingleLinePipeline
from ..core.improved_pipeline import ImprovedPipeline


@click.command()
@click.argument('input_path', type=click.Path(exists=True, path_type=Path))
@click.option(
    '-o', '--output',
    type=click.Path(path_type=Path),
    help='Output SVG file path (default: input_name_line_art.svg)'
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
    '--path-optimization',
    type=click.Choice(['greedy', '2-opt']),
    default='greedy',
    help='Path optimization method (default: greedy)'
)
@click.option(
    '--max-dimension',
    default=1024,
    type=int,
    help='Maximum image dimension in pixels (default: 1024)'
)
@click.option(
    '--sample-rate',
    default=0.5,
    type=float,
    help='Point sampling rate 0-1 (default: 0.5)'
)
@click.option(
    '--smooth-window',
    default=3,
    type=int,
    help='Path smoothing window size (default: 3)'
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
@click.option(
    '--no-fit-to-page',
    is_flag=True,
    help='Do not scale output to fit page'
)
@click.option(
    '--margin',
    default=10,
    type=float,
    help='Page margin in mm (default: 10)'
)
@click.option(
    '--verbose', '-v',
    is_flag=True,
    help='Show detailed processing information'
)
@click.option(
    '--algorithm',
    type=click.Choice(['edge_trace', 'stipple_tsp', 'tone_aware', 'scribble']),
    default='stipple_tsp',
    help='Algorithm to use (default: stipple_tsp)'
)
@click.option(
    '--stipple-density',
    default=1.0,
    type=float,
    help='Stipple point density multiplier (default: 1.0)'
)
@click.option(
    '--edge-weight',
    default=0.3,
    type=float,
    help='Weight for edges vs tone (0-1, default: 0.3)'
)
@click.option(
    '--optimization-level',
    type=click.Choice(['greedy', '2-opt', '3-opt']),
    default='2-opt',
    help='TSP optimization level (default: 2-opt)'
)
def single_line_command(
    input_path: Path,
    output: Optional[Path],
    contrast: float,
    brightness: int,
    edge_method: str,
    low_threshold: int,
    high_threshold: int,
    path_optimization: str,
    max_dimension: int,
    sample_rate: float,
    smooth_window: int,
    use_clahe: bool,
    gamma: float,
    no_fit_to_page: bool,
    margin: float,
    verbose: bool,
    algorithm: str,
    stipple_density: float,
    edge_weight: float,
    optimization_level: str
):
    """
    Convert an image to single line art.
    
    INPUT_PATH: Path to input image (jpg, png, heic)
    
    Example:
        squiggle-draw single photo.jpg -o output.svg --contrast 2.0
    """
    # Set default output path if not provided
    if output is None:
        output = input_path.parent / f"{input_path.stem}_line_art.svg"
    
    # Ensure output directory exists
    output.parent.mkdir(parents=True, exist_ok=True)
    
    # Create appropriate pipeline
    if algorithm == "edge_trace":
        pipeline = SingleLinePipeline()
        use_improved = False
    else:
        pipeline = ImprovedPipeline()
        use_improved = True
    
    if verbose:
        click.echo(f"Processing: {input_path}")
        click.echo(f"Output: {output}")
        click.echo(f"Algorithm: {algorithm}")
        click.echo(f"Settings:")
        click.echo(f"  - Contrast: {contrast}")
        click.echo(f"  - Brightness: {brightness}")
        if use_improved:
            click.echo(f"  - Stipple density: {stipple_density}")
            click.echo(f"  - Edge weight: {edge_weight}")
            click.echo(f"  - Optimization: {optimization_level}")
        else:
            click.echo(f"  - Edge method: {edge_method}")
            click.echo(f"  - Sample rate: {sample_rate}")
        click.echo(f"  - Max dimension: {max_dimension}")
    
    try:
        # Process image
        if use_improved:
            stats = pipeline.process(
                input_path,
                output,
                algorithm_type=algorithm,
                contrast=contrast,
                brightness=brightness,
                use_edges=(edge_weight > 0),
                edge_weight=edge_weight,
                stipple_density=stipple_density,
                optimization_level=optimization_level,
                smoothing=smooth_window / 10.0,  # Convert to 0-1 range
                max_dimension=max_dimension,
                low_threshold=low_threshold,
                high_threshold=high_threshold,
                use_clahe=use_clahe,
                gamma=gamma,
                fit_to_page=not no_fit_to_page,
                margin_mm=margin
            )
        else:
            stats = pipeline.process(
                input_path,
                output,
                contrast=contrast,
                brightness=brightness,
                edge_method=edge_method,
                path_optimization=path_optimization,
                max_dimension=max_dimension,
                sample_rate=sample_rate,
                smooth_window=smooth_window,
                low_threshold=low_threshold,
                high_threshold=high_threshold,
                use_clahe=use_clahe,
                gamma=gamma,
                fit_to_page=not no_fit_to_page,
                margin_mm=margin
            )
        
        click.echo(click.style("✓ Processing complete!", fg="green"))
        click.echo(f"Output saved to: {output}")
        
        if verbose:
            click.echo("\nStatistics:")
            click.echo(f"  Original size: {stats['original_dimensions']}")
            click.echo(f"  Processed size: {stats['processed_dimensions']}")
            if 'num_edge_pixels' in stats:
                click.echo(f"  Edge pixels: {stats['num_edge_pixels']:,}")
            if 'num_points_sampled' in stats:
                click.echo(f"  Points sampled: {stats['num_points_sampled']:,}")
            if 'num_components' in stats:
                click.echo(f"  Components found: {stats['num_components']}")
            click.echo(f"  Path length: {stats['path_length']:,} points")
            click.echo(f"  Estimated drawing time: {stats['estimated_time_seconds']:.1f} seconds")
            if 'algorithm' in stats:
                click.echo(f"  Algorithm used: {stats['algorithm']}")
    
    except FileNotFoundError as e:
        click.echo(click.style(f"✗ Error: {e}", fg="red"), err=True)
        sys.exit(1)
    except ValueError as e:
        click.echo(click.style(f"✗ Error: {e}", fg="red"), err=True)
        sys.exit(1)
    except Exception as e:
        click.echo(click.style(f"✗ Unexpected error: {e}", fg="red"), err=True)
        if verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)