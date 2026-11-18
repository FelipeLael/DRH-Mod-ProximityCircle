package mods.proximity_circle;

import brain.gameObject.GameObject;
import brain.sceneGraph.SceneGraphManager;
import brain.starling.StarlingLayer;
import distributedObjects.DistributedDungeonFloor;
import modding.ModSubscription;
import mods.api.Context;
import mods.api.Mod;
import mods.api.Subscription;
import mods.api.dungeon.Floor;
import mods.proximity_circle.ui.Circles;
import openfl.events.Event;

/** A tile library read once: its theme, its objects by tile, and the zones that get a ring. */
typedef Analysis = {
	var json:Dynamic;
	var theme:String;
	var objectsByTile:Map<String, Array<Ring.LibraryObject>>;
	var drawable:Map<String, Bool>;
}

/**
 * Draws a cased dashed warning ring around each gameplay-acting proximity trigger on the dungeon floor,
 * using a biome-adaptive 2-hue hazard palette (`#FF781F` flame / `#FF476C` cerise-crimson) over an
 * `#08080E` obsidian contrast casing.
 *
 * Rings render on a dedicated world `StarlingLayer` (`sortIndex = 12`), placing them directly on the
 * dungeon floor above ground tiles and floor rugs (`5`/`10`) and beneath heroes, monsters, walls (`20`),
 * room fades (`46`) and the Starling HUD (`64`), with zero `nativeOverlay` hit-test or click-blocking cost.
 * When a secret room opens mid-floor (`DistributedDungeonFloor.tiles`), the rings rebuild once.
 */
class Main extends Mod {
	/** Starling world layer index: above ground (5) and floor decals (10), below sorted actors/walls (20). */
	static inline final STARLING_RING_LAYER = 12;

	/** Fallback OpenFL world layer (`GroundLayer2`) used only if Starling rendering is unavailable. */
	static inline final FALLBACK_RING_LAYER = 70;

	static inline final TILES_FIELD = "DistributedDungeonFloor.tiles";

	/** R key (82), rebindable under CONTROLS in the settings menu. */
	static inline final TOGGLE_KEY:UInt = 82;

	var ctx:Context;

	var rings:Circles;

	var visible:Bool = true;

	var state:FloorState<Floor>;

	/** The last tile library read. Keyed by the library's identity: a different library is read again. */
	var analysed:Null<Analysis> = null;

	/** Every API subscription the mod made, cancelled in `dispose`. */
	var subscriptions:Array<Subscription> = [];

	/** Core host subscriptions (`onFieldReceived`), cancelled in `dispose`. */
	var coreSubscriptions:Array<ModSubscription> = [];

	/** Kept as a value, so the very listener that was added is the one removed. */
	var frameListener:Event->Void;

	override public function init(context:Context):Void {
		ctx = context;
		state = new FloorState<Floor>();
		rings = new Circles();
		frameListener = frame;
		subscriptions.push(ctx.keys.action("toggle", "Show or hide", "Shows or hides the proximity trigger rings on the floor.", TOGGLE_KEY).onPress(function() {
			visible = !visible;
			rings.setVisible(visible);
		}));
		subscriptions.push(ctx.onFloorEnter(enterFloor));
		subscriptions.push(ctx.onFloorExit(function(_:Floor) leaveFloor()));
		subscriptions.push(ctx.onTownEnter(leaveFloor));
		coreSubscriptions.push(ctx.core.onFieldReceived(onFieldReceived));
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
		for (subscription in coreSubscriptions)
			subscription.cancel();
		coreSubscriptions = [];
	}

	function enterFloor(floor:Floor):Void {
		removeRings();
		state.enter(floor);
		syncListener();
	}

	function leaveFloor():Void {
		if (state != null)
			state.leave();
		removeRings();
		syncListener();
	}

	/** Rebuilds rings on the next frame when a secret wall reveals new tiles on the active floor. */
	function onFieldReceived(object:GameObject, _:UInt, name:String):Void {
		if (name != TILES_FIELD || object == null)
			return;
		var floor = state.current;
		if (floor == null || object.id != floor.id)
			return;
		state.refresh();
		syncListener();
	}

	/** The rings leave the world and their geometry is freed. Safe at any time. */
	function removeRings():Void {
		if (rings == null)
			return;
		rings.clear();
		var layers = sceneGraph();
		if (layers != null)
			layers.removeChild(rings.shape);
	}

	/** The frame listener runs exactly while the state is waiting for a floor's data. */
	function syncListener():Void {
		if (ctx == null || ctx.overlay == null || frameListener == null || state == null)
			return;
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
		var facade = ctx.core.facade;
		var gom = facade == null ? null : facade.gameObjectManager;
		if (gom == null)
			return false;
		var game:Null<DistributedDungeonFloor> = cast gom.getReferenceFromId(floor.id);
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
		var coreColor = Ring.colorForFloor(cache.theme, floor.map);
		var starlingFloor = starlingRingLayer();

		layers.removeChild(rings.shape);
		rings.build(zones, coreColor, starlingFloor);
		rings.setVisible(visible);
		if (starlingFloor == null && zones.length > 0)
			layers.addChild(rings.shape, FALLBACK_RING_LAYER);

		ctx.log("Proximity Circle: " + zones.length + " ring(s) on " + floor.map);
		return true;
	}

	/** Reads a library once: its theme, its objects by tile, its wires, and the zones that get a ring. */
	static function analyse(json:Dynamic):Analysis {
		var objectsByTile = new Map<String, Array<Ring.LibraryObject>>();
		var all:Array<Ring.LibraryObject> = [];
		for (tile in (json.LETiles : Array<Dynamic>)) {
			if (tile == null || tile.LEObjects == null)
				continue;
			var list:Array<Ring.LibraryObject> = tile.LEObjects;
			objectsByTile.set(tile.id, list);
			for (object in list)
				all.push(object);
		}
		var links:Array<Ring.Link> = json.LETriggers == null ? [] : (json.LETriggers : Array<Ring.Link>);
		var theme:String = Std.isOfType(json.theme, String) ? (json.theme : String) : "";
		return {
			json: json,
			theme: theme,
			objectsByTile: objectsByTile,
			drawable: Ring.drawable(all, links)
		};
	}

	function starlingRingLayer():Null<StarlingLayer> {
		var facade = ctx.core.facade;
		var manager = facade == null ? null : facade.starlingLayerManager;
		if (manager == null || !manager.isReady())
			return null;
		return @:privateAccess manager.overlayLayer(STARLING_RING_LAYER, "proximityRings", null, false);
	}

	function sceneGraph():Null<SceneGraphManager> {
		var facade = ctx.core.facade;
		return facade == null ? null : facade.sceneGraphManager;
	}
}
