package mods.proximity_circle;

/** A zone in world units: its centre and its radius. */
typedef Zone = {
	var x:Float;
	var y:Float;
	var radius:Float;
}

/** A tile as the mod reads it from the floor: its id in the tile library and its top-left corner. */
typedef TileInfo = {
	var id:String;
	var x:Int;
	var y:Int;
}

/** A destructible prop trap in world units: its centre and GM constant. */
typedef PropTrap = {
	var x:Float;
	var y:Float;
	var constant:String;
}

/** Drawable proximity zones and destructible prop traps found in one library pass. */
typedef DrawableSet = {
	var zones:Map<String, Bool>;
	var propTraps:Map<String, Bool>;
}

/**
 * An object of a tile in the library, as the library gives it: its id, type, constant and offset.
 * Flash's exporter omits `x` or `y` when 0, so coordinates and radius are nullable.
 */
typedef LibraryObject = {
	var id:String;
	var type:Null<String>;
	var constant:Null<String>;
	@:optional var x:Null<Float>;
	@:optional var y:Null<Float>;
	@:optional var radius:Null<Float>;
	@:optional var npcId:Null<String>;
}

/** A wire of the library: the object `triggerId` drives the object `triggerableId`. */
typedef Link = {
	var triggerId:String;
	var triggerableId:String;
}

/** One dash of a dashed circle, as angles in radians from the circle's east point. */
typedef Dash = {
	var from:Float;
	var to:Float;
}

/**
 * The zones' and prop-traps' rule, colour selection and arithmetic, free of the game.
 *
 * Proximity zones are `LETrigger` objects with `PROXIMITY_TRIGGER` or `PROXIMITY_ALL_HERO`
 * that reach at least one gameplay-acting object (traps, gates/walls, switches, generators...).
 *
 * Destructible prop traps are non-secret `LENPC` (`PROP`) objects watched by `NPC_DAMAGE_TRIGGER`
 * or an inverted (`NOT_GATE`) `NPC_LIFE_TRIGGER` that drives a gameplay-acting object when
 * damaged or destroyed.
 */
class Ring {
	public static inline final TYPE = "LETrigger";

	public static inline final NPC_TYPE = "LENPC";

	public static inline final CONSTANT = "PROXIMITY_TRIGGER";

	public static inline final CONSTANT_ALL_HERO = "PROXIMITY_ALL_HERO";

	public static inline final LIFE_TRIGGER = "NPC_LIFE_TRIGGER";

	public static inline final DAMAGE_TRIGGER = "NPC_DAMAGE_TRIGGER";

	public static inline final SUICIDE = "NPC_SUICIDE_TRIGGER";

	/** Objects that only pass a signal on: gates, timers and chained proximity zones. */
	static inline final GATE_TYPE = "LETriggerGate";

	static inline final NOT_GATE = "NOT_GATE";

	static inline final AUTO_TIMER = "AUTO_TIMER_TRIGGER";

	static inline final ASYM_AUTO_TIMER = "ASYM_AUTO_TIMER_TRIGGER";

	/** Non-gameplay feedback sinks that should not by themselves produce a hazard marker. */
	static inline final CAMERA_TRIGGERABLE_TYPE = "LETriggerableCamera";

	static inline final FLOOR_MESSAGE = "FLOOR_MESSAGE_TRIGGERABLE";

	static inline final PLAY_SOUND = "PLAY_SOUND_TRIGGERABLE";

	/** Target arc pitch (dash + gap) in world units so small and large rings share the same rhythm. */
	public static inline final DASH_PITCH = 18.0;

	public static inline final MIN_DASHES = 8;

	/** Drawn share of each slot (leaves clean gaps around the cased dash caps). */
	public static inline final DASH_FRACTION = 0.42;

	/** Flame tangerine-red (#FF781F): high-luminance hazard core for dark, cool and neutral stone maps. */
	public static inline final COLOR_FLAME:UInt = 0xFF781F;

	/** Cerise-crimson (#FF476C): blue-lifted hazard core for saturated green jungle and bright warm sand. */
	public static inline final COLOR_CRIMSON:UInt = 0xFF476C;

	/** True when `object` is a hero proximity trigger zone (`PROXIMITY_TRIGGER` or `PROXIMITY_ALL_HERO`). */
	public static function isZone(object:LibraryObject):Bool {
		return object != null
			&& object.type == TYPE
			&& (object.constant == CONSTANT || object.constant == CONSTANT_ALL_HERO);
	}

	/** True when `object` watches a destructible NPC/prop (`NPC_LIFE_TRIGGER` or `NPC_DAMAGE_TRIGGER`). */
	public static function isWatchTrigger(object:LibraryObject):Bool {
		return object != null
			&& object.type == TYPE
			&& (object.constant == LIFE_TRIGGER || object.constant == DAMAGE_TRIGGER)
			&& object.npcId != null;
	}

	/**
	 * Biome-adaptive 2-hue hazard palette: selects cerise-crimson on saturated green jungle and
	 * bright warm arena sand, and flame tangerine-red across dark, icy and stone biomes.
	 */
	public static function colorForFloor(theme:Null<String>, map:Null<String>):UInt {
		var key = theme != null && theme != "" ? theme.toUpperCase() : (map == null ? "" : map.toUpperCase());
		if (key.indexOf("ARENA") >= 0 || key.indexOf("DINO") >= 0 || key.indexOf("TRIBAL") >= 0)
			return COLOR_CRIMSON;
		return COLOR_FLAME;
	}

	/**
	 * Finds both drawable proximity zones and destructible-prop traps (`NPC_DAMAGE_TRIGGER` or
	 * inverted `NPC_LIFE_TRIGGER` watching a non-secret prop) in one parity-aware backward pass.
	 */
	public static function drawableSet(objects:Array<LibraryObject>, links:Array<Link>, isProp:String->Bool):DrawableSet {
		var known = new Map<String, LibraryObject>();
		var acting:Array<String> = [];
		var zones:Array<String> = [];
		var watches:Array<LibraryObject> = [];
		for (object in objects) {
			if (object == null || object.id == null)
				continue;
			known.set(object.id, object);
			if (object.type != TYPE && !isPassing(object) && !isIgnoredSink(object))
				acting.push(object.id);
			if (isZone(object))
				zones.push(object.id);
			else if (isWatchTrigger(object))
				watches.push(object);
		}

		// Who drives whom, counting only wires whose two ends are objects of the library.
		var driversOf = new Map<String, Array<String>>();
		for (link in links) {
			if (link == null || link.triggerId == null || link.triggerableId == null || !known.exists(link.triggerId) || !known.exists(link.triggerableId))
				continue;
			if (!driversOf.exists(link.triggerableId))
				driversOf.set(link.triggerableId, []);
			driversOf.get(link.triggerableId).push(link.triggerId);
		}

		var reachResult = reachParity(acting, driversOf, known);
		var zoneOut = new Map<String, Bool>();
		for (id in zones)
			if (reachResult.p0.exists(id) || reachResult.p1.exists(id))
				zoneOut.set(id, true);

		var propOut = new Map<String, Bool>();
		for (trig in watches) {
			// NPC_LIFE_TRIGGER outputs 0 on destruction (needs p0 at output); NPC_DAMAGE_TRIGGER outputs 1 (needs p1).
			var activeOnTrigger = trig.constant == LIFE_TRIGGER ? reachResult.p0.exists(trig.id) : reachResult.p1.exists(trig.id);
			if (!activeOnTrigger)
				continue;
			var npc = known.get(trig.npcId);
			if (npc == null || npc.id == null || npc.type != NPC_TYPE || npc.constant == null)
				continue;
			if (npc.constant.indexOf("WALL_SECRET") >= 0)
				continue;
			if (isProp(npc.constant))
				propOut.set(npc.id, true);
		}

		return {zones: zoneOut, propTraps: propOut};
	}

	/** Backwards-compatible helper returning only drawable proximity zone ids. */
	public static function drawable(objects:Array<LibraryObject>, links:Array<Link>):Map<String, Bool> {
		return drawableSet(objects, links, function(_) return false).zones;
	}

	/** The zones of the floor's tiles that are in `drawable`. `objectsByTile` gives a tile's objects by the tile's id. */
	public static function zonesOf(tiles:Array<TileInfo>, objectsByTile:Map<String, Array<LibraryObject>>, drawable:Map<String, Bool>):Array<Zone> {
		var out:Array<Zone> = [];
		for (tile in tiles) {
			if (tile == null || tile.id == null || !objectsByTile.exists(tile.id))
				continue;
			for (object in objectsByTile.get(tile.id)) {
				if (object == null || object.id == null || !isZone(object) || !drawable.exists(object.id))
					continue;
				var r = coord(object.radius);
				if (r <= 0)
					continue;
				out.push({
					x: tile.x + coord(object.x),
					y: tile.y + coord(object.y),
					radius: r
				});
			}
		}
		return out;
	}

	/** The destructible prop traps of the floor's tiles that are in `drawableProps`. */
	public static function propTrapsOf(tiles:Array<TileInfo>, objectsByTile:Map<String, Array<LibraryObject>>, drawableProps:Map<String, Bool>):Array<PropTrap> {
		var out:Array<PropTrap> = [];
		for (tile in tiles) {
			if (tile == null || tile.id == null || !objectsByTile.exists(tile.id))
				continue;
			for (object in objectsByTile.get(tile.id)) {
				if (object == null || object.id == null || object.constant == null || !drawableProps.exists(object.id))
					continue;
				out.push({
					x: tile.x + coord(object.x),
					y: tile.y + coord(object.y),
					constant: object.constant
				});
			}
		}
		return out;
	}

	/** The dashes for a ring of `radius`: uniform world-space pitch, at least `MIN_DASHES`. */
	public static function dashesForRadius(radius:Float):Array<Dash> {
		var raw = Math.round(2 * Math.PI * radius / DASH_PITCH);
		var count = raw < MIN_DASHES ? MIN_DASHES : raw;
		var slot = 2 * Math.PI / count;
		var out:Array<Dash> = [];
		for (i in 0...count) {
			var from = i * slot;
			out.push({from: from, to: from + slot * DASH_FRACTION});
		}
		return out;
	}

	static inline function coord(value:Null<Float>):Float {
		return value == null || Math.isNaN(value) ? 0.0 : value;
	}

	/** Gates, timers and proximity zones only pass a signal on. */
	static function isPassing(object:LibraryObject):Bool {
		return object.type == GATE_TYPE
			|| isZone(object)
			|| object.constant == AUTO_TIMER
			|| object.constant == ASYM_AUTO_TIMER;
	}

	/** Barrel self-destructs and purely cosmetic audio/camera/text triggers do not count as hazards. */
	static function isIgnoredSink(object:LibraryObject):Bool {
		return object.constant == SUICIDE
			|| object.type == CAMERA_TRIGGERABLE_TYPE
			|| object.constant == FLOOR_MESSAGE
			|| object.constant == PLAY_SOUND;
	}

	/**
	 * Walks wires backward from acting sinks while tracking `NOT_GATE` parity.
	 * `p1` holds nodes whose `1` output reaches a sink as active (`1`), `p0` holds nodes whose `0` output does.
	 */
	static function reachParity(seeds:Array<String>, driversOf:Map<String, Array<String>>,
			known:Map<String, LibraryObject>):{p0:Map<String, Bool>, p1:Map<String, Bool>} {
		var p0 = new Map<String, Bool>();
		var p1 = new Map<String, Bool>();
		var qIds:Array<String> = [];
		var qParities:Array<Int> = [];
		for (id in seeds) {
			if (!p1.exists(id)) {
				p1.set(id, true);
				qIds.push(id);
				qParities.push(1);
			}
		}
		while (qIds.length > 0) {
			var id = qIds.pop();
			var parity = qParities.pop();
			if (!driversOf.exists(id))
				continue;
			var node = known.get(id);
			var nextParity = (node != null && node.constant == NOT_GATE) ? (1 - parity) : parity;
			var target = nextParity == 0 ? p0 : p1;
			for (driver in driversOf.get(id)) {
				if (!target.exists(driver)) {
					target.set(driver, true);
					qIds.push(driver);
					qParities.push(nextParity);
				}
			}
		}
		return {p0: p0, p1: p1};
	}
}
