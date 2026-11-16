# Molde web

The browser version of [Molde](https://github.com/mongoosebo/molde), an open-world, third-person game set in
Molde, Norway. Built with Godot 4 and exported for the web (WebGL 2); it also still runs on the desktop.

## Play in a browser

Online: https://mongoosebo.github.io/molde-web/

Every push to `main` exports the game and publishes it there (`.github/workflows/pages.yml`; Settings -> Pages ->
Source must be "GitHub Actions"). The map is not in the game's pack: the page downloads the files in `world/`
(about 265 MB) before the game starts and the browser keeps them, so later visits start quickly and only fetch
files that have changed (`web/shell.html`, list made by `tools/web_site.py`).

To try it on your own machine:

    ./web.sh

exports to `build/web/` and serves it on http://localhost:8060. It needs Godot's export templates
(Editor -> Manage Export Templates -> Download).

In the browser the game uses Godot's Compatibility renderer (WebGL 2) instead of Forward+, so there is no
ambient occlusion and the light is a little flatter; the desktop game is unchanged. The export is
single-threaded, so any plain web server works (no special headers). Click once to take the mouse.
The helicopter goes down with C as well as Ctrl, since Ctrl+W closes a browser tab, and notes
(right mouse button) are off in the browser.

## Run

Needs Godot 4.4 or newer on PATH.

    ./run.sh

## The map

The game area runs from the east mouth of Haukabøtunnelen in the west (blocked with rubble) to 100 m past
Molde lufthavn, Årø in the east, and from the fjord up to Frænavarden in the north. It is set in `tools/area.py`.

Everything in it comes from open data:

- the ground is Kartverket's 1 m terrain model; the game reads it in 100 m cells around the player;
- every roof is worked out from Kartverket's 1 m laser surface model (`tools/roofs.py`);
- trees stand where the laser saw them, at their measured heights;
- roads, sidewalks, bridges, buildings, land cover and street furniture come from OpenStreetMap;
- the mountains in the far view are Kartverket terrain for 96 km around the town.

What a building looks like close up (style, apparent age, colours) is chosen by rule from its type and
measured shape. A few dozen buildings have their real wall colour, read from Mapillary street photos
(`tools/mapillary.py`, `tools/colours.py` -> `data/colours.json`); the photos cover little of the town and
only readings that several photos agree on are used. Those two tools need a Mapillary access token in
`~/.config/molde/mapillary_token`; the rest of the map builds without it.

## Rebuild the map

The map tools need shapely and scipy, kept in a virtual environment in the project:

    python3 -m venv --system-site-packages .venv && .venv/bin/pip install shapely scipy

    .venv/bin/python tools/fetch_osm.py       # OpenStreetMap data for the area -> data/osm_raw.json
    .venv/bin/python tools/make_textures.py
    .venv/bin/python tools/build_map.py       # downloads the Kartverket data it needs (about 1.5 GB, cached in data/kartverket/)

`tools/build_map.py` turns the raw inputs in `data/` into the game-ready files in `world/`. The first run
takes some minutes; later runs about a minute.

## Checks

    ./run.sh -- --shot --view=x,z,yaw,pitch,distance   # save a picture from any spot to data/shot0.png
    ./run.sh -- --perf                                 # frame times on a fast ride through the centre
    ./run.sh -- --drive                                # autopilot the ATV along ten roads; reports what stops it

## Notes from inside the game

There is a crosshair in the middle of the screen. Point it at anything (a building, a tree, a sign, a road, the
ground) and press the right mouse button: the thing lights up yellow and a text box opens. Write what should
change, then Ctrl+Enter (or "Save note"); Esc cancels. Each note is saved as one line in `notes/notes.jsonl`
with what was pointed at, where it is, where the player stood, and a picture in `notes/shots/`. The folder is
not in git. `./run.sh -- --notetest --view=x,z,yaw,pitch,dist` tries the tool without a player.

## Credits

Map data © OpenStreetMap contributors, available under the Open Database License (ODbL).
Terrain, building heights and roof shapes from Kartverket's laser data (hoydedata.no), © Kartverket.
A few wall colours are derived from street photos by Mapillary contributors (CC BY-SA 4.0).
