"""UI command for launching Streamlit interface."""

import click
import subprocess
import sys
from pathlib import Path


@click.command()
@click.option(
    '--port',
    default=8501,
    type=int,
    help='Port to run the UI on (default: 8501)'
)
@click.option(
    '--no-browser',
    is_flag=True,
    help="Don't open browser automatically"
)
def ui_command(port: int, no_browser: bool):
    """
    Launch the interactive web UI.
    
    This opens a web interface where you can upload images,
    adjust parameters in real-time, and download the results.
    """
    # Get the app path
    app_path = Path(__file__).parent.parent / "ui" / "app.py"
    
    # Build streamlit command
    cmd = [
        sys.executable, "-m", "streamlit", "run",
        str(app_path),
        "--server.port", str(port)
    ]
    
    if no_browser:
        cmd.extend(["--server.headless", "true"])
    
    click.echo(click.style("✨ Starting Squiggle Draw UI...", fg="green"))
    click.echo(f"🌐 Open http://localhost:{port} in your browser")
    click.echo("Press Ctrl+C to stop\n")
    
    try:
        subprocess.run(cmd)
    except KeyboardInterrupt:
        click.echo("\n👋 Shutting down...")
    except Exception as e:
        click.echo(click.style(f"❌ Error: {e}", fg="red"), err=True)
        sys.exit(1)