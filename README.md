# Proximity Circle

<!-- drh:show -->
Draws a translucent dashed coral-red warning ring with a dark contrast halo around each proximity trigger on the dungeon floor, so you can see where they are without hiding the ground underneath.

- Triggers that do nothing get no ring.
- Triggers that set off an exploding barrel (any trigger that feeds an `NPC_SUICIDE_TRIGGER`) get no ring.
- Dash spacing scales with ring radius so small and large triggers stay equally crisp.
- Rings move with the floor and stay under every menu, popup and the HUD.
- The rings are drawn on the game's world layer 70, above heroes and monsters, because the game draws the world with Starling underneath.

## Controls

- Press **R** to show or hide the rings (rebindable under **CONTROLS** in the settings menu).
<!-- /drh:show -->
