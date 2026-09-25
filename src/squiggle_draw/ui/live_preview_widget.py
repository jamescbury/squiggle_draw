"""Live preview widget for Streamlit that doesn't require rerun."""

import streamlit as st
from typing import Optional, Dict, Any
import time
import threading
from queue import Queue
import base64


class LivePreviewWidget:
    """A widget that can update SVG preview without triggering st.rerun()."""
    
    def __init__(self):
        self.preview_container = None
        self.preview_queue = Queue()
        self.is_active = False
        
    def create_container(self):
        """Create the preview container."""
        self.preview_container = st.empty()
        self.is_active = True
        return self
        
    def update_preview(self, svg_content: str, points_count: int):
        """Update the preview with new SVG content."""
        if not self.is_active or not self.preview_container:
            return
            
        # Create HTML with inline SVG
        html_content = f"""
        <div style="background: #f8f9fa; border: 1px solid #dee2e6; border-radius: 8px; padding: 20px; height: 500px; position: relative;">
            <div style="position: absolute; top: 10px; left: 10px; background: rgba(255,255,255,0.9); padding: 5px 10px; border-radius: 4px; font-size: 14px; color: #666;">
                Live Preview - {points_count:,} points
            </div>
            <div style="width: 100%; height: 100%; display: flex; align-items: center; justify-content: center;">
                <div style="max-width: 90%; max-height: 90%; overflow: auto;">
                    {svg_content}
                </div>
            </div>
        </div>
        <style>
            svg {{
                max-width: 100%;
                max-height: 100%;
                width: auto !important;
                height: auto !important;
                background: white;
                box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            }}
        </style>
        """
        
        # Update the container
        self.preview_container.markdown(html_content, unsafe_allow_html=True)
        
    def show_placeholder(self):
        """Show placeholder text."""
        if self.preview_container:
            self.preview_container.info("Live preview will appear here during processing...")
            
    def clear(self):
        """Clear the preview."""
        self.is_active = False
        if self.preview_container:
            self.preview_container.empty()


def create_preview_callback(preview_widget: LivePreviewWidget):
    """Create a callback function for pipeline preview updates."""
    def callback(preview_data: Dict[str, Any]):
        if preview_data['type'] == 'preview':
            svg_content = preview_data['svg_content']
            points_count = preview_data['points_count']
            preview_widget.update_preview(svg_content, points_count)
    return callback