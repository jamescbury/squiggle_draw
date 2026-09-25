# Algorithm Comparison

## Overview

Squiggle Draw now includes 5 different algorithms for generating line art:

### 1. **True Scribbler** (NEW! - Based on TheScribbler)
- **Algorithm**: Stippling + TSP + Circular Scribbles
- **Best for**: Artistic, tone-aware scribble effects
- **Parameters**:
  - Number of Stipples: Base points for the path
  - Min/Max Radius: Circle size variation
  - Min/Max Step: Movement speed along path
  - Rotation Angle: Scribble density
- **Output**: Dense circular scribbles that follow image tone

### 2. **Stipple TSP** (Recommended for efficiency)
- **Algorithm**: Adaptive stippling + TSP optimization
- **Best for**: Clean, efficient single-line drawings
- **Typical file size**: 2-5 KB
- **Speed**: Very fast

### 3. **Tone Aware**
- **Algorithm**: Variable density based on image tone
- **Best for**: Capturing tonal variations
- **Note**: Limited to 1000 points for performance

### 4. **Scribble** (Original attempt)
- **Algorithm**: Basic scribbling with loops
- **Best for**: Decorative effects
- **Note**: Less sophisticated than True Scribbler

### 5. **Edge Trace** (Original)
- **Algorithm**: Edge detection + path tracing
- **Best for**: Simple outlines
- **Note**: Can produce chaotic results

## Parameter Guidelines

### True Scribbler Settings

#### For Fine Detail:
- Stipples: 1000-1500
- Min Radius: 1-2
- Max Radius: 6-10
- Min Step: 0.1-0.3
- Max Step: 2-5
- Rotation: 30-60°

#### For Bold Artistic Effect:
- Stipples: 300-800
- Min Radius: 3-5
- Max Radius: 15-25
- Min Step: 0.5-1.0
- Max Step: 8-15
- Rotation: 90-120°

#### For Dense Coverage:
- Stipples: 800-1200
- Min Radius: 2-3
- Max Radius: 8-12
- Min Step: 0.1-0.2
- Max Step: 1-3
- Rotation: 20-40°

## Performance Comparison

| Algorithm | Typical Points | File Size | Processing Time |
|-----------|---------------|-----------|-----------------|
| True Scribbler | 10k-50k | 150-500 KB | 20-60s |
| Stipple TSP | 100-500 | 2-5 KB | 1-3s |
| Tone Aware | 500-1000 | 8-15 KB | 1-5s |
| Scribble | 5k-10k | 100-200 KB | 5-10s |
| Edge Trace | 10k-20k | 150-300 KB | 3-5s |

## Visual Comparison

### Input Image
Original photograph (e.g., portrait, landscape)

### True Scribbler Output
- Dense circular scribbles
- Darker areas have larger, denser circles
- Artistic, hand-drawn appearance
- Follows important features via TSP path

### Stipple TSP Output
- Clean, minimal points
- Efficient single line
- Good for quick previews
- Maintains recognizable features

### Tone Aware Output
- Variable line density
- Captures gradients well
- More abstract representation

### Original Scribble Output
- Basic circular patterns
- Less sophisticated than True Scribbler
- Uniform scribble size

### Edge Trace Output
- Follows detected edges
- Can be chaotic
- Best for high-contrast images

## Recommendations

1. **For artistic prints**: Use True Scribbler with 500-1000 stipples
2. **For quick tests**: Use Stipple TSP
3. **For tonal images**: Try Tone Aware
4. **For portraits**: True Scribbler with fine detail settings
5. **For logos/text**: Edge Trace might work better

## Tips

- Start with fewer stipples and increase gradually
- Larger rotation angles = fewer points but less detail
- Adjust contrast/brightness before processing
- Use max dimension 600-800 for faster processing
- True Scribbler works best with good contrast