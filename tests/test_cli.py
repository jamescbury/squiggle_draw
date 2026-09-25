"""Test CLI commands."""

import pytest
from click.testing import CliRunner
from pathlib import Path
import tempfile

from squiggle_draw.cli.main import cli


class TestCLI:
    def test_cli_version(self):
        runner = CliRunner()
        result = runner.invoke(cli, ['--version'])
        assert result.exit_code == 0
        assert 'version 0.1.0' in result.output
    
    def test_cli_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ['--help'])
        assert result.exit_code == 0
        assert 'Squiggle Draw' in result.output
        assert 'single' in result.output
        assert 'preview' in result.output
    
    def test_single_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ['single', '--help'])
        assert result.exit_code == 0
        assert 'Convert an image to single line art' in result.output
        assert '--contrast' in result.output
    
    def test_preview_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ['preview', '--help'])
        assert result.exit_code == 0
        assert 'Preview edge detection' in result.output
    
    def test_single_missing_input(self):
        runner = CliRunner()
        result = runner.invoke(cli, ['single'])
        assert result.exit_code != 0
        assert 'Missing argument' in result.output
    
    def test_single_invalid_file(self):
        runner = CliRunner()
        result = runner.invoke(cli, ['single', 'nonexistent.jpg'])
        assert result.exit_code != 0
    
    def test_single_with_temp_image(self):
        """Test with a temporary test image."""
        runner = CliRunner()
        
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create a simple test image
            import numpy as np
            from PIL import Image
            
            # Create test image
            test_image = np.zeros((100, 100, 3), dtype=np.uint8)
            test_image[40:60, :] = 255  # White horizontal line
            
            # Save test image
            input_path = Path(tmpdir) / "test.png"
            Image.fromarray(test_image).save(input_path)
            
            # Run CLI
            output_path = Path(tmpdir) / "output.svg"
            result = runner.invoke(cli, [
                'single',
                str(input_path),
                '-o', str(output_path),
                '--max-dimension', '100',
                '--sample-rate', '1.0'
            ])
            
            # Check results
            assert result.exit_code == 0
            assert '✓ Processing complete!' in result.output
            assert output_path.exists()
            
            # Check SVG content
            svg_content = output_path.read_text()
            assert '<svg' in svg_content
            assert '<path' in svg_content