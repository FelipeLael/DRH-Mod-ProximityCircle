# Proximity Circle

Draws a dashed ring around each proximity trigger on the dungeon floor, so you can see where they are.

- Triggers that do nothing get no ring.
- Triggers that set off an exploding barrel (any trigger that feeds an `NPC_SUICIDE_TRIGGER`) get no ring.
- Rings are drawn in the game's world layer 70. They move with the floor and stay under every menu, popup and the HUD (for example "Really exit dungeon?").

## Options

In the MODS tab:

- **Show rings**: turn the rings on or off.

## Installation

Requires Dungeon Rampage Haxe 18 with API 1.4. Put this folder in the mods folder and enable it.

## Tests

`sh tests/run.sh` runs both suites under the Haxe interpreter, without the game:

- `RingTests`: the rule that picks the zones (wired to something that acts, not feeding a suicide trigger) and the zone arithmetic.
- `FloorStateTests`: the floor state machine (enter, build, leave, bounded wait, listening).

The script exits non-zero if any check fails.

## Not yet verified in the game

- That the rings show on the live floor in the expected places. Earlier builds did not show them; this build is unconfirmed.
- That the rings sit under every popup. The game's code puts layer 70 in the world group, which is added before the UI group that holds popup layer 105, so popups should draw above. Not seen running.
- That no ring appears around a non-exploding NPC that has no outgoing wire (the rule excludes these; the exact object in the earlier screenshot was not identified).

See `docs/FINDINGS.md` for the sources behind each claim.
