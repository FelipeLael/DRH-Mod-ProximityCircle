# Proximity Circle

<!-- drh:show -->
Draws a crisp dashed hazard ring with a deep obsidian contrast casing around each gameplay proximity trigger on the dungeon floor, keeping floor cues inside completely clear.

- Biome-adaptive 2-hue hazard palette (`#FF781F` flame tangerine-red on dark, icy and stone maps; `#FF476C` cerise-crimson on saturated green jungle and bright warm arena sand) over an `#08080E` casing for strong contrast and colour-vision safety across every tileset.
- Covers both single-hero (`PROXIMITY_TRIGGER`) and party (`PROXIMITY_ALL_HERO`) proximity zones.
- Ignores bare exploding-barrel fuses (`NPC_SUICIDE_TRIGGER`) and purely cosmetic camera, sound or text triggers without hiding real traps or ambushes.
- Automatically updates when secret rooms open mid-floor.
- Rendered natively on Starling's floor layer beneath heroes, monsters, walls, room fades and the HUD, with zero click blocking.

## Controls

- Press **R** to show or hide the rings (rebindable under **CONTROLS** in the settings menu).
<!-- /drh:show -->
