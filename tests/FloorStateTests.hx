import mods.proximity_circle.FloorState;

/** Checks of the floor state machine. Run with tests/run.sh; exit 1 on any failure. */
class FloorStateTests {
	static var checks = 0;

	static var failures = 0;

	static function check(name:String, ok:Bool):Void {
		checks++;
		if (!ok) {
			failures++;
			Sys.println("FAIL: " + name);
		}
	}

	static function isIdle<T>(s:FloorState<T>):Bool {
		return switch s.phase {
			case Idle: true;
			case _: false;
		}
	}

	static function isWaiting<T>(s:FloorState<T>):Bool {
		return switch s.phase {
			case Waiting(_, _): true;
			case _: false;
		}
	}

	static function isShown<T>(s:FloorState<T>):Bool {
		return switch s.phase {
			case Shown(_): true;
			case _: false;
		}
	}

	static function main():Void {
		// A fresh state does nothing and listens to nothing.
		var s = new FloorState<String>();
		check("starts idle", isIdle(s));
		check("starts not listening", !s.listening);
		check("starts with no floor", s.current == null);
		check("a frame while idle asks for nothing", switch s.frame() {
			case Nothing: true;
			case _: false;
		});

		// Entering a floor waits for it, and listens.
		s.enter("A");
		check("enter waits", isWaiting(s));
		check("enter listens", s.listening);
		check("current is the entered floor", s.current == "A");

		// A frame asks for a build; the build succeeds and the mod stops listening.
		check("first frame asks for a build of the floor", switch s.frame() {
			case Build("A"): true;
			case _: false;
		});
		s.built();
		check("built shows the floor", isShown(s));
		check("built stops listening", !s.listening);
		check("current is still the floor", s.current == "A");
		check("a frame once shown asks for nothing", switch s.frame() {
			case Nothing: true;
			case _: false;
		});

		// built() outside waiting changes nothing.
		var idle = new FloorState<String>();
		idle.built();
		check("built while idle changes nothing", isIdle(idle));

		// Leaving ends the floor from any phase.
		s.leave();
		check("leave from shown is idle", isIdle(s));
		check("leave stops listening", !s.listening);
		check("leave clears the floor", s.current == null);

		var w = new FloorState<String>();
		w.enter("B");
		w.leave();
		check("leave from waiting is idle", isIdle(w));
		check("leave while waiting stops listening", !w.listening);

		// Entering a new floor replaces the old one, whatever phase it was in.
		var r = new FloorState<String>();
		r.enter("C");
		r.built();
		r.enter("D");
		check("a new floor replaces a shown one", r.current == "D" && isWaiting(r));
		check("a new floor waits, so listens", r.listening);

		// Waiting is bounded: after the limit the floor is given up, and the mod stops listening.
		var g = new FloorState<String>();
		g.enter("E");
		var builds = 0;
		var given = false;
		for (_ in 0...FloorState.MAX_WAIT_FRAMES + 5) {
			switch g.frame() {
				case Build(_): builds++;
				case GiveUp("E"): given = true;
				case _:
			}
		}
		check("every frame of the wait asks for a build", builds == FloorState.MAX_WAIT_FRAMES);
		check("the floor is given up after the limit", given);
		check("given up goes idle", isIdle(g));
		check("given up stops listening", !g.listening);

		// A floor that is built in time is never given up.
		var t = new FloorState<String>();
		t.enter("F");
		var steps = 0;
		while (t.listening && steps < 10) {
			steps++;
			switch t.frame() {
				case Build(_): if (steps == 3) t.built();
				case _:
			}
		}
		check("a floor built in time is never given up", isShown(t));

		Sys.println(checks + " checks, " + failures + " failures");
		if (failures > 0)
			Sys.exit(1);
	}
}
