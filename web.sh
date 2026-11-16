#!/bin/sh
# Export the game for the browser and serve it on http://localhost:8060
# Needs Godot 4.4 or newer on PATH and its export templates (Editor -> Manage Export Templates -> Download).
#   ./web.sh            export, then serve
#   ./web.sh --serve    serve the last export without exporting again
set -e
cd "$(dirname "$0")"
if [ "$1" != "--serve" ]; then
	mkdir -p build/web
	# A headless editor run imports the project first if needed (the first time takes a while).
	godot --headless --path . --import >/dev/null 2>&1 || true
	godot --headless --path . --export-release "Web" build/web/index.html
	python3 tools/web_site.py build/web        # the map goes next to the page, not in the pack
	ls -lh build/web
fi
echo "Open http://localhost:8060 (Ctrl+C stops the server)"
exec python3 -m http.server 8060 --directory build/web
