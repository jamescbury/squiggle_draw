#!/usr/bin/env python3
"""Test the SVG viewer scaling."""

import sys
from pathlib import Path

# Add the src directory to Python path
sys.path.insert(0, str(Path(__file__).parent.parent / 'src'))

from squiggle_draw.ui.svg_viewer import create_svg_viewer

# Read a test SVG
test_svg = Path("output/progress_test/test_stipple_tsp.svg")
if test_svg.exists():
    with open(test_svg, 'r') as f:
        svg_content = f.read()
    
    # Create viewer HTML
    html = create_svg_viewer(svg_content)
    
    # Save to file for manual inspection
    output_path = Path("output/test_viewer.html")
    
    # Create a full HTML page
    full_html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>SVG Viewer Test</title>
        <meta charset="utf-8">
        <style>
            body {{
                margin: 0;
                padding: 20px;
                font-family: Arial, sans-serif;
                background: #f0f0f0;
            }}
            h1 {{
                text-align: center;
                color: #333;
            }}
            .container {{
                max-width: 1200px;
                margin: 0 auto;
            }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1>SVG Viewer Test</h1>
            {html}
            <p style="text-align: center; margin-top: 20px; color: #666;">
                Use mouse wheel to zoom, click and drag to pan, or use the control buttons.
            </p>
        </div>
    </body>
    </html>
    """
    
    with open(output_path, 'w') as f:
        f.write(full_html)
    
    print(f"✓ Test viewer created: {output_path}")
    print("  Open in browser to test scaling and interaction")
    
else:
    print("✗ No test SVG found. Run test_progress.py first.")