#!/bin/sh
# Runs the pure-logic tests under the Haxe interpreter, with no game or OpenFL needed.
# The mod is staged as mods/proximity_circle, the layout Astra and the game use, so package names hold.
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/mods/proximity_circle"
cp -r "$root/src/." "$stage/mods/proximity_circle/"
cp -r "$root/tests" "$stage/tests"
cd "$stage"
haxe -cp . -cp tests -main RingTests --interp
haxe -cp . -cp tests -main FloorStateTests --interp
