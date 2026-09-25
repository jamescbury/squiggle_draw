# Live Preview Feature

## Overview

The Squiggle Draw UI now supports live preview for the True Scribbler algorithm, allowing users to see the drawing being built in real-time during processing.

## How It Works

### 1. Enable Live Preview
- In the Advanced Options, check "Show Live Preview"
- This feature is currently only available for the True Scribbler algorithm

### 2. During Processing
- The preview area will show the drawing as it's being generated
- A point counter displays the current number of scribble points
- The preview updates approximately 20 times during the generation process
- You can see the circular scribbles being added along the TSP path

### 3. Benefits
- **Visual Feedback**: See the algorithm working in real-time
- **Early Stopping**: If the result doesn't look right, you can stop early
- **Understanding**: Better understand how the algorithm builds the image
- **Engagement**: More interactive and engaging user experience

## Technical Implementation

### Preview Pipeline
1. **True Scribbler** generates points in batches
2. **Preview Manager** collects points and generates intermediate SVGs
3. **Live Preview Widget** displays updates without interrupting processing
4. **Final Result** replaces the preview when complete

### Performance Considerations
- Preview updates are throttled to avoid overwhelming the UI
- Only the last 100 points are sent per update to keep SVG size manageable
- Preview SVGs are simplified (no smoothing) for faster rendering

## Example Workflow

1. Select "true_scribbler" algorithm
2. Adjust parameters:
   - Fewer stipples (300-500) for faster preview
   - Larger rotation angle (60-90°) for quicker coverage
3. Enable "Show Live Preview"
4. Click "Generate Line Art"
5. Watch as the drawing builds up:
   - First: TSP path through stipples
   - Then: Circular scribbles added progressively
   - Finally: Complete artwork

## Tips for Best Experience

### Fast Preview Settings
- Stipples: 300-500
- Rotation Angle: 60-90°
- Skip smoothing during preview

### Detailed Preview Settings
- Stipples: 800-1200
- Rotation Angle: 30-45°
- Smaller step sizes for denser coverage

## Limitations

- Currently only available for True Scribbler algorithm
- Preview may slow down processing slightly
- Very large drawings (>50k points) may have delayed updates
- Preview quality is slightly lower than final output

## Future Enhancements

Potential improvements:
- Add preview support for other algorithms
- Show stipple placement phase
- Display TSP path optimization
- Add pause/resume functionality
- Allow parameter adjustment during generation