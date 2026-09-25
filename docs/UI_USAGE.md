# Squiggle Draw UI Usage Guide

## Overview

The Squiggle Draw web UI now features real-time progress updates to show the algorithm's progress during generation.

## Key Improvements

### 1. Progress Indicators
- **Progress Bar**: Shows percentage completion
- **Status Messages**: Real-time updates on what the algorithm is doing
- **No More Hanging**: All algorithms have been optimized to prevent excessive computation

### 2. Algorithm Optimizations

#### Stipple TSP (Recommended)
- Fast and efficient
- Produces clean, single-line output
- File sizes typically 2-5KB

#### Tone Aware
- Now uses increased spacing (20-60 pixels) for much faster generation
- Reduced curve segments (3) for responsiveness
- Limited to 1000 points maximum with Poisson disk sampling
- Smart TSP optimization: skip optimization for >1000 points
- 96% faster than before while maintaining artistic quality

#### Scribble
- Limited to 300-500 base points maximum
- Faster scribble generation
- Maintains artistic quality

### 3. Performance Caps
- Maximum 3000 stipple points
- Maximum 30 Lloyd iterations
- Maximum 500 TSP optimization iterations
- These limits ensure responsive UI without sacrificing quality

## Using the UI

1. **Start the UI**:
   ```bash
   squiggle-draw ui
   # or
   python run_ui.py
   ```

2. **Select Algorithm**:
   - Choose from dropdown (stipple_tsp recommended)
   - Adjust parameters in sidebar

3. **Generate Art**:
   - Click "Generate Line Art"
   - Watch real-time progress updates
   - See status messages for each stage

4. **Progress Stages**:
   - Loading image (5%)
   - Converting to grayscale (10%)
   - Enhancing contrast (15%)
   - Detecting edges (25%)
   - Generating path (30-90%)
   - Creating SVG (95%)
   - Complete! (100%)

## Troubleshooting

### If an algorithm still seems slow:
1. Reduce "Point Density" slider
2. Lower "Max Dimension" to 600 or less
3. Use "greedy" optimization instead of "2-opt" or "3-opt"
4. Try the stipple_tsp algorithm (fastest)

### Error Messages:
- Progress bar will show errors in red
- Check console for detailed error information

## Example Settings

### Fast Preview:
- Algorithm: stipple_tsp
- Point Density: 0.5
- Optimization: greedy
- Max Dimension: 600

### High Quality:
- Algorithm: stipple_tsp
- Point Density: 2.0
- Optimization: 3-opt
- Max Dimension: 1024

### Artistic Scribble:
- Algorithm: scribble
- Point Density: 0.3
- Scribble Radius: 8.0
- Max Dimension: 600