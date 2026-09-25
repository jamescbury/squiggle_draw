#!/usr/bin/env python3
"""Launch the Streamlit UI."""

import subprocess
import sys
from pathlib import Path


def main():
    """Launch Streamlit app."""
    # Get the app path
    app_path = Path(__file__).parent / "src" / "squiggle_draw" / "ui" / "app.py"
    
    # Run streamlit
    cmd = [sys.executable, "-m", "streamlit", "run", str(app_path)]
    
    print("Starting Squiggle Draw UI...")
    print("Opening in your browser...")
    
    try:
        subprocess.run(cmd)
    except KeyboardInterrupt:
        print("\nShutting down...")


if __name__ == "__main__":
    main()