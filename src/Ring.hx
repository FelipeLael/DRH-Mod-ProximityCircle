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
 * The zones' rule, colour selection and arithmetic, free of the game.
 *
 * In the game's data a zone is a `LETrigger` object with `PROXIMITY_TRIGGER` or `PROXIMITY_ALL_HERO`,
 * inside a tile of the library. Its centre is the tile's top-left corner plus `(x ?? 0, y ?? 0)`, and
 * its radius is `radius`.
 *
 * A zone gets a ring only if it reaches at least one gameplay-acting object (traps, gates/walls,
 * switches, monster generators...) through logic gates, timers and chained zones. Purely cosmetic
 * sinks (camera shakes, sound cues, floor text) and `NPC_SUICIDE_TRIGGER` (bare exploding-barrel
 * fuses) do not count as acting, without vetoing zones that also drive real traps or ambushes.
 */
class Ring {
	public static inline final TYPE = "LETrigger";

	public static inline final CONSTANT = "PROXIMITY_TRIGGER";

	public static inline final CONSTANT_ALL_HERO = "PROXIMITY_ALL_HERO";

	public static inline final SUICIDE = "NPC_SUICIDE_TRIGGER";

	/** Objects that only pass a signal on: gates, timers and chained proximity zones. */
	static inline final GATE_TYPE = "LETriggerGate";

	static inline final AUTO_TIMER = "AUTO_TIMER_TRIGGER";

	static inline final ASYM_AUTO_TIMER = "ASYM_AUTO_TIMER_TRIGGER";

	/** Non-gameplay feedback sinks that should not by themselves produce a hazard ring. */
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

	/** Cerise-crimson (#FF476C): blue-lifted hazard core for saturated green grass and bright warm sand. */
	public static inline final COLOR_CRIMSON:UInt = 0xFF476C;

	/** True when `object` is a hero proximity trigger zone (`PROXIMITY_TRIGGER` or `PROXIMITY_ALL_HERO`). */
	public static function isZone(object:LibraryObject):Bool {
		return object != null
			&& object.type == TYPE
			&& (object.constant == CONSTANT || object.constant == CONSTANT_ALL_HERO);
	}

	/**
	 * Biome-adaptive 2-hue hazard palette (Option A): selects cerise-crimson on saturated green jungle
	 * and bright warm arena sand (avoiding Protan/Deutan red-green and warm-sand collisions), and flame
	 * tangerine-red across dark, icy and stone biomes.
	 */
	public static function colorForFloor(theme:Null<String>, map:Null<String>):UInt {
		var key = theme != null && theme != "" ? theme.toUpperCase() : (map == null ? "" : map.toUpperCase());
		if (key.indexOf("ARENA") >= 0 || key.indexOf("DINO") >= 0 || key.indexOf("TRIBAL") >= 0)
			return COLOR_CRIMSON;
		return COLOR_FLAME;
	}

	/**
	 * The ids of the zones to draw, as keys: every proximity zone wired to at least one gameplay-acting
	 * object. Found in one backward pass from the acting objects over the library's wires.
	 */
	public static function drawable(objects:Array<LibraryObject>, links:Array<Link>):Map<String, Bool> {
		var known = new Map<String, Bool>();
		var acting:Array<String> = [];
		var zones:Array<String> = [];
		for (object in objects) {
			if (object == null || object.id == null)
				continue;
			known.set(object.id, true);
			if (!isPassing(object) && !isIgnoredSink(object))
				acting.push(object.id);
			if (isZone(object))
				zones.push(object.id);
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

		var doesSomething = reach(acting, driversOf);
		var out = new Map<String, Bool>();
		for (id in zones)
			if (doesSomething.exists(id))
				out.set(id, true);
		return out;
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

	/** Every object that reaches one of the seeds by following wires backward, the seeds included. */
	static function reach(seeds:Array<String>, driversOf:Map<String, Array<String>>):Map<String, Bool> {
		var found = new Map<String, Bool>();
		var queue:Array<String> = [];
		for (id in seeds) {
			if (!found.exists(id)) {
				found.set(id, true);
				queue.push(id);
			}
		}
		while (queue.length > 0) {
			var id = queue.pop();
			if (!driversOf.exists(id))
				continue;
			for (driver in driversOf.get(id)) {
				if (!found.exists(driver)) {
					found.set(driver, true);
					queue.push(driver);
				}
			}
		}
		return found;
	}
}
