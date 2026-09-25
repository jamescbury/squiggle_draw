#!/usr/bin/env python3
"""Launch the UI for testing."""

import subprocess
import sys
from pathlib import Path

print("Launching Squiggle Draw UI with True Scribbler...")
print("=" * 50)
print("\nAvailable algorithms:")
print("1. true_scribbler - TheScribbler algorithm (NEW!)")
print("2. stipple_tsp - Fast stippling with TSP")
print("3. tone_aware - Variable density based on tone")
print("4. scribble - Original scribble attempt")
print("5. edge_trace - Original edge-based algorithm")
print("\nPress Ctrl+C to stop the server.")
print("=" * 50)

# Change to project directory
project_dir = Path(__file__).parent
subprocess.run(
    [sys.executable, "-m", "streamlit", "run", "src/squiggle_draw/ui/app.py"],
    cwd=project_dir
)