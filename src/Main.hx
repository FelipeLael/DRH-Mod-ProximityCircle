package mods.proximity_circle;

import brain.gameObject.GameObject;
import brain.sceneGraph.SceneGraphManager;
import brain.starling.StarlingLayer;
import brain.starling.StarlingLayerManager;
import distributedObjects.DistributedDungeonFloor;
import distributedObjects.NPCGameObject;
import gameMasterDictionary.GMNpc;
import modding.ModSubscription;
import mods.api.Context;
import mods.api.Mod;
import mods.api.Subscription;
import mods.api.dungeon.Floor;
import mods.proximity_circle.ui.Circles;
import mods.proximity_circle.ui.PropHighlight;
import mods.proximity_circle.ui.TrapHud;
import mods.proximity_circle.ui.ZoneTracker;
import openfl.Lib;
import openfl.events.Event;

/** A tile library read once: its theme, its objects by tile, and the zones/prop traps to mark. */
typedef Analysis = {
	var json:Dynamic;
	var theme:String;
	var objectsByTile:Map<String, Array<Ring.LibraryObject>>;
	var drawable:Map<String, Ring.Outcome>;
	var drawableProps:Map<String, Ring.PropEntry>;
}

/**
 * Marks floor proximity traps (cased dashed rings on Starling floor layer 12), highlights
 * destructible trap objects directly on the prop sprites (`PropHighlight`), and displays an
 * in-game DRH-styled proximity HUD (`TrapHud`) showing what nearby triggers activate/spawn.
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

	var tracker:ZoneTracker;

	var hud:Null<TrapHud> = null;

	var visible:Bool = true;

	var state:FloorState<Floor>;

	var currentGame:Null<DistributedDungeonFloor> = null;

	var activeZones:Array<Ring.Zone> = [];

	var activeCoreColor:UInt = Ring.COLOR_TRAP;

	var frameHooked:Bool = false;

	var overlayLayerWarned:Bool = false;

	/** The last tile library read. Keyed by the library's identity: a different library is read again. */
	var analysed:Null<Analysis> = null;

	/** Cached per-floor GameMaster NPC metadata lookup so `onObjectReady` allocates no closure per spawn. */
	var npcLookup:Null<String->Ring.NpcMeta> = null;

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
		tracker = new ZoneTracker();
		frameListener = frame;
		subscriptions.push(ctx.keys.action("toggle", "Show or hide", "Shows or hides proximity rings, shiny trap objects, and the proximity HUD.", TOGGLE_KEY)
			.onPress(function() {
				visible = !visible;
				rings.setVisible(visible);
				highlights.setVisible(visible);
				if (!visible && hud != null)
					hud.reset();
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
		if (hud == null && ctx.overlay != null)
			hud = new TrapHud(ctx.overlay, ctx.core.facade);
	}

	override public function dispose():Void {
		leaveFloor();
		if (hud != null) {
			hud.dispose();
			hud = null;
		}
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

	/** Observes newly ready NPCs for trap-prop highlighting and live ring trigger/spawn status. */
	function onObjectReady(object:GameObject):Void {
		if (state == null || state.current == null || object == null)
			return;
		var npc = Std.downcast(object, NPCGameObject);
		if (npc == null)
			return;
		var facade = ctx == null ? null : ctx.core.facade;
		if (tracker != null && facade != null) {
			if (npcLookup == null)
				npcLookup = makeNpcLookup(facade.gameMaster);
			tracker.observeNpc(npc, npcLookup, true, currentGame);
		}
		if (highlights != null && highlights.tryTrack(npc))
			syncListener();
	}

	/** Cleans up tracked prop highlights and zone spawn/target references when an object leaves. */
	function onObjectGone(object:GameObject):Void {
		if (object == null)
			return;
		if (highlights != null)
			highlights.untrack(object.id, Lib.getTimer());
		if (tracker != null)
			tracker.onObjectGone(object.id);
		syncListener();
	}

	/** Removes all floor rings, prop-trap highlights, tracker state, and HUD state. */
	function removeMarkers():Void {
		currentGame = null;
		activeZones = [];
		npcLookup = null;
		if (tracker != null)
			tracker.clear();
		if (hud != null)
			hud.reset();
		if (highlights != null)
			highlights.clear();
		if (rings == null)
			return;
		rings.clear();
		var layers = sceneGraph();
		if (layers != null)
			layers.removeChild(rings.shape);
	}

	/** The frame listener runs while waiting for floor data or while visible triggers/props exist. */
	function syncListener():Void {
		if (ctx == null || ctx.overlay == null || frameListener == null || state == null || highlights == null)
			return;
		var needFrame = state.listening || (visible && (highlights.hasActive || activeZones.length > 0));
		if (needFrame == frameHooked)
			return;
		frameHooked = needFrame;
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
		if (visible) {
			var facade = ctx.core.facade;
			var nowMs = Lib.getTimer();
			if (tracker != null)
				tracker.update(nowMs, currentGame);
			if (rings != null && tracker != null)
				rings.syncStates(nowMs, tracker);
			if (highlights != null && highlights.hasActive)
				highlights.update(nowMs, facade == null ? null : facade.camera, currentGame);
			if (hud != null && tracker != null)
				hud.update(nowMs, ctx.viewWidth, ctx.viewHeight, facade, currentGame, visible, activeCoreColor, tracker, highlights);
		}
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
		var starlingFloor:Null<StarlingLayer> = ringStarlingLayer(manager);

		var getNpc = makeNpcLookup(facade.gameMaster);
		npcLookup = getNpc;
		var cache = analysed;
		if (cache == null || cache.json != json) {
			cache = analyse(json, getNpc);
			analysed = cache;
		}

		var tiles:Array<Ring.TileInfo> = [for (tile in floor.tiles) {id: tile.id, x: tile.x, y: tile.y}];
		var zones = Ring.zonesOf(tiles, cache.objectsByTile, cache.drawable);
		var propTraps = Ring.propTrapsOf(tiles, cache.objectsByTile, cache.drawableProps, getNpc);
		var coreColor = Ring.colorForFloor(cache.theme, floor.map);

		currentGame = game;
		activeZones = zones;
		activeCoreColor = coreColor;

		layers.removeChild(rings.shape);
		rings.build(zones, coreColor, starlingFloor);
		rings.setVisible(visible);
		if (starlingFloor == null && zones.length > 0)
			layers.addChild(rings.shape, FALLBACK_RING_LAYER);

		tracker.reset(zones);
		var starlingOverlay:Null<StarlingLayer> = manager == null ? null : manager.starlingOverlayLayer;
		highlights.setFloorTraps(propTraps, visible, starlingFloor, starlingOverlay);
		var actors = game.remoteActors;
		if (actors != null) {
			for (key in actors.keysToArray()) {
				var npc = Std.downcast(actors.itemFor(key), NPCGameObject);
				if (npc != null) {
					tracker.observeNpc(npc, getNpc, false, game);
					highlights.tryTrack(npc);
				}
			}
		}

		ctx.log("Proximity Circle: " + zones.length + " ring(s), " + propTraps.length + " prop trap(s) on " + floor.map);
		return true;
	}

	/**
	 * Fetches or creates world layer 12 (`proximityRings`) via `StarlingLayerManager.overlayLayer`,
	 * which is private in DRH (no public method exists to insert a layer between `background` 10
	 * and `sorted` 20). Once created, DRH transforms it with the world camera (`syncWorldTransform`)
	 * and clears its children (`cleanLayers`) as its own; it stays registered in the manager until
	 * exit (`StarlingLayerManager` has no remove-layer API, and an empty layer incurs 0 draw calls).
	 *
	 * Looked up via `Reflect` so a DRH update that renames `overlayLayer` logs once and falls back
	 * cleanly to `FALLBACK_RING_LAYER` instead of failing the mod at compile/load time.
	 */
	function ringStarlingLayer(manager:Null<StarlingLayerManager>):Null<StarlingLayer> {
		if (manager == null)
			return null;
		var fn:Dynamic = Reflect.field(manager, "overlayLayer");
		if (fn != null) {
			try {
				var layer:Dynamic = Reflect.callMethod(manager, fn, [STARLING_RING_LAYER, "proximityRings", null, false]);
				var typed = Std.downcast(layer, StarlingLayer);
				if (typed != null)
					return typed;
			} catch (e:Dynamic) {
				if (!overlayLayerWarned) {
					overlayLayerWarned = true;
					ctx.log("Proximity Circle: StarlingLayerManager.overlayLayer failed (" + Std.string(e) + "); using OpenFL fallback.");
				}
				return null;
			}
		}
		if (!overlayLayerWarned) {
			overlayLayerWarned = true;
			ctx.log("Proximity Circle: StarlingLayerManager.overlayLayer unavailable; using OpenFL fallback.");
		}
		return null;
	}

	static function makeNpcLookup(gameMaster:Dynamic):String->Ring.NpcMeta {
		var npcByConstant = gameMaster == null ? null : gameMaster.npcByConstant;
		return function(constant:String):Ring.NpcMeta {
			var npc:Null<GMNpc> = npcByConstant == null ? null : Std.downcast(npcByConstant.itemFor(constant), GMNpc);
			if (npc == null) {
				return {
					isProp: false,
					name: "",
					isBoss: constant.indexOf("BOSS") >= 0 || constant.indexOf("JUGGERNAUT") >= 0,
					isExploding: constant.indexOf("EXPLODING_BARREL") >= 0,
					isCombatant: false
				};
			}
			var isBoss = npc.IsBoss || npc.HasHealthbar || constant.indexOf("BOSS") >= 0 || constant.indexOf("MINIBOSS") >= 0;
			var isExploding = constant.indexOf("EXPLODING_BARREL") >= 0;
			var isCombatant = npc.CharType == "ENEMY" || (npc.CharType == "BEAST" && npc.Species != "TRAP");
			return {
				isProp: npc.CharType == "PROP",
				name: npc.Name == null ? "" : npc.Name,
				isBoss: isBoss,
				isExploding: isExploding,
				isCombatant: isCombatant
			};
		};
	}

	/** Reads a library once: its theme, its objects by tile, its wires, and the zones/prop traps to mark. */
	static function analyse(json:Dynamic, getNpc:String->Ring.NpcMeta):Analysis {
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
		var set = Ring.drawableSet(all, links, getNpc);
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
