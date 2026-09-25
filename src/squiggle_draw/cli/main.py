#!/usr/bin/env python3
"""Command line interface for Squiggle Draw."""

import click
from pathlib import Path
import sys

from .single_line import single_line_command
from .preview import preview_command
from .ui import ui_command


@click.group()
@click.version_option(version="0.1.0", prog_name="squiggle-draw")
def cli():
    """
    Squiggle Draw - Generate single line art from photos for AxiDraw plotters.
    
    Convert your photos into continuous line drawings that can be plotted
    with pen plotters like AxiDraw.
    """
    pass


# Add subcommands
cli.add_command(single_line_command, name="single")
cli.add_command(preview_command, name="preview")
cli.add_command(ui_command, name="ui")


if __name__ == "__main__":
    cli()