import mods.proximity_circle.Ring;
import mods.proximity_circle.Ring.LibraryObject;
import mods.proximity_circle.Ring.Link;
import mods.proximity_circle.Ring.TileInfo;

/** Checks of Ring's rule, the zones' places and the dashes. Run with tests/run.sh; exit 1 on any failure. */
class RingTests {
	static var checks = 0;

	static var failures = 0;

	static function check(name:String, ok:Bool):Void {
		checks++;
		if (!ok) {
			failures++;
			Sys.println("FAIL: " + name);
		}
	}

	static function object(id:String, type:String, constant:String, x:Int, y:Int, radius:Float):LibraryObject {
		return {id: id, type: type, constant: constant, x: x, y: y, radius: radius};
	}

	static function zone(id:String, x:Int, y:Int, radius:Float):LibraryObject {
		return object(id, "LETrigger", "PROXIMITY_TRIGGER", x, y, radius);
	}

	static function gate(id:String):LibraryObject {
		return object(id, "LETriggerGate", "OR_GATE", 0, 0, 0);
	}

	static function timer(id:String):LibraryObject {
		return object(id, "LETrigger", "AUTO_TIMER_TRIGGER", 0, 0, 0);
	}

	static function suicide(id:String):LibraryObject {
		return object(id, "LETrigger", "NPC_SUICIDE_TRIGGER", 0, 0, 0);
	}

	static function effect(id:String):LibraryObject {
		return object(id, "LENPC", "NPC_GENERATOR", 0, 0, 0);
	}

	static function link(from:String, to:String):Link {
		return {triggerId: from, triggerableId: to};
	}

	static function tile(id:String, x:Int, y:Int):TileInfo {
		return {id: id, x: x, y: y};
	}

	/** Whether the zone with this id is drawn under the rule. */
	static function drawn(objects:Array<LibraryObject>, links:Array<Link>, id:String):Bool {
		return Ring.drawable(objects, links).exists(id);
	}

	static function main():Void {
		check("the constant is the one the data uses", Ring.CONSTANT == "PROXIMITY_TRIGGER");
		check("the type is a trigger object", Ring.TYPE == "LETrigger");
		check("the suicide constant is the one the data uses", Ring.SUICIDE == "NPC_SUICIDE_TRIGGER");

		// The rule: a zone is drawn when it does something, and not when it feeds a suicide trigger.
		check("a zone wired straight to an effect is drawn", drawn([zone("z", 0, 0, 1), effect("e")], [link("z", "e")], "z"));
		check("a zone with no wire is not drawn", !drawn([zone("z", 0, 0, 1), effect("e")], [], "z"));
		check("a zone wired to a gate with no output is not drawn", !drawn([zone("z", 0, 0, 1), gate("g")], [link("z", "g")], "z"));
		check("a zone through a gate to an effect is drawn", drawn([zone("z", 0, 0, 1), gate("g"), effect("e")], [link("z", "g"), link("g", "e")], "z"));
		check("a zone through a timer and a gate with no output is not drawn",
			!drawn([zone("z", 0, 0, 1), timer("t"), gate("g")], [link("z", "t"), link("t", "g")], "z"));
		check("a zone through a zone to an effect is drawn", drawn([zone("a", 0, 0, 1), zone("b", 5, 5, 1), effect("e")], [link("a", "b"), link("b", "e")], "a"));
		check("the zone it passes to is drawn too", drawn([zone("a", 0, 0, 1), zone("b", 5, 5, 1), effect("e")], [link("a", "b"), link("b", "e")], "b"));

		// Suicide feeders are not drawn, however they are wired.
		check("a zone wired straight to a suicide trigger is not drawn", !drawn([zone("z", 0, 0, 1), suicide("s")], [link("z", "s")], "z"));
		check("a zone through a gate to a suicide trigger is not drawn",
			!drawn([zone("z", 0, 0, 1), gate("g"), suicide("s")], [link("z", "g"), link("g", "s")], "z"));
		check("a zone through a timer to a suicide trigger is not drawn",
			!drawn([zone("z", 0, 0, 1), timer("t"), suicide("s")], [link("z", "t"), link("t", "s")], "z"));
		check("a zone that feeds a suicide trigger and an effect is not drawn",
			!drawn([zone("z", 0, 0, 1), suicide("s"), effect("e")], [link("z", "s"), link("z", "e")], "z"));
		check("a zone the suicide trigger feeds is not drawn unless it does something",
			!drawn([zone("z", 0, 0, 1), suicide("s")], [link("s", "z")], "z"));

		// Dangling wires: a wire to an object the library does not have is nothing.
		check("a wire to a missing object is nothing", !drawn([zone("z", 0, 0, 1)], [link("z", "gone")], "z"));
		check("a wire from a missing object is nothing", !drawn([zone("z", 0, 0, 1), effect("e")], [link("gone", "z"), link("z", "gone")], "z"));

		// Cycles of gates end, with and without an effect.
		check("a cycle with no effect ends, not drawn",
			!drawn([zone("z", 0, 0, 1), gate("a"), gate("b")], [link("z", "a"), link("a", "b"), link("b", "a")], "z"));
		check("a cycle that reaches an effect ends, drawn",
			drawn([zone("z", 0, 0, 1), gate("a"), gate("b"), effect("e")], [link("z", "a"), link("a", "b"), link("b", "a"), link("b", "e")], "z"));

		// Only zones are in the drawable set.
		var set = Ring.drawable([zone("z", 0, 0, 1), effect("e")], [link("z", "e"), link("e", "z")]);
		check("the drawable set holds zones only", set.exists("z") && !set.exists("e"));

		// The zones' places: the tile's corner plus the object's offset; the radius is the object's.
		var entries = new Map<String, Array<LibraryObject>>();
		entries.set("a", [zone("o1", 450, 60, 150), effect("e")]);
		var drawableA = Ring.drawable(entries.get("a"), [link("o1", "e")]);
		var one = Ring.zonesOf([tile("a", 900, 0)], entries, drawableA);
		check("one zone found", one.length == 1);
		check("zone centre is corner plus offset", one.length == 1 && one[0].x == 1350 && one[0].y == 60);
		check("zone radius is the object's", one.length == 1 && one[0].radius == 150);

		// Only zones that are drawable come out; other types and constants never do.
		var mixed = new Map<String, Array<LibraryObject>>();
		mixed.set("m", [
			object("m1", "LEProp", "PROXIMITY_TRIGGER", 0, 0, 10),
			object("m2", "LETrigger", "PROXIMITY_LOCAL_HERO", 0, 0, 10),
			object("m3", "LETrigger", "AUTO_TIMER_TRIGGER", 0, 0, 10),
			zone("m4", 100, 200, 60),
			zone("m5", 300, 300, 60),
			effect("e")
		]);
		var mixedLinks = [link("m4", "e"), link("m5", "m5x")];
		var filtered = Ring.zonesOf([tile("m", 0, 0)], mixed, Ring.drawable(mixed.get("m"), mixedLinks));
		check("other types and constants are not zones", filtered.length == 1);
		check("only the zone with a working wire is kept", filtered.length == 1 && filtered[0].x == 100 && filtered[0].y == 200);

		// A tile with no library entry, and an empty floor.
		check("tile without an entry has no zone", Ring.zonesOf([tile("none", 0, 0)], entries, drawableA).length == 0);
		check("no tiles, no zones", Ring.zonesOf([], entries, drawableA).length == 0);

		// Several zones in several tiles, in the floor's order, including negative corners.
		var many = new Map<String, Array<LibraryObject>>();
		many.set("p", [zone("p1", 0, 0, 30), zone("p2", 450, 450, 90)]);
		many.set("q", [zone("q1", 10, 20, 300)]);
		var all = [zone("p1", 0, 0, 30), zone("p2", 450, 450, 90), zone("q1", 10, 20, 300), effect("e")];
		var manyLinks = [link("p1", "e"), link("p2", "e"), link("q1", "e")];
		var found = Ring.zonesOf([tile("p", -900, 1800), tile("x", 0, 0), tile("q", 0, 900)], many, Ring.drawable(all, manyLinks));
		check("three zones across two tiles", found.length == 3);
		check("first zone of the first tile", found.length > 0 && found[0].x == -900 && found[0].y == 1800 && found[0].radius == 30);
		check("second zone of the same tile", found.length > 1 && found[1].x == -450 && found[1].y == 2250 && found[1].radius == 90);
		check("zone of the later tile", found.length > 2 && found[2].x == 10 && found[2].y == 920 && found[2].radius == 300);

		// Dashes: evenly spaced, each a fraction of its slot, inside one turn.
		var dashes = Ring.dashes();
		check("dash count", dashes.length == Ring.DASHES);
		var slot = 2 * Math.PI / Ring.DASHES;
		var evenly = true;
		var forward = true;
		for (i in 0...dashes.length) {
			var d = dashes[i];
			if (Math.abs(d.from - i * slot) > 1e-9)
				evenly = false;
			if (Math.abs((d.to - d.from) - slot * Ring.DASH_FRACTION) > 1e-9 || d.to <= d.from)
				forward = false;
		}
		check("dashes start evenly spaced", evenly);
		check("each dash is a fraction of its slot, forward", forward);
		check("dashes stay within one turn", dashes[dashes.length - 1].to <= 2 * Math.PI + 1e-9);

		Sys.println(checks + " checks, " + failures + " failures");
		if (failures > 0)
			Sys.exit(1);
	}
}
