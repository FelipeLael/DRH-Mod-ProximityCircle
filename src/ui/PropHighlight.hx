package mods.proximity_circle.ui;

import actor.ActorRenderer;
import brain.camera.Camera;
import brain.starling.StarlingLayer;
import distributedObjects.DistributedDungeonFloor;
import distributedObjects.NPCGameObject;
import mods.proximity_circle.Ring;
import openfl.Lib;
import starling.display.MeshBatch;
import starling.display.Quad;
import starling.styles.MeshStyle;

typedef TrackedProp = {
	var idKey:String;
	var npc:NPCGameObject;
	var trap:Ring.PropTrap;
	var renderer:Null<ActorRenderer>;
	var phaseMs:Int;
	var initialHp:UInt;
	var maxDim:Float;
	var collarR:Float;
	var badgeLift:Float;
	var wasHitTriggered:Bool;
	var lastGlint:Float;
	var colorMat:Array<Dynamic>;
	var collarBatch:Null<MeshBatch>;
	var badgeBatch:Null<MeshBatch>;
}

typedef BrokenProp = {
	var x:Float;
	var y:Float;
	var trap:Ring.PropTrap;
	var expiresAtMs:Int;
}

/**
 * Marks destructible trap objects (barrels, cages, statues, eggs, huts) using negative-affordance
 * signifiers grounded in ecological & hazard-warning psychology (Gibson 1979, Norman 2013,
 * Wogalter C-HIP, ANSI Z535.3, Glover & Wogalter 1998, Mayer Spatial Contiguity, Palmer 1992):
 *
 * 1. **Overhead Prohibition + Consequence Badge (`starlingOverlayLayer`, layer 36):** Anchored
 *    directly above the prop so gaze never leaves combat. Shows *why* not to break it (bone-ivory
 *    skull for enemies, crowned skull for Mini-Boss, hazard spike for traps) inside a matte
 *    charcoal medallion (`#161210`) framed by an ANSI Z535.3 `#C9544D` prohibition ring & 45-deg
 *    slash with a dark knock-out border so the skull remains legible. Quiet (`0.65` alpha) when
 *    distant; ramps to `0.96` with a brief low-amplitude cage-rattle shudder within swing range.
 * 2. **Base Containment Collar (floor layer 12):** Tightly hugs the prop footprint with inward
 *    charcoal/crimson iron chevrons—visually sealing the prop instead of glowing like loot.
 * 3. **Restrained Sprite Rim & Specular Gleam (`npc.actorView.bodyAnimRenderer`):** Muted crimson
 *    (`#B84A44`) or Boss plum-burgundy (`#A34E68`) rim glow + subtle anisotropic GPU color-filter
 *    gleam (camera-culled off-screen; retired cleanly once a `"HIT"` prop has fired).
 */
class PropHighlight {
	/** Muted crimson-terracotta warning color (used for prop rim, badges, and HUD accent). */
	public static inline final GLOW_COLOR:UInt = 0xC9544D;

	/** Warm bone-ivory icon color used for consequence silhouettes and HUD badges. */
	public static inline final SHIMMER_COLOR:UInt = 0xE8DFD1;

	static inline final RIM_ENEMY_COLOR:UInt = 0xB84A44;

	static inline final RIM_BOSS_COLOR:UInt = 0xA34E68;

	static inline final COLLAR_ENEMY_COLOR:UInt = 0xA64B4B;

	static inline final COLLAR_BOSS_COLOR:UInt = 0xA34E68;

	static inline final BOSS_CROWN_COLOR:UInt = 0xD4A94A;

	static inline final INK_COLOR:UInt = 0x14110F;

	static inline final BADGE_BG_COLOR:UInt = 0x161210;

	static inline final BADGE_RIM_COLOR:UInt = 0x2E2723;

	static inline final SPENT_GLOW_COLOR:UInt = 0x7A736A;

	static inline final SMALL_GLOW_ALPHA:Float = 4.8;

	static inline final SMALL_GLOW_BLUR:Float = 1.8;

	static inline final LARGE_GLOW_ALPHA:Float = 5.2;

	static inline final LARGE_GLOW_BLUR:Float = 2.2;

	static inline final BOSS_GLOW_ALPHA:Float = 6.0;

	static inline final BOSS_GLOW_BLUR:Float = 2.5;

	static inline final SPENT_GLOW_ALPHA:Float = 2.2;

	static inline final SPENT_GLOW_BLUR:Float = 1.4;

	static inline final LARGE_PROP_PX:Float = 360.0;

	static inline final BREAK_PERIOD_MS:Int = 2200;

	static inline final HIT_PERIOD_MS:Int = 1650;

	static inline final REST_GLINT:Float = 0.03;

	static inline final GLINT_EPS:Float = 0.02;

	/** Weapon-approach range where overhead badge ramps to full contrast + subtle cage rattle. */
	static inline final RATTLE_DIST:Float = 220.0;

	static inline final RATTLE_DIST_SQ:Float = RATTLE_DIST * RATTLE_DIST;

	static inline final RATTLE_PERIOD_MS:Int = 1200;

	static inline final RATTLE_BURST_MS:Int = 180;

	static inline final POS_TOLERANCE:Float = 0.5;

	static inline final CAMERA_CULL_MARGIN:Float = 350.0;

	static inline final BROKEN_MEMORY_MS:Int = 6500;

	public var hasActive(get, never):Bool;

	public var entries(get, never):Array<TrackedProp>;

	public var recentBroken(get, never):Array<BrokenProp>;

	var trapsByConstant:Map<String, Array<Ring.PropTrap>> = new Map();

	var tracked:Array<TrackedProp> = [];

	var trackedIds:Map<String, Bool> = new Map();

	var broken:Array<BrokenProp> = [];

	var floorLayer:Null<StarlingLayer> = null;

	var overlayLayer:Null<StarlingLayer> = null;

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

	/** Replaces the floor's expected prop traps and Starling world layers (floor 12 + overlay 36). */
	public function setFloorTraps(traps:Array<Ring.PropTrap>, visible:Bool, floor:Null<StarlingLayer> = null, overlay:Null<StarlingLayer> = null):Void {
		clear();
		isVisible = visible;
		floorLayer = floor;
		overlayLayer = overlay;
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

	/** Matches a spawned `NPCGameObject` against this floor's trap props and attaches signifiers. */
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

		var dims = measureProp(npc);
		var entry:TrackedProp = {
			idKey: key,
			npc: npc,
			trap: matched,
			renderer: rendererOf(npc),
			phaseMs: rawPhase,
			initialHp: npc.hitPoints,
			maxDim: dims.maxDim,
			collarR: dims.collarR,
			badgeLift: dims.badgeLift,
			wasHitTriggered: false,
			lastGlint: -1.0,
			colorMat: newMatrix(),
			collarBatch: null,
			badgeBatch: null
		};
		buildWorldSignifiers(entry);
		tracked.push(entry);
		trackedIds.set(key, true);
		if (isVisible)
			applyEntry(entry, Lib.getTimer());
		else
			setSignifiersVisible(entry, false);
		return true;
	}

	/** Stops tracking and removes sprite highlights + world signifiers for object `id`. */
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
				cleanupEntry(entry);
				tracked.splice(i, 1);
			}
			i--;
		}
	}

	/** Shows or hides all active prop highlights & world signifiers without losing tracking. */
	public function setVisible(on:Bool):Void {
		isVisible = on;
		var now = Lib.getTimer();
		for (entry in tracked) {
			if (on && isAliveProp(entry.npc)) {
				var r = rendererOf(entry.npc);
				if (r != entry.renderer) {
					clearRenderer(entry.renderer);
					entry.renderer = r;
					refreshDimensions(entry);
				}
				entry.lastGlint = -1.0;
				setSignifiersVisible(entry, true);
				applyEntry(entry, now);
			} else {
				clearRenderer(entry.renderer);
				setSignifiersVisible(entry, false);
			}
		}
	}

	/**
	 * Updates on-screen prop glints, world-space badge proximity escalation/rattle, lazy renderer
	 * binds, `"HIT"` retirement, and post-break memory expiration.
	 */
	public function update(nowMs:Int, camera:Null<Camera>, game:Null<DistributedDungeonFloor> = null):Void {
		var bi = broken.length - 1;
		while (bi >= 0) {
			if (nowMs >= broken[bi].expiresAtMs)
				broken.splice(bi, 1);
			bi--;
		}

		var avatar = (game != null && !game.isDestroyed) ? game.activeOwnerAvatar : null;
		var hasHero = avatar != null && !avatar.isDestroyed && !avatar.isDead() && avatar.hasPosition;
		var hx = hasHero ? avatar.positionX : 0.0;
		var hy = hasHero ? avatar.positionY : 0.0;

		var i = tracked.length - 1;
		while (i >= 0) {
			var entry = tracked[i];
			if (!isAliveProp(entry.npc)) {
				recordBroken(entry, nowMs);
				cleanupEntry(entry);
				trackedIds.remove(entry.idKey);
				tracked.splice(i, 1);
				i--;
				continue;
			}
			var r = rendererOf(entry.npc);
			if (r != entry.renderer) {
				clearRenderer(entry.renderer);
				entry.renderer = r;
				refreshDimensions(entry);
				entry.lastGlint = -1.0;
				if (isVisible && r != null)
					applyGlow(entry, r);
			}
			if (isVisible) {
				var hitNow = entry.trap.triggerKind == "HIT" && isDamaged(entry);
				if (hitNow && !entry.wasHitTriggered) {
					entry.wasHitTriggered = true;
					entry.lastGlint = -1.0;
					if (r != null) {
						applyGlow(entry, r);
						r.clearColorFilter();
					}
					if (entry.collarBatch != null)
						entry.collarBatch.alpha = 0.25;
					if (entry.badgeBatch != null) {
						entry.badgeBatch.alpha = 0.28;
						entry.badgeBatch.x = entry.npc.positionX;
					}
				} else if (!entry.wasHitTriggered) {
					var px = entry.npc.hasPosition ? entry.npc.positionX : entry.trap.x;
					var py = entry.npc.hasPosition ? entry.npc.positionY : entry.trap.y;
					var offScreen = (r != null && r.isCulled) || (camera != null && !camera.isInCullView(px, py, CAMERA_CULL_MARGIN));
					if (!offScreen) {
						if (r != null) {
							var g = glintAmount(nowMs, entry);
							if (entry.lastGlint < 0.0 || Math.abs(g - entry.lastGlint) >= GLINT_EPS) {
								entry.lastGlint = g;
								fillGlintMatrix(entry.colorMat, g, entry.trap.severity >= Ring.SEVERITY_BOSS);
								r.applyColorFilter(entry.colorMat);
							}
						}
						// Proximity escalation & subtle cage-rattle on overhead anti-affordance badge
						if (entry.badgeBatch != null) {
							var near = false;
							if (hasHero) {
								var dx = hx - px;
								var dy = hy - py;
								near = (dx * dx + dy * dy) <= RATTLE_DIST_SQ;
							}
							entry.badgeBatch.alpha = near ? 0.96 : 0.65;
							entry.badgeBatch.y = py - entry.badgeLift;
							if (near) {
								var cyc = (nowMs + entry.phaseMs) % RATTLE_PERIOD_MS;
								if (cyc < 0)
									cyc += RATTLE_PERIOD_MS;
								if (cyc < RATTLE_BURST_MS) {
									var p = cyc / RATTLE_BURST_MS;
									entry.badgeBatch.x = px + Math.sin(p * Math.PI * 4.0) * 1.8 * (1.0 - p);
								} else {
									entry.badgeBatch.x = px;
								}
							} else {
								entry.badgeBatch.x = px;
							}
						}
					}
				}
			}
			i--;
		}
	}

	public function clear():Void {
		for (entry in tracked)
			cleanupEntry(entry);
		tracked = [];
		trackedIds = new Map();
		trapsByConstant = new Map();
		broken = [];
		floorLayer = null;
		overlayLayer = null;
	}

	public static function isDamaged(entry:TrackedProp):Bool {
		var npc = entry.npc;
		if (npc.hitPoints < entry.initialHp)
			return true;
		var maxInt = Std.int(npc.maxHitPoints);
		return maxInt > 1 && npc.hitPoints < (maxInt : UInt);
	}

	function recordBroken(entry:TrackedProp, nowMs:Int):Void {
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

	function cleanupEntry(entry:TrackedProp):Void {
		clearRenderer(entry.renderer);
		if (entry.collarBatch != null) {
			entry.collarBatch.removeFromParent(true);
			entry.collarBatch = null;
		}
		if (entry.badgeBatch != null) {
			entry.badgeBatch.removeFromParent(true);
			entry.badgeBatch = null;
		}
	}

	function setSignifiersVisible(entry:TrackedProp, on:Bool):Void {
		if (entry.collarBatch != null)
			entry.collarBatch.visible = on;
		if (entry.badgeBatch != null)
			entry.badgeBatch.visible = on;
	}

	function refreshDimensions(entry:TrackedProp):Void {
		var dims = measureProp(entry.npc);
		entry.maxDim = dims.maxDim;
		entry.badgeLift = dims.badgeLift;
		if (entry.badgeBatch != null && entry.npc.hasPosition)
			entry.badgeBatch.y = entry.npc.positionY - entry.badgeLift;
	}

	/** Builds the world-space base containment collar (layer 12) + overhead skull/prohibition badge (layer 36). */
	function buildWorldSignifiers(entry:TrackedProp):Void {
		var px = entry.npc.hasPosition ? entry.npc.positionX : entry.trap.x;
		var py = entry.npc.hasPosition ? entry.npc.positionY : entry.trap.y;
		var isBoss = entry.trap.severity >= Ring.SEVERITY_BOSS;

		if (floorLayer != null) {
			var collar = buildCollarBatch(entry.collarR, isBoss);
			collar.x = px;
			collar.y = py;
			collar.visible = isVisible;
			floorLayer.addChild(collar);
			entry.collarBatch = collar;
		}

		if (overlayLayer != null) {
			var badge = buildOverheadBadgeBatch(isBoss, entry.trap.hasGenerator);
			badge.x = px;
			badge.y = py - entry.badgeLift;
			badge.alpha = 0.65;
			badge.visible = isVisible;
			overlayLayer.addChild(badge);
			entry.badgeBatch = badge;
		}
	}

	/** Base containment collar (Palmer Common Region): 8 inward charcoal/crimson iron chevrons hugging footprint. */
	static function buildCollarBatch(r:Float, isBoss:Bool):MeshBatch {
		var batch = new MeshBatch();
		batch.touchable = false;
		batch.setStyle(new MeshStyle(), false);
		var quad = new Quad(1, 1, 0xFFFFFF);
		quad.setStyle(new MeshStyle(), false);

		var coreCol = isBoss ? COLLAR_BOSS_COLOR : COLLAR_ENEMY_COLOR;
		var coreAlpha = isBoss ? 0.72 : 0.64;
		var segs = 16;

		// Charcoal under-ring + restrained mineral collar
		emitRingSegs(batch, quad, r, 3.8, INK_COLOR, 0.48, segs, 0.56);
		emitRingSegs(batch, quad, r, 1.7, coreCol, coreAlpha, segs, 0.52);

		// 8 short inward iron chevrons visually "sealing" the prop
		var chevCount = 8;
		var step = 2 * Math.PI / chevCount;
		for (pass in 0...2) {
			var col = pass == 0 ? INK_COLOR : (isBoss ? BOSS_CROWN_COLOR : coreCol);
			var alp = pass == 0 ? 0.52 : (isBoss ? 0.80 : 0.70);
			var depth = pass == 0 ? 9.5 : 7.2;
			var halfB = pass == 0 ? 5.2 : 3.2;
			setQuadFlat(quad, col, alp);
			for (k in 0...chevCount) {
				var a = k * step + Math.PI * 0.125;
				var dAng = halfB / r;
				var ax = (r - depth) * Math.cos(a);
				var ay = (r - depth) * Math.sin(a);
				quad.setVertexPosition(0, r * Math.cos(a - dAng), r * Math.sin(a - dAng));
				quad.setVertexPosition(1, r * Math.cos(a + dAng), r * Math.sin(a + dAng));
				quad.setVertexPosition(2, ax, ay);
				quad.setVertexPosition(3, ax, ay);
				batch.addMesh(quad, null, 1.0, null, true);
			}
		}

		quad.dispose();
		return batch;
	}

	/**
	 * Overhead Prohibition + Consequence Badge (Mayer Spatial Contiguity + ANSI Z535.3 +
	 * Glover & Wogalter knock-out slash): matte charcoal disc, bone-ivory skull/crowned-skull/spike,
	 * and muted crimson prohibition circle + 45-degree slash.
	 */
	static function buildOverheadBadgeBatch(isBoss:Bool, hasGenerator:Bool):MeshBatch {
		var batch = new MeshBatch();
		batch.touchable = false;
		batch.setStyle(new MeshStyle(), false);
		var quad = new Quad(1, 1, 0xFFFFFF);
		quad.setStyle(new MeshStyle(), false);

		var R:Float = isBoss ? 18.0 : 15.0;
		var s:Float = isBoss ? 1.15 : 1.0;

		// 1. Outer rim & matte charcoal medallion backing (#161210 @ 0.82)
		emitDisc(batch, quad, 0, 0, R + 1.8, BADGE_RIM_COLOR, 0.90, 20);
		emitDisc(batch, quad, 0, 0, R, BADGE_BG_COLOR, 0.84, 20);

		// 2. Consequence pictogram in warm bone-ivory (#E8DFD1)
		if (hasGenerator) {
			// Skull cranium + jaw
			emitDisc(batch, quad, 0, -1.5 * s, 5.4 * s, SHIMMER_COLOR, 0.96, 12);
			emitRect(batch, quad, -3.2 * s, 2.2 * s, 6.4 * s, 3.6 * s, SHIMMER_COLOR, 0.96);
			// Dark eye sockets & teeth gap
			emitDisc(batch, quad, -2.1 * s, -1.3 * s, 1.45 * s, BADGE_BG_COLOR, 0.98, 8);
			emitDisc(batch, quad, 2.1 * s, -1.3 * s, 1.45 * s, BADGE_BG_COLOR, 0.98, 8);
			emitRect(batch, quad, -0.5 * s, 3.8 * s, 1.0 * s, 2.0 * s, BADGE_BG_COLOR, 0.95);
			if (isBoss) {
				// 3-point tarnished gold Mini-Boss crown above skull
				emitRect(batch, quad, -5.2 * s, -8.8 * s, 10.4 * s, 2.6 * s, BOSS_CROWN_COLOR, 0.98);
				emitTri(batch, quad, -5.2 * s, -8.8 * s, -2.4 * s, -8.8 * s, -4.4 * s, -12.4 * s, BOSS_CROWN_COLOR, 0.98);
				emitTri(batch, quad, -1.8 * s, -8.8 * s, 1.8 * s, -8.8 * s, 0.0, -13.2 * s, BOSS_CROWN_COLOR, 0.98);
				emitTri(batch, quad, 2.4 * s, -8.8 * s, 5.2 * s, -8.8 * s, 4.4 * s, -12.4 * s, BOSS_CROWN_COLOR, 0.98);
			} else {
				// Curved enemy horns
				emitTri(batch, quad, -4.6 * s, -4.2 * s, -2.5 * s, -6.4 * s, -7.2 * s, -8.6 * s, SHIMMER_COLOR, 0.95);
				emitTri(batch, quad, 4.6 * s, -4.2 * s, 2.5 * s, -6.4 * s, 7.2 * s, -8.6 * s, SHIMMER_COLOR, 0.95);
			}
		} else {
			// Non-generator trap prop: crisp bone-ivory exclamation hazard icon
			emitRect(batch, quad, -1.6 * s, -7.2 * s, 3.2 * s, 8.6 * s, SHIMMER_COLOR, 0.96);
			emitDisc(batch, quad, 0, 4.8 * s, 1.8 * s, SHIMMER_COLOR, 0.96, 8);
		}

		// 3. ANSI Z535.3 Prohibition ring + 45-degree slash with dark knock-out gap (Glover & Wogalter 1998)
		var ringCol = isBoss ? BOSS_CROWN_COLOR : GLOW_COLOR;
		emitRingSegs(batch, quad, R - 1.4, 2.4, ringCol, 0.94, 20, 1.0);
		var slashR = R - 2.2;
		var d = slashR * 0.7071;
		// Dark knock-out buffer behind slash so skull remains crisp
		emitLine(batch, quad, -d, -d, d, d, 4.2, BADGE_BG_COLOR, 0.92);
		emitLine(batch, quad, -d, -d, d, d, 2.1, GLOW_COLOR, 0.95);

		quad.dispose();
		return batch;
	}

	static inline function setQuadFlat(quad:Quad, color:UInt, alpha:Float):Void {
		for (i in 0...4) {
			quad.setVertexColor(i, color);
			quad.setVertexAlpha(i, alpha);
		}
	}

	static function emitDisc(batch:MeshBatch, quad:Quad, cx:Float, cy:Float, r:Float, color:UInt, alpha:Float, segs:Int):Void {
		setQuadFlat(quad, color, alpha);
		var step = 2 * Math.PI / segs;
		var c0 = 1.0;
		var s0 = 0.0;
		for (k in 1...segs + 1) {
			var a = k == segs ? 0.0 : k * step;
			var c1 = Math.cos(a);
			var s1 = Math.sin(a);
			quad.setVertexPosition(0, cx + r * c0, cy + r * s0);
			quad.setVertexPosition(1, cx + r * c1, cy + r * s1);
			quad.setVertexPosition(2, cx, cy);
			quad.setVertexPosition(3, cx, cy);
			batch.addMesh(quad, null, 1.0, null, true);
			c0 = c1;
			s0 = s1;
		}
	}

	static function emitRingSegs(batch:MeshBatch, quad:Quad, r:Float, thickness:Float, color:UInt, alpha:Float, segs:Int, duty:Float):Void {
		setQuadFlat(quad, color, alpha);
		var slot = 2 * Math.PI / segs;
		var rOut = r + thickness * 0.5;
		var rIn = Math.max(0.0, r - thickness * 0.5);
		for (k in 0...segs) {
			var a0 = k * slot;
			var a1 = a0 + slot * duty;
			var c0 = Math.cos(a0);
			var s0 = Math.sin(a0);
			var c1 = Math.cos(a1);
			var s1 = Math.sin(a1);
			quad.setVertexPosition(0, rOut * c0, rOut * s0);
			quad.setVertexPosition(1, rOut * c1, rOut * s1);
			quad.setVertexPosition(2, rIn * c0, rIn * s0);
			quad.setVertexPosition(3, rIn * c1, rIn * s1);
			batch.addMesh(quad, null, 1.0, null, true);
		}
	}

	static function emitRect(batch:MeshBatch, quad:Quad, x:Float, y:Float, w:Float, h:Float, color:UInt, alpha:Float):Void {
		setQuadFlat(quad, color, alpha);
		quad.setVertexPosition(0, x, y);
		quad.setVertexPosition(1, x + w, y);
		quad.setVertexPosition(2, x, y + h);
		quad.setVertexPosition(3, x + w, y + h);
		batch.addMesh(quad, null, 1.0, null, true);
	}

	static function emitTri(batch:MeshBatch, quad:Quad, x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, color:UInt, alpha:Float):Void {
		setQuadFlat(quad, color, alpha);
		quad.setVertexPosition(0, x0, y0);
		quad.setVertexPosition(1, x1, y1);
		quad.setVertexPosition(2, x2, y2);
		quad.setVertexPosition(3, x2, y2);
		batch.addMesh(quad, null, 1.0, null, true);
	}

	static function emitLine(batch:MeshBatch, quad:Quad, x0:Float, y0:Float, x1:Float, y1:Float, width:Float, color:UInt, alpha:Float):Void {
		var dx = x1 - x0;
		var dy = y1 - y0;
		var len = Math.sqrt(dx * dx + dy * dy);
		if (len <= 0.001)
			return;
		var nx = (-dy / len) * (width * 0.5);
		var ny = (dx / len) * (width * 0.5);
		setQuadFlat(quad, color, alpha);
		quad.setVertexPosition(0, x0 + nx, y0 + ny);
		quad.setVertexPosition(1, x1 + nx, y1 + ny);
		quad.setVertexPosition(2, x0 - nx, y0 - ny);
		quad.setVertexPosition(3, x1 - nx, y1 - ny);
		batch.addMesh(quad, null, 1.0, null, true);
	}

	static function applyEntry(entry:TrackedProp, nowMs:Int):Void {
		var r = entry.renderer;
		if (entry.trap.triggerKind == "HIT" && isDamaged(entry))
			entry.wasHitTriggered = true;
		if (r != null) {
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
		if (entry.wasHitTriggered) {
			if (entry.collarBatch != null)
				entry.collarBatch.alpha = 0.25;
			if (entry.badgeBatch != null)
				entry.badgeBatch.alpha = 0.28;
		}
	}

	static function applyGlow(entry:TrackedProp, r:ActorRenderer):Void {
		if (entry.wasHitTriggered) {
			r.setPersistentGlowFilter(SPENT_GLOW_COLOR, SPENT_GLOW_ALPHA, SPENT_GLOW_BLUR);
		} else if (entry.trap.severity >= Ring.SEVERITY_BOSS) {
			r.setPersistentGlowFilter(RIM_BOSS_COLOR, BOSS_GLOW_ALPHA, BOSS_GLOW_BLUR);
		} else if (entry.maxDim >= LARGE_PROP_PX) {
			r.setPersistentGlowFilter(RIM_ENEMY_COLOR, LARGE_GLOW_ALPHA, LARGE_GLOW_BLUR);
		} else {
			r.setPersistentGlowFilter(RIM_ENEMY_COLOR, SMALL_GLOW_ALPHA, SMALL_GLOW_BLUR);
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
			if (u >= 0.56 && u < 0.77)
				wave = asymmetricPulse((u - 0.56) / 0.21);
			else if (u >= 0.78 && u < 0.98)
				wave = 0.62 * asymmetricPulse((u - 0.78) / 0.20);
		} else if (u >= 0.70) {
			wave = asymmetricPulse((u - 0.70) / 0.30);
		}
		return REST_GLINT + (1.0 - REST_GLINT) * wave;
	}

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

	/** Restrained warm crimson/burgundy specular glint (no neon bloom; preserves comic ink). */
	static inline function fillGlintMatrix(m:Array<Dynamic>, g:Float, isBoss:Bool):Void {
		if (isBoss) {
			m[0] = 1.0 + 0.14 * g;
			m[4] = 30.0 * g;
			m[6] = 1.0 - 0.04 * g;
			m[9] = 10.0 * g;
			m[12] = 1.0 + 0.06 * g;
			m[14] = 18.0 * g;
		} else {
			m[0] = 1.0 + 0.14 * g;
			m[4] = 32.0 * g;
			m[6] = 1.0 - 0.05 * g;
			m[9] = 10.0 * g;
			m[12] = 1.0 - 0.05 * g;
			m[14] = 8.0 * g;
		}
	}

	static function measureProp(npc:NPCGameObject):{maxDim:Float, collarR:Float, badgeLift:Float} {
		var maxDim = 220.0;
		var collarR = 46.0;
		var badgeLift = 86.0;

		var ad:Dynamic = npc.actorData;
		if (ad != null && ad.gMActor != null) {
			var ny:Float = ad.gMActor.NametagY;
			if (!Math.isNaN(ny) && ny > 20.0)
				badgeLift = ny + 18.0;
		}
		var view = npc.actorView;
		if (view != null) {
			var rect = view.mouseHitRect;
			if (rect != null && rect.width > 0 && rect.height > 0) {
				maxDim = Math.max(rect.width, rect.height);
				collarR = Math.max(30.0, Math.min(88.0, rect.width * 0.42 + 6.0));
				var rectTop = -rect.y;
				if (rectTop > 30.0 && rectTop + 14.0 > badgeLift)
					badgeLift = Math.min(220.0, rectTop + 14.0);
			}
		}
		return {maxDim: maxDim, collarR: collarR, badgeLift: badgeLift};
	}

	public static inline function isAliveProp(npc:Null<NPCGameObject>):Bool {
		return npc != null && !npc.isDestroyed && !npc.isDead() && npc.hitPoints > 0 && npc.isProp;
	}

	/** Uses DRH's real `ActorView.bodyAnimRenderer` property (verified in `ActorView.hx:140`). */
	static inline function rendererOf(npc:NPCGameObject):Null<ActorRenderer> {
		return npc.actorView == null ? null : npc.actorView.bodyAnimRenderer;
	}

	static function clearRenderer(r:Null<ActorRenderer>):Void {
		if (r == null)
			return;
		r.clearPersistentGlowFilter();
		r.clearColorFilter();
	}
}
