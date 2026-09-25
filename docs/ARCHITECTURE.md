# Architecture Overview

## Module Structure

### `core/`
Core algorithms for line art generation:
- `algorithms.py` - Main line tracing algorithms
- `path_optimizer.py` - Path optimization for continuous lines
- `color_analyzer.py` - Color separation logic

### `processors/`
Image preprocessing and manipulation:
- `image_loader.py` - Load jpg, png, heic files
- `contrast_enhancer.py` - Adjust contrast and shadows
- `edge_detector.py` - Edge detection algorithms
- `color_separator.py` - Separate images by color

### `generators/`
SVG generation and path creation:
- `svg_generator.py` - Create SVG files
- `path_generator.py` - Generate continuous paths
- `multi_path_generator.py` - Handle multi-color paths

### `io/`
Input/output handling:
- `file_handler.py` - File I/O operations
- `svg_writer.py` - Write SVG files with AxiDraw compatibility

### `cli/`
Command line interface:
- `main.py` - Entry point for CLI
- `single_line.py` - Single line mode commands
- `multi_line.py` - Multi-line mode commands

### `gui/`
Graphical user interface (future):
- `app.py` - Main GUI application
- `widgets/` - Custom UI widgets

## Data Flow

1. **Input**: User provides image file (jpg/png/heic)
2. **Loading**: `image_loader` reads and converts to standard format
3. **Preprocessing**: 
   - `contrast_enhancer` adjusts image contrast
   - `edge_detector` finds edges
   - `color_separator` (for multi-line mode)
4. **Generation**:
   - `path_generator` creates continuous path
   - `path_optimizer` optimizes for drawing
5. **Output**: `svg_writer` creates AxiDraw-compatible SVG

## Key Design Decisions

1. **Modular Architecture**: Each module has a single responsibility
2. **Pipeline Pattern**: Image processing follows a clear pipeline
3. **Strategy Pattern**: Different algorithms can be swapped
4. **Factory Pattern**: SVG generators for different modes