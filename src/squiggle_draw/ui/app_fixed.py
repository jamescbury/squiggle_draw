"""Streamlit UI for Squiggle Draw with fixed preview."""

import streamlit as st
from pathlib import Path
import tempfile
import shutil
from PIL import Image
import numpy as np
import time

import sys
from pathlib import Path

# Add the src directory to Python path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from squiggle_draw.core.improved_pipeline import ImprovedPipeline
from squiggle_draw.core.progress_pipeline import ProgressPipeline
from squiggle_draw.io.image_loader import ImageLoader
from squiggle_draw.ui.svg_viewer import create_svg_viewer
from squiggle_draw.ui.live_preview_widget import LivePreviewWidget, create_preview_callback


# Page config
st.set_page_config(
    page_title="Squiggle Draw",
    page_icon="✏️",
    layout="wide"
)

# Initialize session state
if 'processed' not in st.session_state:
    st.session_state.processed = False
if 'output_path' not in st.session_state:
    st.session_state.output_path = None
if 'preview_svg' not in st.session_state:
    st.session_state.preview_svg = None
if 'is_processing' not in st.session_state:
    st.session_state.is_processing = False


def main():
    """Main UI function."""
    st.title("✏️ Squiggle Draw")
    st.markdown("Generate single line art from photos for AxiDraw plotters")
    
    # Sidebar for parameters
    with st.sidebar:
        st.header("Parameters")
        
        # Algorithm selection
        algorithm = st.selectbox(
            "Algorithm",
            ["true_scribbler", "stipple_tsp", "tone_aware", "scribble", "edge_trace"],
            help="Choose the line art generation algorithm"
        )
        
        # Basic parameters
        st.subheader("Image Processing")
        contrast = st.slider("Contrast", 0.5, 3.0, 1.5, 0.1)
        brightness = st.slider("Brightness", -50, 50, 0)
        max_dimension = st.slider("Max Dimension", 256, 1024, 800, 64)
        
        # Algorithm-specific parameters
        if algorithm == "true_scribbler":
            st.subheader("Scribbler Parameters")
            num_stipples = st.slider(
                "Number of Stipples", 100, 2000, 500, 50,
                help="Number of base points for the TSP path"
            )
            col1, col2 = st.columns(2)
            with col1:
                rmin = st.slider(
                    "Min Radius", 0.5, 5.0, 2.0, 0.5,
                    help="Circle radius in bright areas"
                )
                rmax = st.slider(
                    "Max Radius", 5.0, 30.0, 12.0, 1.0,
                    help="Circle radius in dark areas"
                )
            with col2:
                dtmin = st.slider(
                    "Min Step", 0.1, 2.0, 0.5, 0.1,
                    help="Step size in dark areas (denser)"
                )
                dtmax = st.slider(
                    "Max Step", 2.0, 20.0, 10.0, 1.0,
                    help="Step size in bright areas (sparser)"
                )
            dtheta = st.slider(
                "Rotation Angle", 10.0, 180.0, 90.0, 10.0,
                help="Angle increment for circular scribbles"
            )
        elif algorithm != "edge_trace":
            st.subheader("Stippling Parameters")
            stipple_density = st.slider("Point Density", 0.3, 3.0, 1.0, 0.1)
            edge_weight = st.slider("Edge Weight", 0.0, 1.0, 0.3, 0.05)
            optimization = st.selectbox(
                "Optimization Level",
                ["greedy", "2-opt", "3-opt"],
                index=1
            )
        else:
            st.subheader("Edge Trace Parameters")
            edge_method = st.selectbox(
                "Edge Detection",
                ["canny", "sobel", "laplacian"],
                index=0
            )
            sample_rate = st.slider("Sample Rate", 0.1, 1.0, 0.3, 0.05)
        
        # Advanced options
        with st.expander("Advanced Options"):
            use_clahe = st.checkbox("Use CLAHE", value=False)
            gamma = st.slider("Gamma", 0.5, 2.0, 1.0, 0.1)
            smoothing = st.slider("Path Smoothing", 0, 10, 3)
            show_live_preview = st.checkbox(
                "Show Live Preview", 
                value=True,
                help="Display the drawing as it's being generated"
            )
    
    # Main content area
    col1, col2 = st.columns(2)
    
    uploaded_file = None
    
    with col1:
        st.subheader("Input Image")
        
        # File uploader
        uploaded_file = st.file_uploader(
            "Choose an image",
            type=['jpg', 'jpeg', 'png', 'heic'],
            help="Upload a photo to convert to line art"
        )
        
        # Or select from examples
        example_dir = Path("input")
        if example_dir.exists():
            example_files = list(example_dir.glob("*"))
            if example_files:
                st.write("Or select an example:")
                example_names = ["None"] + [f.name for f in example_files]
                selected_example = st.selectbox("Example images", example_names)
                
                if selected_example != "None":
                    uploaded_file = example_dir / selected_example
        
        # Display input image
        if uploaded_file is not None:
            if hasattr(uploaded_file, 'read'):
                # It's an uploaded file
                image = Image.open(uploaded_file)
                st.image(image, caption="Input Image", use_container_width=True)
            else:
                # It's a path
                image = Image.open(uploaded_file)
                st.image(image, caption="Input Image", use_container_width=True)
    
    with col2:
        st.subheader("Output")
        output_container = st.empty()
        
    # Process button
    if uploaded_file is not None and st.button("🎨 Generate Line Art", type="primary", use_container_width=True):
        # Clear any previous output
        output_container.empty()
        
        # Process the image
        if algorithm == "true_scribbler":
            process_image(
                uploaded_file,
                algorithm,
                contrast,
                brightness,
                max_dimension,
                None,  # stipple_density
                None,  # edge_weight
                None,  # optimization
                None,  # edge_method
                None,  # sample_rate
                use_clahe,
                gamma,
                smoothing,
                output_container,
                # True scribbler params
                num_stipples=num_stipples,
                rmin=rmin,
                rmax=rmax,
                dtmin=dtmin,
                dtmax=dtmax,
                dtheta=dtheta,
                show_live_preview=show_live_preview
            )
        else:
            process_image(
                uploaded_file,
                algorithm,
                contrast,
                brightness,
                max_dimension,
                stipple_density if algorithm != "edge_trace" else None,
                edge_weight if algorithm != "edge_trace" else None,
                optimization if algorithm != "edge_trace" else None,
                edge_method if algorithm == "edge_trace" else None,
                sample_rate if algorithm == "edge_trace" else None,
                use_clahe,
                gamma,
                smoothing,
                output_container,
                show_live_preview=show_live_preview
            )
    
    # Show default message if no processing
    if not st.session_state.processed:
        with output_container.container():
            st.info("Upload an image and click 'Generate Line Art' to see results")


def process_image(
    uploaded_file,
    algorithm,
    contrast,
    brightness,
    max_dimension,
    stipple_density,
    edge_weight,
    optimization,
    edge_method,
    sample_rate,
    use_clahe,
    gamma,
    smoothing,
    output_container,
    **kwargs
):
    """Process the uploaded image."""
    # Create progress placeholder
    progress_bar = st.progress(0)
    status_text = st.empty()
    
    def update_progress(message: str, progress: float):
        """Update progress in UI."""
        if progress >= 0:
            progress_bar.progress(min(progress, 1.0))
            status_text.text(message)
        else:
            status_text.error(message)
    
    # Create preview widget if needed  
    preview_widget = None
    show_preview = kwargs.get('show_live_preview', False) and algorithm == "true_scribbler"
    
    if show_preview:
        # Create preview in the output area
        with output_container.container():
            st.markdown("### Live Preview")
            preview_widget = LivePreviewWidget()
            preview_widget.create_container()
            preview_widget.show_placeholder()
    
    try:
        # Handle input file
        if hasattr(uploaded_file, 'read'):
            # It's an uploaded file from Streamlit
            # Get file extension
            file_ext = Path(uploaded_file.name).suffix.lower() if hasattr(uploaded_file, 'name') else '.png'
            
            # Save to temporary file with correct extension
            with tempfile.NamedTemporaryFile(suffix=file_ext, delete=False) as tmp_input:
                # Reset file position to beginning
                uploaded_file.seek(0)
                # Write file content
                tmp_input.write(uploaded_file.read())
                tmp_input.flush()
                input_path = tmp_input.name
            temp_file_created = True
        else:
            # It's a path to an existing file
            input_path = str(uploaded_file)
            temp_file_created = False
        
        # Output path
        output_path = Path("output") / f"streamlit_output_{int(time.time())}.svg"
        output_path.parent.mkdir(exist_ok=True)
        
        # Set processing state
        st.session_state.is_processing = True
        st.session_state.preview_svg = None
        
        # Create pipeline with progress callback
        pipeline = ProgressPipeline(progress_callback=update_progress)
        
        # Process based on algorithm
        if algorithm == "true_scribbler":
            # Use the true scribbler pipeline
            try:
                from squiggle_draw.core.scribbler_pipeline import ScribblerPipeline
                # Add preview callback if enabled
                preview_cb = create_preview_callback(preview_widget) if preview_widget else None
                pipeline = ScribblerPipeline(
                    progress_callback=update_progress,
                    preview_callback=preview_cb
                )
            except TypeError as e:
                # Fallback if preview_callback not recognized (cache issue)
                st.warning("Live preview temporarily unavailable. Please restart the app.")
                from squiggle_draw.core.scribbler_pipeline import ScribblerPipeline
                pipeline = ScribblerPipeline(progress_callback=update_progress)
            stats = pipeline.process(
                input_path,
                output_path,
                contrast=contrast,
                brightness=brightness,
                gamma=gamma,
                max_dimension=max_dimension,
                **kwargs  # Contains num_stipples, rmin, rmax, dtmin, dtmax, dtheta
            )
        elif algorithm == "edge_trace":
            # Use original pipeline for edge trace
            from squiggle_draw.core.pipeline import SingleLinePipeline
            pipeline = SingleLinePipeline()
            stats = pipeline.process(
                input_path,
                output_path,
                contrast=contrast,
                brightness=brightness,
                edge_method=edge_method,
                max_dimension=max_dimension,
                sample_rate=sample_rate,
                smooth_window=smoothing,
                use_clahe=use_clahe,
                gamma=gamma
            )
        else:
            # Use improved pipeline
            stats = pipeline.process(
                input_path,
                output_path,
                algorithm_type=algorithm,
                contrast=contrast,
                brightness=brightness,
                stipple_density=stipple_density,
                edge_weight=edge_weight,
                optimization_level=optimization,
                max_dimension=max_dimension,
                use_clahe=use_clahe,
                gamma=gamma,
                smoothing=smoothing / 10.0
            )
        
        # Update session state
        st.session_state.processed = True
        st.session_state.output_path = str(output_path)
        st.session_state.stats = stats
        
        # Clean up temp file if created
        if temp_file_created:
            try:
                Path(input_path).unlink()
            except:
                pass
        
        # Clear progress indicators
        progress_bar.empty()
        status_text.empty()
        
        # Clear processing state
        st.session_state.is_processing = False
        st.session_state.preview_svg = None
        
        # Clear preview if it exists
        if preview_widget:
            preview_widget.clear()
        
        # Display final result
        display_final_result(output_container)
        
    except Exception as e:
        progress_bar.empty()
        status_text.empty()
        st.error(f"Error processing image: {str(e)}")
        # Clean up temp file on error
        if 'temp_file_created' in locals() and temp_file_created:
            try:
                Path(input_path).unlink()
            except:
                pass


def display_final_result(output_container):
    """Display the final processed result."""
    with output_container.container():
        if st.session_state.processed and st.session_state.output_path:
            # Display SVG info
            output_path = Path(st.session_state.output_path)
            if output_path.exists():
                file_size = output_path.stat().st_size / 1024
                
                # Display stats
                if 'stats' in st.session_state:
                    stats = st.session_state.stats
                    col_stat1, col_stat2, col_stat3 = st.columns(3)
                    with col_stat1:
                        st.metric("Points", f"{stats.get('path_length', 'N/A'):,}")
                    with col_stat2:
                        st.metric("File Size", f"{file_size:.1f} KB")
                    with col_stat3:
                        st.metric("Est. Time", f"{stats.get('estimated_time_seconds', 0):.1f}s")
                
                # Display SVG preview with interactive viewer
                with open(output_path, 'r') as f:
                    svg_content = f.read()
                
                # Use the interactive SVG viewer
                html_content = create_svg_viewer(svg_content, height=550)
                st.components.v1.html(html_content, height=600)
                
                # Download button
                st.download_button(
                    label="📥 Download SVG",
                    data=svg_content,
                    file_name=f"squiggle_art_{int(time.time())}.svg",
                    mime="image/svg+xml",
                    use_container_width=True
                )


if __name__ == "__main__":
    main()