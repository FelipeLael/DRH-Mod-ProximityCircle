# Findings

Sources: Dungeon-Rampage-Haxe (`src`, `Resources/Levels`), DRH-Mod-API tag `v1.4.0` (5880b08).

## Where the proximity triggers are

- A proximity trigger is a `LETrigger` object with the constant `PROXIMITY_TRIGGER`, in the `LEObjects` of a tile in `Resources/Levels/<biome>/*.json` (`LETiles`).
- It is not a tile category, and it is not in the `src` code as a category. The earlier mod matched on categories, which is why its rings never drew.
- Its centre is the tile's top-left corner plus the object's `x` and `y`; its radius is the object's `radius`. This matches the game's own sensor: `Tile.createLocalEventCollision` places the sensor at `position + (x, y)`.
- Object ids, wire ids and tile ids are strings in the data; `x`, `y` and `radius` are integers.
- The floor's tile id is the library id: `TileFactory` keys its tile map by the `LETiles` `id`, and the API's `Tile.id` is "the tile's id in its library".

## Which triggers get a ring

- Data across the 37 floor files: 1,100 proximity zones; 1,005 get a ring under the current rule.
- A zone gets a ring only if its outgoing wires (through gates, timers and other zones) reach an object that acts (not a gate, timer or zone).
- A zone gets no ring if its wires reach `NPC_SUICIDE_TRIGGER` (78 zones, all in the four exploding-barrel tiles).
- A wire whose end is missing from its file is treated as nothing. The game ignores it.
- The rule is reproduced in an independent Python script over the level data, with the same totals (1,100 zones, 1,005 drawn).

## Where the rings are drawn

- The world group (`SceneGraphManager.worldLayerGroup`) is added to the root before the UI group. Popups (layer 105) and the HUD are in the UI group, so they draw above the world.
- Layer 70 (`GroundLayer2`) is created and never written to by the game.
- Only layer 5 is cleared on a floor build (`DungeonFloorFactory`), so layer 70 is kept.
- The UI toggle (`ui1_9visible`) hides layers 52–59 only, not layer 70.
- `StarlingWorldCut` masks the whole world group the same way it masks the floor, so rings are clipped with the floor.
- Earlier, a ring drawn on `context.overlay` sat above the popups (the screenshot `image-5.png` case). Moving it into layer 70 fixes the order in the code; not yet seen in the game.

## Timing

- `Host.ready` runs after the scene graph is created (`architectureLoaded` follows the facade constructor), so `ready` can rely on the scene graph.
- The floor's data (`floor.floor`, its `dungeonFloorFactory`, the tile library JSON) can come a few frames after `floorEnter`. The mod waits for it, up to 600 frames (`FloorState.MAX_WAIT_FRAMES`), then gives up for that floor and logs it.
- The tile library JSON is cached by identity (`getTileLibraryJson` returns the cached map entry), so the analysis runs once per library.

## Open items

- The exact object in the earlier `image-6.png` ring was not identified from the screenshot. Under the current rule, no drawn zone sits in a small tile with BRUISER or FODDER. That ring most likely came from an earlier build that drew every zone.
- Game-internal members (`dungeonFloorFactory`, `mTileLibraryJson`, `SceneGraphManager.addChild`) are not checked by Astra; they were checked against the DRH source.
- Nothing has been run in the game.
