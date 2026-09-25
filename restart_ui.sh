#!/bin/bash
# Script to restart the UI and clear Python cache

echo "Clearing Python cache..."
find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null
find . -name "*.pyc" -delete 2>/dev/null

echo "Clearing Streamlit cache..."
rm -rf ~/.streamlit/cache 2>/dev/null

echo "Starting Squiggle Draw UI..."
source .venv/bin/activate
python -m streamlit run src/squiggle_draw/ui/app.py