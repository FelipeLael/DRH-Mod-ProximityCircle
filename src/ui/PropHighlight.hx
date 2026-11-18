package mods.proximity_circle.ui;

import actor.ActorRenderer;
import brain.camera.Camera;
import distributedObjects.NPCGameObject;
import mods.proximity_circle.Ring;
import openfl.Lib;

typedef TrackedProp = {
	var idKey:String;
	var npc:NPCGameObject;
	var trap:Ring.PropTrap;
	var renderer:Null<ActorRenderer>;
	var phase:Float;
	var initialHp:UInt;
}

typedef BrokenProp = {
	var x:Float;
	var y:Float;
	var trap:Ring.PropTrap;
	var expiresAtMs:Int;
}

/**
 * Highlights destructible trap objects directly on the prop sprites themselves so players can
 * spot and avoid breaking them (barrels, statues, cages, eggs that spawn enemies or traps).
 *
 * Uses a high-luminance electric violet-magenta rim glow (`setPersistentGlowFilter`) paired with
 * a gentle ~1.0 Hz specular surface shimmer (`applyStatusTint`):
 * - Electric violet-magenta avoids colliding with DRH's gold mouseover (`0xFDD017`), red selection
 *   (`0xFF0000`), and gold loot sparkles while remaining Protan/Deutan/Tritan readable via high
 *   luminance contrast.
 * - `StarlingActorRenderer` chains `mPersistentGlowFilter` separately from `mHighlightFilter`, so
 *   hovering a marked prop never clears its trap highlight.
 * - Shimmer updates are skipped for props outside the camera cull bounds so off-screen objects incur
 *   zero per-frame Symbol/ColorTransformStyle traversal, while `setPersistentGlowFilter` remains
 *   attached for instant pop-free re-entry.
 */
class PropHighlight {
	/** Electric violet-magenta outer aura: distinct from gold loot/hover and red selection. */
	public static inline final GLOW_COLOR:UInt = 0xD848FF;

	static inline final GLOW_ALPHA:Float = 7.5;

	static inline final GLOW_BLUR:Float = 3.5;

	/** Pale orchid-white specular sheen for surface shimmer. */
	public static inline final SHIMMER_COLOR:UInt = 0xF8D4FF;

	static inline final SHIMMER_MIN:Float = 0.08;

	static inline final SHIMMER_MAX:Float = 0.38;

	static inline final SHIMMER_TRIGGERED_MAX:Float = 0.16;

	static inline final PULSE_RAD_PER_MS:Float = 0.0062831853; // 2 * pi * 1.0 Hz / 1000 ms

	/** Coordinate tolerance matching `TileFactory.getForceFlashForNpc` (`< 0.5`). */
	static inline final POS_TOLERANCE:Float = 0.5;

	/** Generous margin past camera edges so shimmer refreshes just before Starling un-culls the prop. */
	static inline final CAMERA_CULL_MARGIN:Float = 350.0;

	/** Retain broken-prop summary briefly so the player sees what breaking it just spawned. */
	static inline final BROKEN_MEMORY_MS:Int = 6500;

	public var hasActive(get, never):Bool;

	public var entries(get, never):Array<TrackedProp>;

	public var recentBroken(get, never):Array<BrokenProp>;

	var trapsByConstant:Map<String, Array<Ring.PropTrap>> = new Map();

	var tracked:Array<TrackedProp> = [];

	var trackedIds:Map<String, Bool> = new Map();

	var broken:Array<BrokenProp> = [];

	var isVisible:Bool = true;

	public function new() {}

	function get_hasActive():Bool {
		return tracked.length > 0 || broken.length > 0;
	}

	function get_entries():Array<TrackedProp> {
		return tracked;
	}

	function get_recentBroken():Array<BrokenProp> {
		return broken;
	}

	/** Replaces the floor's expected prop-trap coordinates and clears any previous floor highlights. */
	public function setFloorTraps(traps:Array<Ring.PropTrap>, visible:Bool):Void {
		clear();
		isVisible = visible;
		trapsByConstant = new Map();
		for (trap in traps) {
			var bucket = trapsByConstant.get(trap.constant);
			if (bucket == null) {
				bucket = [];
				trapsByConstant.set(trap.constant, bucket);
			}
			bucket.push(trap);
		}
	}

	/** Checks whether a spawned `NPCGameObject` matches one of this floor's trap props and highlights it. */
	public function tryTrack(npc:Null<NPCGameObject>):Bool {
		if (!isAliveProp(npc))
			return false;
		var key = Std.string(npc.id);
		if (trackedIds.exists(key))
			return true;
		var constant = npc.actorData == null ? null : npc.actorData.constant;
		if (constant == null)
			return false;
		var candidates = trapsByConstant.get(constant);
		if (candidates == null)
			return false;

		var px = npc.positionX;
		var py = npc.positionY;
		var matched:Null<Ring.PropTrap> = null;
		for (trap in candidates) {
			if (Math.abs(px - trap.x) < POS_TOLERANCE && Math.abs(py - trap.y) < POS_TOLERANCE) {
				matched = trap;
				break;
			}
		}
		if (matched == null)
			return false;

		var entry:TrackedProp = {
			idKey: key,
			npc: npc,
			trap: matched,
			renderer: rendererOf(npc),
			phase: ((npc.id : Int) % 64) * 0.27,
			initialHp: npc.hitPoints
		};
		tracked.push(entry);
		trackedIds.set(key, true);
		if (isVisible)
			applyEntry(entry, Lib.getTimer());
		return true;
	}

	/** Stops tracking and removes any highlight from object `id` (on despawn or death). */
	public function untrack(id:UInt, nowMs:Int):Void {
		var key = Std.string(id);
		if (!trackedIds.exists(key))
			return;
		trackedIds.remove(key);
		var i = tracked.length - 1;
		while (i >= 0) {
			var entry = tracked[i];
			if (entry.idKey == key) {
				recordBroken(entry, nowMs);
				clearRenderer(entry.renderer);
				tracked.splice(i, 1);
			}
			i--;
		}
	}

	/** Shows or hides the shiny highlight on all currently tracked trap props. */
	public function setVisible(on:Bool):Void {
		isVisible = on;
		var now = Lib.getTimer();
		for (entry in tracked) {
			if (on && isAliveProp(entry.npc)) {
				var r = rendererOf(entry.npc);
				if (r != entry.renderer) {
					clearRenderer(entry.renderer);
					entry.renderer = r;
				}
				applyEntry(entry, now);
			} else {
				clearRenderer(entry.renderer);
			}
		}
	}

	/**
	 * Advances the 1.0 Hz shimmer only on tracked props near the camera, swaps renderers if bound
	 * lazily, and retires dead props immediately while keeping a brief post-break confirmation.
	 */
	public function update(nowMs:Int, camera:Null<Camera>):Void {
		var bi = broken.length - 1;
		while (bi >= 0) {
			if (nowMs >= broken[bi].expiresAtMs)
				broken.splice(bi, 1);
			bi--;
		}

		var i = tracked.length - 1;
		while (i >= 0) {
			var entry = tracked[i];
			if (!isAliveProp(entry.npc)) {
				recordBroken(entry, nowMs);
				clearRenderer(entry.renderer);
				trackedIds.remove(entry.idKey);
				tracked.splice(i, 1);
				i--;
				continue;
			}
			var r = rendererOf(entry.npc);
			if (r != entry.renderer) {
				clearRenderer(entry.renderer);
				entry.renderer = r;
				if (isVisible && r != null)
					r.setPersistentGlowFilter(GLOW_COLOR, GLOW_ALPHA, GLOW_BLUR);
			}
			if (isVisible && r != null) {
				var offScreen = r.isCulled || (camera != null && entry.npc.hasPosition && !camera.isInCullView(entry.npc.positionX, entry.npc.positionY, CAMERA_CULL_MARGIN));
				if (!offScreen) {
					var alreadyHitTriggered = entry.trap.triggerKind == "HIT" && isDamaged(entry);
					var maxAmt = alreadyHitTriggered ? SHIMMER_TRIGGERED_MAX : SHIMMER_MAX;
					r.applyStatusTint(SHIMMER_COLOR, shimmerAmount(nowMs, entry.phase, maxAmt));
				}
			}
			i--;
		}
	}

	public function clear():Void {
		for (entry in tracked)
			clearRenderer(entry.renderer);
		tracked = [];
		trackedIds = new Map();
		trapsByConstant = new Map();
		broken = [];
	}

	public static function isDamaged(entry:TrackedProp):Bool {
		var npc = entry.npc;
		if (npc.hitPoints < entry.initialHp)
			return true;
		var maxInt = Std.int(npc.maxHitPoints);
		return maxInt > 1 && npc.hitPoints < (maxInt : UInt);
	}

	function recordBroken(entry:TrackedProp, nowMs:Int):Void {
		// Record only when the player actually broke it (HP dropped / ActorDeadState), not floor teardown.
		var npc = entry.npc;
		if (npc == null || (!npc.isDead() && npc.hitPoints > 0))
			return;
		var px = npc.hasPosition ? npc.positionX : entry.trap.x;
		var py = npc.hasPosition ? npc.positionY : entry.trap.y;
		broken.push({
			x: px,
			y: py,
			trap: entry.trap,
			expiresAtMs: nowMs + BROKEN_MEMORY_MS
		});
	}

	static function applyEntry(entry:TrackedProp, nowMs:Int):Void {
		var r = entry.renderer;
		if (r == null)
			return;
		r.setPersistentGlowFilter(GLOW_COLOR, GLOW_ALPHA, GLOW_BLUR);
		var alreadyHitTriggered = entry.trap.triggerKind == "HIT" && isDamaged(entry);
		r.applyStatusTint(SHIMMER_COLOR, shimmerAmount(nowMs, entry.phase, alreadyHitTriggered ? SHIMMER_TRIGGERED_MAX : SHIMMER_MAX));
	}

	static inline function shimmerAmount(nowMs:Int, phase:Float, maxAmt:Float):Float {
		var wave = 0.5 + 0.5 * Math.sin(nowMs * PULSE_RAD_PER_MS + phase);
		return SHIMMER_MIN + (maxAmt - SHIMMER_MIN) * wave;
	}

	public static inline function isAliveProp(npc:Null<NPCGameObject>):Bool {
		return npc != null && !npc.isDestroyed && !npc.isDead() && npc.hitPoints > 0 && npc.isProp;
	}

	static inline function rendererOf(npc:NPCGameObject):Null<ActorRenderer> {
		return npc.actorView == null ? null : npc.actorView.bodyAnimRenderer;
	}

	static function clearRenderer(r:Null<ActorRenderer>):Void {
		if (r == null)
			return;
		r.clearPersistentGlowFilter();
		r.clearStatusTint();
	}
}
