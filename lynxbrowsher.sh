#!/bin/sh
# nano64-html4.sh
# A barebones HTML4 "browser" wrapper using lynx

# Check if lynx is installed
if ! command -v lynx >/dev/null 2>&1; then
  echo "Error: lynx not found. Install with: sudo apt-get install lynx"
  exit 1
fi

# Require an HTML file argument
if [ $# -eq 0 ]; then
  echo "Usage: $0 file.html"
  exit 1
fi

FILE="$1"

# Run lynx in dump mode (renders HTML4 text in terminal)
lynx -dump "$FILE"
