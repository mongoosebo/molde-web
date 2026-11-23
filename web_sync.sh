#!/bin/sh
# Brings this web version up to the desktop game (mongoosebo/molde), keeping what is the web version's own.
#   ./web_sync.sh [path to the molde repository, default ~/Work/molde]
# It takes the game's committed files (scripts, shaders, sounds, the map, the tools), removes what the game has
# removed, and then puts the web version's own changes back on top from web/web-only.patch (the map's folder by
# way of scripts/paths.gd, no note tool, C to descend, the browser renderer, coarser townspeople, the help
# line). If the patch does not fit any more, it stops and says where: mend by hand, then make the patch again:
#   diff -ruN <the game's scripts and project.godot> <this folder's> > web/web-only.patch     (without *.uid, paths.gd)
# Nothing is committed or pushed: look at `git status`, try it (godot --path . --rendering-method gl_compatibility),
# then push; the workflows publish it and check it in a browser.
set -e
cd "$(dirname "$0")"
M="${1:-$HOME/Work/molde}"
DIRS="scripts shaders sounds world data tools models"
KEEP="scripts/paths.gd tools/web_site.py"
git -C "$M" ls-files $DIRS main.tscn run.sh project.godot > /tmp/web_sync_theirs.$$
for f in $(git ls-files $DIRS); do
  case "$f" in *.uid|*.import) continue ;; esac
  case " $KEEP " in *" $f "*) continue ;; esac
  grep -qxF "$f" /tmp/web_sync_theirs.$$ || rm -f "$f"
done
rm -f /tmp/web_sync_theirs.$$
git -C "$M" archive HEAD $DIRS main.tscn run.sh project.godot | tar -x
git apply --whitespace=nowarn -p1 web/web-only.patch || { echo "web/web-only.patch does not fit: see above"; exit 1; }
echo "synced from $(git -C "$M" log --oneline -1)"
