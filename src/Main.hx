package mods.proximity_circle;

import brain.gameObject.GameObject;
import brain.sceneGraph.SceneGraphManager;
import brain.starling.StarlingLayer;
import distributedObjects.DistributedDungeonFloor;
import distributedObjects.NPCGameObject;
import modding.ModSubscription;
import mods.api.Context;
import mods.api.Mod;
import mods.api.Subscription;
import mods.api.dungeon.Floor;
import mods.proximity_circle.ui.Circles;
import mods.proximity_circle.ui.PropHighlight;
import openfl.Lib;
import openfl.events.Event;

/** A tile library read once: its theme, its objects by tile, and the zones/prop traps to mark. */
typedef Analysis = {
	var json:Dynamic;
	var theme:String;
	var objectsByTile:Map<String, Array<Ring.LibraryObject>>;
	var drawable:Map<String, Bool>;
	var drawableProps:Map<String, Bool>;
}

/**
 * Marks both floor proximity traps (cased dashed rings on Starling floor layer 12) and destructible
 * trap objects (`NPC_LIFE_TRIGGER` / `NPC_DAMAGE_TRIGGER` props highlighted directly with a glowing
 * violet-magenta rim + shimmering sheen so players avoid destroying them).
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

	var highlights:PropHighlight;

	var visible:Bool = true;

	var state:FloorState<Floor>;

	/** The last tile library read. Keyed by the library's identity: a different library is read again. */
	var analysed:Null<Analysis> = null;

	/** Every API subscription the mod made, cancelled in `dispose`. */
	var subscriptions:Array<Subscription> = [];

	/** Core host subscriptions (`onFieldReceived`, `onObjectReady`, `onObjectGone`), cancelled in `dispose`. */
	var coreSubscriptions:Array<ModSubscription> = [];

	/** Kept as a value, so the very listener that was added is the one removed. */
	var frameListener:Event->Void;

	override public function init(context:Context):Void {
		ctx = context;
		state = new FloorState<Floor>();
		rings = new Circles();
		highlights = new PropHighlight();
		frameListener = frame;
		subscriptions.push(ctx.keys.action("toggle", "Show or hide", "Shows or hides proximity rings and trap object highlights.", TOGGLE_KEY).onPress(function() {
			visible = !visible;
			rings.setVisible(visible);
			highlights.setVisible(visible);
			syncListener();
		}));
		subscriptions.push(ctx.onFloorEnter(enterFloor));
		subscriptions.push(ctx.onFloorExit(function(_:Floor) leaveFloor()));
		subscriptions.push(ctx.onTownEnter(enterTown));
		coreSubscriptions.push(ctx.core.onFieldReceived(onFieldReceived));
		coreSubscriptions.push(ctx.core.onObjectReady(onObjectReady));
		coreSubscriptions.push(ctx.core.onObjectGone(onObjectGone));
	}

	override public function ready(context:Context):Void {
		if (sceneGraph() == null)
			throw "the game's scene graph is missing (facade.sceneGraphManager): the rings cannot be placed";
	}

	override public function dispose():Void {
		leaveFloor();
		analysed = null;
		for (subscription in subscriptions)
			subscription.cancel();
		subscriptions = [];
		for (subscription in coreSubscriptions)
			subscription.cancel();
		coreSubscriptions = [];
	}

	function enterFloor(floor:Floor):Void {
		removeMarkers();
		state.enter(floor);
		syncListener();
	}

	function leaveFloor():Void {
		if (state != null)
			state.leave();
		removeMarkers();
		syncListener();
	}

	function enterTown():Void {
		leaveFloor();
		// Release the parsed tile library JSON when the game clears its own tile library cache in town.
		analysed = null;
	}

	/** Rebuilds markers on the next frame when a secret wall reveals new tiles on the active floor. */
	function onFieldReceived(object:GameObject, _:UInt, name:String):Void {
		if (name != TILES_FIELD || object == null)
			return;
		var floor = state.current;
		if (floor == null || object.id != floor.id)
			return;
		state.refresh();
		syncListener();
	}

	/** Highlights trap props that spawn after initial floor build (or after secret walls open). */
	function onObjectReady(object:GameObject):Void {
		if (highlights == null || state == null || state.current == null || object == null)
			return;
		var npc = Std.downcast(object, NPCGameObject);
		if (npc != null && highlights.tryTrack(npc))
			syncListener();
	}

	/** Cleans up tracked prop highlight when a trap object leaves the floor. */
	function onObjectGone(object:GameObject):Void {
		if (highlights == null || object == null)
			return;
		highlights.untrack(object.id);
		syncListener();
	}

	/** Removes all floor rings and prop-trap highlights. Safe at any time. */
	function removeMarkers():Void {
		if (highlights != null)
			highlights.clear();
		if (rings == null)
			return;
		rings.clear();
		var layers = sceneGraph();
		if (layers != null)
			layers.removeChild(rings.shape);
	}

	/** The frame listener runs while waiting for floor data or while animating visible trap props. */
	function syncListener():Void {
		if (ctx == null || ctx.overlay == null || frameListener == null || state == null || highlights == null)
			return;
		var needFrame = state.listening || (visible && highlights.hasActive);
		if (needFrame)
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
		if (visible && highlights != null && highlights.hasActive)
			highlights.update(Lib.getTimer());
		syncListener();
	}

	/**
	 * Draws the floor's rings and highlights its destructible trap objects. False while the game's
	 * data, Starling layer manager, or scene graph is not ready yet.
	 */
	function build(floor:Floor):Bool {
		var facade = ctx.core.facade;
		var gom = facade == null ? null : facade.gameObjectManager;
		if (gom == null)
			return false;
		var game = Std.downcast(gom.getReferenceFromId(floor.id), DistributedDungeonFloor);
		var layers = sceneGraph();
		if (game == null || game.isDestroyed || layers == null)
			return false;
		var factory = game.dungeonFloorFactory == null ? null : game.dungeonFloorFactory.tileFactory;
		if (factory == null)
			return false;
		var json:Dynamic = @:privateAccess factory.mTileLibraryJson;
		if (json == null || json.LETiles == null)
			return false;

		var manager = facade.starlingLayerManager;
		if (manager != null && !manager.isReady())
			return false;
		var starlingFloor:Null<StarlingLayer> = manager == null ? null : @:privateAccess manager.overlayLayer(STARLING_RING_LAYER, "proximityRings", null, false);

		var cache = analysed;
		if (cache == null || cache.json != json) {
			cache = analyse(json, facade.gameMaster);
			analysed = cache;
		}

		var tiles:Array<Ring.TileInfo> = [for (tile in floor.tiles) {id: tile.id, x: tile.x, y: tile.y}];
		var zones = Ring.zonesOf(tiles, cache.objectsByTile, cache.drawable);
		var propTraps = Ring.propTrapsOf(tiles, cache.objectsByTile, cache.drawableProps);
		var coreColor = Ring.colorForFloor(cache.theme, floor.map);

		layers.removeChild(rings.shape);
		rings.build(zones, coreColor, starlingFloor);
		rings.setVisible(visible);
		if (starlingFloor == null && zones.length > 0)
			layers.addChild(rings.shape, FALLBACK_RING_LAYER);

		highlights.setFloorTraps(propTraps, visible);
		var actors = game.remoteActors;
		if (actors != null) {
			for (key in actors.keysToArray()) {
				var npc = Std.downcast(actors.itemFor(key), NPCGameObject);
				if (npc != null)
					highlights.tryTrack(npc);
			}
		}

		ctx.log("Proximity Circle: " + zones.length + " ring(s), " + propTraps.length + " prop trap(s) on " + floor.map);
		return true;
	}

	/** Reads a library once: its theme, its objects by tile, its wires, and the zones/prop traps to mark. */
	static function analyse(json:Dynamic, gameMaster:Dynamic):Analysis {
		var objectsByTile = new Map<String, Array<Ring.LibraryObject>>();
		var all:Array<Ring.LibraryObject> = [];
		for (tile in (json.LETiles : Array<Dynamic>)) {
			if (tile == null || tile.id == null || tile.LEObjects == null)
				continue;
			var list:Array<Ring.LibraryObject> = tile.LEObjects;
			objectsByTile.set(tile.id, list);
			for (object in list)
				all.push(object);
		}
		var links:Array<Ring.Link> = json.LETriggers == null ? [] : (json.LETriggers : Array<Ring.Link>);
		var theme:String = Std.isOfType(json.theme, String) ? (json.theme : String) : "";
		var npcByConstant = gameMaster == null ? null : gameMaster.npcByConstant;
		var isProp = function(constant:String):Bool {
			if (npcByConstant == null)
				return false;
			var npc:Dynamic = npcByConstant.itemFor(constant);
			return npc != null && npc.CharType == "PROP";
		};
		var set = Ring.drawableSet(all, links, isProp);
		return {
			json: json,
			theme: theme,
			objectsByTile: objectsByTile,
			drawable: set.zones,
			drawableProps: set.propTraps
		};
	}

	function sceneGraph():Null<SceneGraphManager> {
		var facade = ctx.core.facade;
		return facade == null ? null : facade.sceneGraphManager;
	}
}
