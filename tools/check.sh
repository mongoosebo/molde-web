#!/bin/sh
# Runs every self-test of the game in turn and says which failed (the plan of 18 November, 3.2).
#   tools/check.sh            all of them (about ten minutes; the benchmark is most of it)
#   tools/check.sh quick      all but the benchmark
#   tools/check.sh jobs car   only those named
# A test fails if the game reports a script or shader error, says PROBLEMS or FAILED, or does not finish in time.
# What each one printed is kept in data/check/<name>.log. Do not run this while tools/build_map.py is running.
cd "$(dirname "$0")/.." || exit 1
ALL="models body garage cast traffic people sound patchtest molde menu swim bike heli plane car handling jobs winter lamps film indoors bridges standing bench"
case "$1" in
  "") TESTS="$ALL" ;;
  quick) TESTS=$(echo "$ALL" | sed 's/ bench//') ;;
  *) TESTS="$*" ;;
esac
mkdir -p data/check
failed=""
for t in $TESTS; do
  limit=300
  [ "$t" = bench ] && limit=900
  log="data/check/$t.log"
  timeout "$limit" godot --path . -- "--$t" > "$log" 2>&1
  code=$?
  why=""
  [ "$code" = 124 ] && why="did not finish in $limit s"
  if grep -q "SCRIPT ERROR\|SHADER ERROR\|Parse Error\|PROBLEMS\|FAILED" "$log"; then
    why="$why $(grep -m1 "SCRIPT ERROR\|SHADER ERROR\|Parse Error\|PROBLEMS\|FAILED" "$log" | cut -c1-110)"
  fi
  if [ -n "$why" ]; then
    echo "FAIL  $t  $why"
    failed="$failed $t"
  else
    echo "ok    $t"
  fi
done
if [ -n "$failed" ]; then
  echo "failed:$failed"
  exit 1
fi
echo "all passed"
