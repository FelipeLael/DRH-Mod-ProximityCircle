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
	var phaseMs:Int;
	var initialHp:UInt;
	var maxDim:Float;
	var wasHitTriggered:Bool;
	var lastGlint:Float;
	var colorMat:Array<Dynamic>;
}

typedef BrokenProp = {
	var x:Float;
	var y:Float;
	var trap:Ring.PropTrap;
	var expiresAtMs:Int;
}

/**
 * Highlights destructible trap objects directly on the prop sprites themselves so players can
 * spot and avoid breaking them (barrels, statues, cages, eggs, huts that spawn enemies or traps).
 *
 * Visual & rendering design:
 * - Size- & tier-tuned electric cerise-rose outer rim (`setPersistentGlowFilter`, `0xFF3EA5`):
 *   `blur = 1.8 / alpha = 5.5` on small/medium props (matches DRH ~3 px comic ink & cuts GPU blur
 *   passes by ~29%), `2.3 / 6.0` on large cages/huts (`>= 360 px`), and `2.6 / 7.0` on Boss props.
 * - Anisotropic specular glint via `applyColorFilter` (20-float matrix with GPU `colorOffset`)
 *   instead of `applyStatusTint` (`tintMatrix` has zero additive offset and yields ΔE < 3.5 on dark
 *   iron cages and white snow): produces consistent ΔL ~ +0.10 across dark and bright props while
 *   keeping DRH's dark comic outlines crisp.
 * - Asymmetric "calm rest -> crisp ~175 ms gleam -> smooth decay" envelope (`2200 ms` BREAK,
 *   `1650 ms` hair-trigger HIT, double-glint heartbeat for Boss) eliminates peripheral sine fatigue
 *   and skips matrix uploads completely during the ~70% rest window (`GLINT_EPS = 0.02`,
 *   `REST_GLINT = 0.03` keeps `ColorTransformStyle` attached with zero GC churn).
 * - Already-damaged `"HIT"` props retire to a faint rose-bronze hairline (`0xA86E78`) with glint
 *   disabled so motion cessation immediately signals "already triggered".
 * - Off-screen props are camera-culled (`r.isCulled || !camera.isInCullView(..., 350.0)`).
 */
class PropHighlight {
	/** Electric cerise-rose outer aura: distinct from gold hover/loot, red selection, and purple rarities. */
	public static inline final GLOW_COLOR:UInt = 0xFF3EA5;

	/** Warm rose-white accent used by `TrapHud` prop badges. */
	public static inline final SHIMMER_COLOR:UInt = 0xFFF5FA;

	/** Muted rose-bronze hairline for `"HIT"` props that have already fired. */
	static inline final SPENT_GLOW_COLOR:UInt = 0xA86E78;

	static inline final SMALL_GLOW_ALPHA:Float = 5.5;

	static inline final SMALL_GLOW_BLUR:Float = 1.8;

	static inline final LARGE_GLOW_ALPHA:Float = 6.0;

	static inline final LARGE_GLOW_BLUR:Float = 2.3;

	static inline final BOSS_GLOW_ALPHA:Float = 7.0;

	static inline final BOSS_GLOW_BLUR:Float = 2.6;

	static inline final SPENT_GLOW_ALPHA:Float = 2.5;

	static inline final SPENT_GLOW_BLUR:Float = 1.5;

	static inline final LARGE_PROP_PX:Float = 360.0;

	static inline final BREAK_PERIOD_MS:Int = 2200;

	static inline final HIT_PERIOD_MS:Int = 1650;

	/** Tiny non-zero rest floor prevents `ColorTransformStyle` identity reset/reallocation churn. */
	static inline final REST_GLINT:Float = 0.03;

	/** Skip `applyColorFilter` uploads when the glint envelope changed by less than 2%. */
	static inline final GLINT_EPS:Float = 0.02;

	/** Coordinate tolerance matching `TileFactory.getForceFlashForNpc` (`< 0.5`). */
	static inline final POS_TOLERANCE:Float = 0.5;

	/** Generous margin past camera edges so glint refreshes just before Starling un-culls the prop. */
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

		var rawPhase = ((npc.id : Int) * 347) % BREAK_PERIOD_MS;
		if (rawPhase < 0)
			rawPhase += BREAK_PERIOD_MS;

		var entry:TrackedProp = {
			idKey: key,
			npc: npc,
			trap: matched,
			renderer: rendererOf(npc),
			phaseMs: rawPhase,
			initialHp: npc.hitPoints,
			maxDim: propMaxDim(npc),
			wasHitTriggered: false,
			lastGlint: -1.0,
			colorMat: newMatrix()
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

	/** Shows or hides all active prop highlights without losing track of the live props. */
	public function setVisible(on:Bool):Void {
		isVisible = on;
		var now = Lib.getTimer();
		for (entry in tracked) {
			if (on && isAliveProp(entry.npc)) {
				var r = rendererOf(entry.npc);
				if (r != entry.renderer) {
					clearRenderer(entry.renderer);
					entry.renderer = r;
					entry.maxDim = propMaxDim(entry.npc);
				}
				entry.lastGlint = -1.0;
				applyEntry(entry, now);
			} else {
				clearRenderer(entry.renderer);
			}
		}
	}

	/**
	 * Advances the asymmetric specular glint only on on-screen tracked props (skipping rest frames
	 * via `GLINT_EPS`), transitions damaged `"HIT"` props to a spent hairline, swaps lazy renderers,
	 * and retires dead props while keeping a brief post-break confirmation.
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
				entry.maxDim = propMaxDim(entry.npc);
				entry.lastGlint = -1.0;
				if (isVisible && r != null)
					applyGlow(entry, r);
			}
			if (isVisible && r != null) {
				var hitNow = entry.trap.triggerKind == "HIT" && isDamaged(entry);
				if (hitNow && !entry.wasHitTriggered) {
					entry.wasHitTriggered = true;
					entry.lastGlint = -1.0;
					applyGlow(entry, r);
					r.clearColorFilter();
				} else if (!entry.wasHitTriggered) {
					var offScreen = r.isCulled
						|| (camera != null && entry.npc.hasPosition && !camera.isInCullView(entry.npc.positionX, entry.npc.positionY, CAMERA_CULL_MARGIN));
					if (!offScreen) {
						var g = glintAmount(nowMs, entry);
						if (entry.lastGlint < 0.0 || Math.abs(g - entry.lastGlint) >= GLINT_EPS) {
							entry.lastGlint = g;
							fillGlintMatrix(entry.colorMat, g, entry.trap.severity >= Ring.SEVERITY_BOSS);
							r.applyColorFilter(entry.colorMat);
						}
					}
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
		if (entry.trap.triggerKind == "HIT" && isDamaged(entry))
			entry.wasHitTriggered = true;
		applyGlow(entry, r);
		if (entry.wasHitTriggered) {
			r.clearColorFilter();
			entry.lastGlint = -1.0;
		} else {
			var g = glintAmount(nowMs, entry);
			entry.lastGlint = g;
			fillGlintMatrix(entry.colorMat, g, entry.trap.severity >= Ring.SEVERITY_BOSS);
			r.applyColorFilter(entry.colorMat);
		}
	}

	static function applyGlow(entry:TrackedProp, r:ActorRenderer):Void {
		if (entry.wasHitTriggered) {
			r.setPersistentGlowFilter(SPENT_GLOW_COLOR, SPENT_GLOW_ALPHA, SPENT_GLOW_BLUR);
		} else if (entry.trap.severity >= Ring.SEVERITY_BOSS) {
			r.setPersistentGlowFilter(GLOW_COLOR, BOSS_GLOW_ALPHA, BOSS_GLOW_BLUR);
		} else if (entry.maxDim >= LARGE_PROP_PX) {
			r.setPersistentGlowFilter(GLOW_COLOR, LARGE_GLOW_ALPHA, LARGE_GLOW_BLUR);
		} else {
			r.setPersistentGlowFilter(GLOW_COLOR, SMALL_GLOW_ALPHA, SMALL_GLOW_BLUR);
		}
	}

	static function glintAmount(nowMs:Int, entry:TrackedProp):Float {
		var isBoss = entry.trap.severity >= Ring.SEVERITY_BOSS;
		var period = (!isBoss && entry.trap.triggerKind == "HIT") ? HIT_PERIOD_MS : BREAK_PERIOD_MS;
		var u = ((nowMs + entry.phaseMs) % period) / period;
		if (u < 0.0)
			u += 1.0;

		var wave = 0.0;
		if (isBoss) {
			// Double-glint heartbeat: calm rest [0..0.56], primary gleam [0.56..0.77], echo [0.78..0.98]
			if (u >= 0.56 && u < 0.77) {
				wave = asymmetricPulse((u - 0.56) / 0.21);
			} else if (u >= 0.78 && u < 0.98) {
				wave = 0.62 * asymmetricPulse((u - 0.78) / 0.20);
			}
		} else if (u >= 0.70) {
			wave = asymmetricPulse((u - 0.70) / 0.30);
		}
		return REST_GLINT + (1.0 - REST_GLINT) * wave;
	}

	/** Crisp ~27% cubic attack + smooth ~73% decay (magnocellular capture without sine fatigue). */
	static inline function asymmetricPulse(p:Float):Float {
		if (p <= 0.0 || p >= 1.0)
			return 0.0;
		if (p < 0.27) {
			var t = 1.0 - (p / 0.27);
			return 1.0 - t * t * t;
		}
		var d = (p - 0.27) / 0.73;
		return Math.pow(1.0 - d, 2.2);
	}

	static function newMatrix():Array<Dynamic> {
		return [
			1.0, 0.0, 0.0, 0.0, 0.0,
			0.0, 1.0, 0.0, 0.0, 0.0,
			0.0, 0.0, 1.0, 0.0, 0.0,
			0.0, 0.0, 0.0, 1.0, 0.0
		];
	}

	static inline function fillGlintMatrix(m:Array<Dynamic>, g:Float, isBoss:Bool):Void {
		if (isBoss) {
			// Warmer molten rose-gold sheen bridging to Boss gold accents
			m[0] = 1.0 + 0.20 * g;
			m[4] = 48.0 * g;
			m[6] = 1.0 + 0.04 * g;
			m[9] = 24.0 * g;
			m[12] = 1.0 - 0.04 * g;
			m[14] = 18.0 * g;
		} else {
			// Anisotropic cerise-pearl sheen: +0.10 ΔL across dark cages & snow while keeping comic ink dark
			m[0] = 1.0 + 0.18 * g;
			m[4] = 42.0 * g;
			m[6] = 1.0 - 0.08 * g;
			m[9] = 14.0 * g;
			m[12] = 1.0 + 0.12 * g;
			m[14] = 30.0 * g;
		}
	}

	static function propMaxDim(npc:NPCGameObject):Float {
		var view:Dynamic = npc.actorView;
		if (view != null) {
			var rect:Dynamic = view.mouseHitRect;
			if (rect != null) {
				var d = Math.max(rect.width, rect.height);
				if (d > 0)
					return d;
			}
		}
		return 250.0;
	}

	public static inline function isAliveProp(npc:Null<NPCGameObject>):Bool {
		return npc != null && !npc.isDestroyed && !npc.isDead() && npc.hitPoints > 0 && npc.isProp;
	}

	static inline function rendererOf(npc:NPCGameObject):Null<ActorRenderer> {
		return npc.actorView == null ? null : npc.actorView.actorRenderer;
	}

	static function clearRenderer(r:Null<ActorRenderer>):Void {
		if (r == null)
			return;
		r.clearPersistentGlowFilter();
		r.clearColorFilter();
	}
}
