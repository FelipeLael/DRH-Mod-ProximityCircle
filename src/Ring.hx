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

/** An object of a tile in the library, as the library gives it: its id, type, constant and offset. */
typedef LibraryObject = {
	var id:String;
	var type:String;
	var constant:String;
	var x:Int;
	var y:Int;
	var radius:Float;
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
 * The zones' rule and arithmetic, free of the game.
 *
 * In the game's data a zone is a `LETrigger` object with the constant `PROXIMITY_TRIGGER`, inside a
 * tile of the library. Its centre is the tile's top-left corner plus the object's `x` and `y`, and
 * its radius is the object's `radius`.
 *
 * A zone gets a ring only if it does something: it is wired, through gates, timers and other zones,
 * to an object that acts (a trap, a generator, an NPC...). It gets no ring when it feeds an
 * `NPC_SUICIDE_TRIGGER` (the trigger that makes an NPC blow itself up, such as an exploding barrel).
 * A wire to an object the library does not have is nothing: the game ignores it.
 */
class Ring {
	public static inline final TYPE = "LETrigger";

	public static inline final CONSTANT = "PROXIMITY_TRIGGER";

	public static inline final SUICIDE = "NPC_SUICIDE_TRIGGER";

	/** Objects that only pass a signal on: gates, timers and zones. */
	static inline final GATE_TYPE = "LETriggerGate";

	static inline final AUTO_TIMER = "AUTO_TIMER_TRIGGER";

	static inline final ASYM_AUTO_TIMER = "ASYM_AUTO_TIMER_TRIGGER";

	/** Target arc pitch (dash + gap) in world units so small and large rings share the same rhythm. */
	public static inline final DASH_PITCH = 18.0;

	public static inline final MIN_DASHES = 8;

	/** Drawn share of each slot (leaves clean gaps even with round line caps). */
	public static inline final DASH_FRACTION = 0.42;

	/**
	 * The ids of the zones to draw, as keys: a zone that does something, and does not feed a suicide
	 * trigger. Found by two walks backward over the wires, from the acting objects and from the suicide
	 * triggers: one pass over the library, whatever the number of zones. Run once per library.
	 */
	public static function drawable(objects:Array<LibraryObject>, links:Array<Link>):Map<String, Bool> {
		var known = new Map<String, Bool>();
		var acting:Array<String> = [];
		var suicide:Array<String> = [];
		var zones:Array<String> = [];
		for (object in objects) {
			known.set(object.id, true);
			if (!isPassing(object))
				acting.push(object.id);
			if (object.constant == SUICIDE)
				suicide.push(object.id);
			if (object.type == TYPE && object.constant == CONSTANT)
				zones.push(object.id);
		}

		// Who drives whom, counting only wires whose two ends are objects of the library.
		var driversOf = new Map<String, Array<String>>();
		for (link in links) {
			if (!known.exists(link.triggerId) || !known.exists(link.triggerableId))
				continue;
			if (!driversOf.exists(link.triggerableId))
				driversOf.set(link.triggerableId, []);
			driversOf.get(link.triggerableId).push(link.triggerId);
		}

		var doesSomething = reach(acting, driversOf);
		var feedsSuicide = reach(suicide, driversOf);
		var out = new Map<String, Bool>();
		for (id in zones)
			if (doesSomething.exists(id) && !feedsSuicide.exists(id))
				out.set(id, true);
		return out;
	}

	/** The zones of the floor's tiles that are in `drawable`. `objectsByTile` gives a tile's objects by the tile's id. */
	public static function zonesOf(tiles:Array<TileInfo>, objectsByTile:Map<String, Array<LibraryObject>>, drawable:Map<String, Bool>):Array<Zone> {
		var out:Array<Zone> = [];
		for (tile in tiles) {
			if (!objectsByTile.exists(tile.id))
				continue;
			for (object in objectsByTile.get(tile.id))
				if (object.type == TYPE && object.constant == CONSTANT && drawable.exists(object.id))
					out.push({x: tile.x + object.x, y: tile.y + object.y, radius: object.radius});
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

	/** Gates, timers and zones only pass a signal on; any other object acts. */
	static function isPassing(object:LibraryObject):Bool {
		return object.type == GATE_TYPE
			|| object.constant == CONSTANT
			|| object.constant == AUTO_TIMER
			|| object.constant == ASYM_AUTO_TIMER;
	}

	/** Every object that reaches one of the seeds by following wires forward, the seeds included. */
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
