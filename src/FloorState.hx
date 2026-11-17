package mods.proximity_circle;

/** Where the mod is with the floor it was told about. */
enum Phase<T> {
	/** No floor: in town, or before the first floor. Nothing is drawn and nothing runs. */
	Idle;

	/** A floor was entered and its rings are not built yet; the frames so far are counted. */
	Waiting(floor:T, frames:Int);

	/** The floor's rings are built and placed. */
	Shown(floor:T);
}

/** What the caller must do after a frame. */
enum Step<T> {
	/** Nothing to do. */
	Nothing;

	/** Try to build the floor's rings now; call `built()` if they are built. */
	Build(floor:T);

	/** The game did not give the floor's data in time: the mod stops waiting for this floor. */
	GiveUp(floor:T);
}

/**
 * The mod's whole floor state in one value. Every transition is a method here, and the frame
 * listener runs exactly while `listening` is true, so no two flags can disagree.
 *
 * Waiting is bounded: after `MAX_WAIT_FRAMES` frames the floor is given up, so the mod never polls
 * for a floor that does not come.
 */
class FloorState<T> {
	/** About ten seconds at 60 frames per second. */
	public static inline final MAX_WAIT_FRAMES = 600;

	public var phase(default, null):Phase<T> = Idle;

	public function new() {}

	/** True while the frame listener must run: only while waiting for a floor's data. */
	public var listening(get, never):Bool;

	function get_listening():Bool {
		return switch phase {
			case Waiting(_, _): true;
			case _: false;
		}
	}

	/** The floor the rings belong to, or null when there is none. */
	public var current(get, never):Null<T>;

	function get_current():Null<T> {
		return switch phase {
			case Idle: null;
			case Waiting(floor, _): floor;
			case Shown(floor): floor;
		}
	}

	/** A floor starts. Any floor still shown or waited for is replaced. */
	public function enter(floor:T):Void {
		phase = Waiting(floor, 0);
	}

	/** The floor ends, or town is entered. Valid from any phase. */
	public function leave():Void {
		phase = Idle;
	}

	/** The rings were built and placed. Only meaningful while waiting; otherwise nothing changes. */
	public function built():Void {
		switch phase {
			case Waiting(floor, _): phase = Shown(floor);
			case _:
		}
	}

	/** A frame passed. While waiting, this asks for a build attempt, or gives the floor up when out of time. */
	public function frame():Step<T> {
		return switch phase {
			case Waiting(floor, frames) if (frames >= MAX_WAIT_FRAMES):
				phase = Idle;
				GiveUp(floor);
			case Waiting(floor, frames):
				phase = Waiting(floor, frames + 1);
				Build(floor);
			case Idle | Shown(_):
				Nothing;
		}
	}
}
