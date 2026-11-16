## Where the game reads the map made by tools/build_map.py.
## On the desktop that is world/ in the project. In a browser the map is left out of the game's pack and
## scripts/fetch.gd first downloads it into user://world/, which then becomes the place to read from.

static var world := "res://world/"
