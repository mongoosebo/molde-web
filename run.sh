#!/bin/sh
# Start the game. Needs Godot 4.4 or newer on PATH (Arch: sudo pacman -S godot).
cd "$(dirname "$0")" && exec godot --path . "$@"
