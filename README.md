# Squiggle Draw

Generate single line art from photos for AxiDraw plotters.

## Features

### Single Line Mode (Issue #1) ✅
- Convert photos (jpg, png, heic) to single continuous path SVG
- **NEW**: Stippling algorithm inspired by TheScribbler - 95% smaller files!
- Advanced TSP optimization for efficient drawing paths
- Multiple algorithms: stipple_tsp, tone_aware, scribble, edge_trace
- Export SVG files compatible with Inkscape and AxiDraw

### Multi-Line Mode (Issue #2) 🚧
- Separate images into multiple color layers
- Generate separate paths for each color
- Recommend pen colors for each path

## Quick Start

The new default algorithm (`stipple_tsp`) produces much better results than the original:

```bash
# Good quality, fast processing
squiggle-draw single photo.jpg

# Higher quality, more detail
squiggle-draw single photo.jpg --stipple-density 2.0 --optimization-level 3-opt

# Original algorithm (if needed)
squiggle-draw single photo.jpg --algorithm edge_trace
```

## Installation

```bash
# Clone the repository
git clone https://github.com/jamescbury/squiggle_draw.git
cd squiggle_draw

# Create virtual environment and install dependencies
python3 -m venv .venv
source .venv/bin/activate
poetry install
```

## Usage

### Web UI (Recommended)

Launch the interactive web interface:

```bash
# Start the UI
squiggle-draw ui

# Or use the run script
python run_ui.py
```

The UI provides:
- 📤 Drag-and-drop image upload
- 🎛️ Real-time parameter adjustment
- 👁️ Live preview of results
- 💾 One-click SVG download

### CLI (Command Line Interface)

#### Basic Usage

```bash
# Convert image to single line art
squiggle-draw single photo.jpg

# Specify output file
squiggle-draw single photo.jpg -o my_art.svg

# Preview edge detection before generating
squiggle-draw preview photo.jpg
```

#### Advanced Options

```bash
# Adjust density and contrast for more detail
squiggle-draw single photo.jpg --stipple-density 1.5 --contrast 2.0

# Emphasize edges in the output
squiggle-draw single photo.jpg --edge-weight 0.6 --stipple-density 2.0

# Use advanced optimization for best path quality
squiggle-draw single photo.jpg --optimization-level 3-opt

# Try the scribble style algorithm
squiggle-draw single photo.jpg --algorithm scribble

# Use the original edge-trace algorithm
squiggle-draw single photo.jpg --algorithm edge_trace --sample-rate 0.3

# Verbose output with statistics
squiggle-draw single photo.jpg -v
```

#### Algorithms

- **stipple_tsp** (default): Modern stippling + TSP optimization - produces clean, efficient paths
- **tone_aware**: Variable density based on image tone
- **scribble**: Decorative circular scribbles in dark areas  
- **edge_trace**: Original edge-based algorithm

#### Algorithm Parameters

For stipple-based algorithms:
- `--stipple-density`: Point density (0.5-3.0, default 1.0)
- `--edge-weight`: Balance edges vs tone (0-1, default 0.3)
- `--optimization-level`: TSP solver quality (greedy/2-opt/3-opt)

For edge trace algorithm:
- `--edge-method`: Edge detection method (canny/sobel/laplacian)
- `--sample-rate`: Point sampling rate (0-1)

#### Multi-line Mode (Coming Soon)

```bash
# Multi-line mode for color separation
squiggle-draw multi input.jpg -o output/ --colors 3
```

### GUI (Coming Soon)

A graphical interface for adjusting parameters and previewing results.

## Project Structure

```
squiggle_draw/
├── src/
│   └── squiggle_draw/
│       ├── core/          # Core algorithms
│       ├── processors/    # Image preprocessing
│       ├── generators/    # SVG path generation
│       ├── io/           # File I/O handling
│       ├── cli/          # Command line interface
│       └── gui/          # Graphical interface
├── tests/                # Unit and integration tests
├── examples/             # Example images and outputs
└── output/              # Default output directory
```

## Development

```bash
# Run tests
poetry run pytest

# Run linting
poetry run flake8
poetry run black .
```

## License

MIT License
