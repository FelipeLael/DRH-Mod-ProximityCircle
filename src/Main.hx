package mods.proximity_circle;

import brain.sceneGraph.SceneGraphManager;
import distributedObjects.DistributedDungeonFloor;
import mods.api.Context;
import mods.api.Mod;
import mods.api.Subscription;
import mods.api.dungeon.Floor;
import mods.api.settings.Flag;
import mods.proximity_circle.ui.Circles;
import openfl.events.Event;

/** A tile library read once: its objects by tile, and the zones that get a ring. */
typedef Analysis = {
	var json:Dynamic;
	var objectsByTile:Map<String, Array<Ring.LibraryObject>>;
	var drawable:Map<String, Bool>;
}

/**
 * Draws a dashed ring around each proximity trigger on the dungeon floor that does something, at the
 * trigger's place and radius. Triggers that do nothing, and triggers that set off an exploding barrel,
 * get no ring.
 *
 * The rings sit on the game's world layer 70, so the camera moves them with the floor and every popup,
 * menu and the HUD draws above them. They are built once per floor; while a floor is shown, nothing
 * runs per frame.
 *
 * All the mod's state is in three places: `state` (which floor, and whether it is built), `rings`
 * (the one shape) and `analysed` (the last tile library read, reused by floors of the same library).
 */
class Main extends Mod {
	/**
	 * The world's layer 70 (`GroundLayer2`): inside the world, so the camera moves it, and below every
	 * popup, menu and the HUD. Not layer 5: a floor's build clears layer 5, which would take the rings
	 * with it. Layer 70 is never cleared, nor hidden by the game's UI toggle.
	 */
	static inline final RING_LAYER = 70;

	var ctx:Context;

	var rings:Circles;

	var showRings:Flag;

	var state:FloorState<Floor>;

	/** The last tile library read. Keyed by the library's identity: a different library is read again. */
	var analysed:Null<Analysis> = null;

	/** Every subscription the mod made, cancelled in `dispose`. */
	var subscriptions:Array<Subscription> = [];

	/** Kept as a value, so the very listener that was added is the one removed. */
	var frameListener:Event->Void;

	override public function init(context:Context):Void {
		ctx = context;
		state = new FloorState<Floor>();
		rings = new Circles();
		frameListener = frame;
		showRings = ctx.settings.flag("showRings", "Show rings", "Draws a ring around each proximity trigger on the floor.", true);
		subscriptions.push(showRings.onChange(function(on:Bool) {
			rings.setVisible(on);
		}));
		subscriptions.push(ctx.onFloorEnter(enterFloor));
		subscriptions.push(ctx.onFloorExit(function(_:Floor) leaveFloor()));
		subscriptions.push(ctx.onTownEnter(leaveFloor));
	}

	override public function ready(context:Context):Void {
		if (sceneGraph() == null)
			throw "the game's scene graph is missing (facade.sceneGraphManager): the rings cannot be placed";
	}

	override public function dispose():Void {
		leaveFloor();
		for (subscription in subscriptions)
			subscription.cancel();
		subscriptions = [];
	}

	function enterFloor(floor:Floor):Void {
		removeRings();
		state.enter(floor);
		syncListener();
	}

	function leaveFloor():Void {
		state.leave();
		removeRings();
		syncListener();
	}

	/** The rings leave the world and their graphics are freed. Safe at any time. */
	function removeRings():Void {
		rings.clear();
		var layers = sceneGraph();
		if (layers != null)
			layers.removeChild(rings.shape);
	}

	/** The frame listener runs exactly while the state is waiting for a floor's data. */
	function syncListener():Void {
		if (state.listening)
			ctx.overlay.addEventListener(Event.ENTER_FRAME, frameListener);
		else
			ctx.overlay.removeEventListener(Event.ENTER_FRAME, frameListener);
	}

	function frame(_:Event):Void {
		switch state.frame() {
			case Nothing:
			case Build(floor):
				if (build(floor))
					state.built();
			case GiveUp(floor):
				ctx.log("Proximity Circle: the game gave no data for floor " + floor.map + " in time; no rings on it.");
		}
		syncListener();
	}

	/**
	 * Draws the floor's rings into the world. False while the game's data or the scene graph is not
	 * there yet.
	 */
	function build(floor:Floor):Bool {
		var game:Null<DistributedDungeonFloor> = @:privateAccess floor.floor;
		var layers = sceneGraph();
		if (game == null || game.isDestroyed || layers == null)
			return false;
		var factory = game.dungeonFloorFactory == null ? null : game.dungeonFloorFactory.tileFactory;
		if (factory == null)
			return false;
		var json:Dynamic = @:privateAccess factory.mTileLibraryJson;
		if (json == null || json.LETiles == null)
			return false;

		var cache = analysed;
		if (cache == null || cache.json != json) {
			cache = analyse(json);
			analysed = cache;
		}

		var tiles:Array<Ring.TileInfo> = [for (tile in floor.tiles) {id: tile.id, x: tile.x, y: tile.y}];
		var zones = Ring.zonesOf(tiles, cache.objectsByTile, cache.drawable);
		rings.build(zones);
		rings.setVisible(showRings.value);
		layers.addChild(rings.shape, RING_LAYER);
		ctx.log("Proximity Circle: " + zones.length + " ring(s) on " + floor.map);
		return true;
	}

	/** Reads a library once: its objects by tile, its wires, and the zones that get a ring. */
	static function analyse(json:Dynamic):Analysis {
		var objectsByTile = new Map<String, Array<Ring.LibraryObject>>();
		var all:Array<Ring.LibraryObject> = [];
		for (tile in (json.LETiles : Array<Dynamic>)) {
			var list:Array<Ring.LibraryObject> = tile.LEObjects;
			objectsByTile.set(tile.id, list);
			for (object in list)
				all.push(object);
		}
		var links:Array<Ring.Link> = json.LETriggers == null ? [] : (json.LETriggers : Array<Ring.Link>);
		return {json: json, objectsByTile: objectsByTile, drawable: Ring.drawable(all, links)};
	}

	function sceneGraph():Null<SceneGraphManager> {
		var facade = ctx.core.facade;
		return facade == null ? null : facade.sceneGraphManager;
	}
}
