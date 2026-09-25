# SVG Viewer Features

The Squiggle Draw UI now includes an enhanced SVG viewer with the following features:

## Automatic Scaling
- SVG files are automatically scaled to fit the viewport
- A4-sized outputs (210x297mm) are properly displayed
- Maintains aspect ratio to prevent distortion

## Interactive Controls
- **Mouse Wheel**: Zoom in/out
- **Click & Drag**: Pan around the image
- **Reset View**: Return to original scale and position
- **Zoom In/Out Buttons**: Precise zoom control

## Visual Enhancements
- White background with subtle shadow for the SVG
- Checkered pattern background to show transparency
- Smooth transitions when zooming
- Visual feedback (cursor changes) when dragging

## Zoom Limits
- Maximum zoom: 5x
- Minimum zoom: 0.5x
- Prevents excessive zooming that could cause performance issues

## Usage Tips
1. Use mouse wheel over the image for quick zoom
2. Hold click and drag to pan around when zoomed in
3. Click "Reset View" to return to default view
4. The viewer maintains the actual SVG quality at all zoom levels

## Technical Details
- Each viewer instance has a unique ID to prevent conflicts
- SVG preserveAspectRatio is set to "xMidYMid meet"
- Transform operations use CSS for smooth performance
- Event handlers are properly scoped to avoid conflicts