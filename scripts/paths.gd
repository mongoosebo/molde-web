## Where the game reads the map made by tools/build_map.py.
## On the desktop that is world/ in the project. In a browser the map is left out of the game's pack; the
## page (web/shell.html) downloads it and puts it at /world/ before the game starts, and main.gd points here.

static var world := "res://world/"
