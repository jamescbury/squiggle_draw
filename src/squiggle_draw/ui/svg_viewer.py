"""SVG viewer component with zoom and pan capabilities."""

import re
from typing import Optional


def create_svg_viewer(svg_content: str, height: int = 600) -> str:
    """
    Create an interactive SVG viewer with proper scaling.
    
    Args:
        svg_content: The SVG content to display
        height: Height of the viewer in pixels
        
    Returns:
        HTML content for the viewer
    """
    # Generate a unique ID for this viewer instance
    import random
    viewer_id = f"svg-viewer-{random.randint(1000, 9999)}"
    
    # Modify SVG to ensure it scales properly
    svg_scaled = re.sub(
        r'<svg([^>]*)>',
        rf'<svg\1 id="{viewer_id}-svg" preserveAspectRatio="xMidYMid meet">',
        svg_content
    )
    
    html_content = f"""
    <div style="background: #f8f9fa; border: 1px solid #dee2e6; border-radius: 8px; padding: 0; height: {height}px; position: relative;">
        <!-- Controls -->
        <div style="position: absolute; top: 10px; right: 10px; z-index: 100; background: white; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); padding: 5px;">
            <button onclick="resetZoom_{viewer_id}()" style="background: #6c757d; color: white; border: none; padding: 5px 10px; border-radius: 3px; cursor: pointer; margin-right: 5px;">Reset View</button>
            <button onclick="zoomIn_{viewer_id}()" style="background: #28a745; color: white; border: none; padding: 5px 10px; border-radius: 3px; cursor: pointer; margin-right: 5px;">Zoom In</button>
            <button onclick="zoomOut_{viewer_id}()" style="background: #dc3545; color: white; border: none; padding: 5px 10px; border-radius: 3px; cursor: pointer;">Zoom Out</button>
        </div>
        
        <!-- SVG Container -->
        <div id="{viewer_id}" style="width: 100%; height: 100%; overflow: hidden; cursor: grab; display: flex; align-items: center; justify-content: center; background: repeating-linear-gradient(45deg, #f5f5f5, #f5f5f5 10px, #ffffff 10px, #ffffff 20px);">
            <div style="width: 90%; height: 90%; display: flex; align-items: center; justify-content: center;">
                {svg_scaled}
            </div>
        </div>
        
        <style>
            #{viewer_id} svg {{
                max-width: 100%;
                max-height: 100%;
                width: auto !important;
                height: auto !important;
                background: white;
                box-shadow: 0 4px 12px rgba(0,0,0,0.1);
                transition: transform 0.2s ease;
            }}
            #{viewer_id}.grabbing {{
                cursor: grabbing;
            }}
        </style>
        
        <script>
            (function() {{
                const container = document.getElementById('{viewer_id}');
                const svg = document.getElementById('{viewer_id}-svg');
                let scale = 1;
                let translateX = 0;
                let translateY = 0;
                let isDragging = false;
                let startX, startY;
                
                function updateTransform() {{
                    svg.style.transform = `translate(${{translateX}}px, ${{translateY}}px) scale(${{scale}})`;
                }}
                
                window.resetZoom_{viewer_id} = function() {{
                    scale = 1;
                    translateX = 0;
                    translateY = 0;
                    updateTransform();
                }};
                
                window.zoomIn_{viewer_id} = function() {{
                    scale = Math.min(scale * 1.2, 5);
                    updateTransform();
                }};
                
                window.zoomOut_{viewer_id} = function() {{
                    scale = Math.max(scale / 1.2, 0.5);
                    updateTransform();
                }};
                
                // Mouse wheel zoom
                container.addEventListener('wheel', function(e) {{
                    e.preventDefault();
                    if (e.deltaY < 0) {{
                        window.zoomIn_{viewer_id}();
                    }} else {{
                        window.zoomOut_{viewer_id}();
                    }}
                }});
                
                // Pan functionality
                container.addEventListener('mousedown', function(e) {{
                    isDragging = true;
                    startX = e.clientX - translateX;
                    startY = e.clientY - translateY;
                    container.classList.add('grabbing');
                }});
                
                document.addEventListener('mousemove', function(e) {{
                    if (!isDragging) return;
                    translateX = e.clientX - startX;
                    translateY = e.clientY - startY;
                    updateTransform();
                }});
                
                document.addEventListener('mouseup', function() {{
                    isDragging = false;
                    container.classList.remove('grabbing');
                }});
            }})();
        </script>
    </div>
    """
    
    return html_content