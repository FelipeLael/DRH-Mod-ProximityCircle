package mods.proximity_circle.ui;

import brain.starling.StarlingLayer;
import mods.proximity_circle.Ring;
import mods.proximity_circle.ui.ZoneTracker;
import openfl.display.Shape;
import starling.display.MeshBatch;
import starling.display.Quad;
import starling.display.Sprite;
import starling.styles.MeshStyle;

private typedef VertexRange = {
	var batch:MeshBatch;
	var startVert:Int;
	var numVerts:Int;
}

private typedef ZoneSlice = {
	var zone:Ring.Zone;
	var severity:Int;
	var isUtility:Bool;
	var isBoss:Bool;
	var wash:Null<VertexRange>;
	var casing:VertexRange;
	var core:VertexRange;
	var accents:Null<VertexRange>;
	var lastVisualState:Int;
}

/**
 * The floor's proximity trigger rings, rendered as restrained etched-mineral dungeon markings.
 *
 * Visual & affordance design (Tufte Smallest Effective Difference + Ware Large Area Rule):
 * - Warm charcoal dual-polarity under-stroke (`0x14110F`, `α = 0.40-0.50`) paired with muted
 *   mineral pigment cores (Aged Terracotta Trap, Tarnished Brass Ambush, Muted Plum-Burgundy
 *   Boss double-ring seal, Weathered Verdigris Gate dots) and **zero idle interior fill**.
 * - Every tier is uniquely identifiable in grayscale / CVD via stroke weight & geometry
 *   (stippled dots, dashes, long-dash + cardinal ticks, Boss double-ring + gold cardinal pips,
 *   and staggered inner dots for `PROXIMITY_ALL_HERO`).
 * - Focal saturation & subtle radial wash (`α = 0.09 -> 0`) appear *only* when a ring is
 *   stepped on or actively firing; cleared one-shot rings fade into faint Stone Ash (`α = 0.24`).
 */
class Circles {
	/** Warm charcoal under-stroke (never pure black): guarantees contrast on snow, sand, and ice. */
	static inline final INK_COLOR:UInt = 0x14110F;

	static inline final INK_ALPHA_UTIL:Float = 0.40;

	static inline final INK_ALPHA_ARMED:Float = 0.46;

	static inline final INK_ALPHA_BOSS:Float = 0.50;

	static inline final INK_ALPHA_ACTIVE:Float = 0.58;

	static inline final INK_ALPHA_CLEARED:Float = 0.18;

	/** Restrained mineral pigment cores by tier & state. */
	static inline final BOSS_ACCENT_COLOR:UInt = 0xD4A94A; // Tarnished gold cardinal pips

	static inline final CORE_INSIDE:UInt = 0xDF8556; // Warm terracotta-amber lift on step-in

	static inline final CORE_ACTIVE:UInt = Ring.COLOR_ACTIVE; // Ember Vermilion (#D96248)

	static inline final CORE_CLEARED:UInt = Ring.COLOR_CLEARED; // Stone Ash (#8C877E)

	/** Subtle active floor halo colors & calm pulse speeds (only visible when stepped on / firing). */
	static inline final GLOW_INSIDE_COLOR:UInt = 0xDF8556;

	static inline final GLOW_ACTIVE_COLOR:UInt = 0xD96248;

	static inline final PULSE_INSIDE_RAD:Float = 0.0094248; // 1.5 Hz

	static inline final PULSE_ACTIVE_RAD:Float = 0.0075398; // 1.2 Hz

	static inline final STEPS = 4;

	static inline final MAX_BATCH_QUADS = 16383;

	/** Soft capsule taper along each 4-quad dash: etched brush/chalk rhythm at zero extra vertices. */
	static final CAP_T:Array<Float> = [0.0, 0.16, 0.50, 0.84, 1.0];

	static final CAP_W:Array<Float> = [0.46, 1.0, 1.0, 1.0, 0.46];

	public var shape(default, null):Shape;

	var starlingRoot:Null<Sprite> = null;

	var activeGlowBatch:Null<MeshBatch> = null;

	var slices:Array<ZoneSlice> = [];

	var openflZones:Array<Ring.Zone> = [];

	var lastRevision:Int = -1;

	var activePulseRad:Float = PULSE_ACTIVE_RAD;

	var isVisible:Bool = true;

	public function new() {
		shape = new Shape();
	}

	public function setVisible(on:Bool):Void {
		isVisible = on;
		shape.visible = on;
		if (starlingRoot != null)
			starlingRoot.visible = on;
	}

	public function clear():Void {
		shape.graphics.clear();
		slices = [];
		openflZones = [];
		lastRevision = -1;
		activeGlowBatch = null;
		if (starlingRoot != null) {
			if (starlingRoot.parent != null)
				starlingRoot.removeFromParent(true);
			else
				starlingRoot.dispose();
			starlingRoot = null;
		}
	}

	/** Builds every zone's etched-mineral ring in world units on `starlingLayer` or OpenFL `shape`. */
	public function build(zones:Array<Ring.Zone>, _:UInt, starlingLayer:Null<StarlingLayer>):Void {
		clear();
		if (zones.length == 0)
			return;

		var profiles = [for (z in zones) Ring.tierProfile(z)];
		var dashSets = [for (i in 0...zones.length) Ring.dashesForRadius(zones[i].radius, profiles[i].pitch, profiles[i].fraction)];

		if (starlingLayer != null) {
			buildStarling(zones, profiles, dashSets, starlingLayer);
			return;
		}

		openflZones = zones;
		buildOpenFL(zones, profiles, dashSets, null);
	}

	/**
	 * Synchronizes live floor ring states with `ZoneTracker`. Idle rings stay crisp with zero fill;
	 * stepped-on and firing rings gain focal ember contrast; cleared rings fade into Stone Ash.
	 */
	public function syncStates(nowMs:Int, tracker:Null<ZoneTracker>):Void {
		if (tracker == null || !isVisible)
			return;

		var rev = tracker.revision;
		if (starlingRoot != null) {
			if (rev != lastRevision) {
				lastRevision = rev;
				patchStarlingStates(tracker.items);
			}
			if (activeGlowBatch != null && activeGlowBatch.visible) {
				var wave = 0.5 + 0.5 * Math.sin(nowMs * activePulseRad);
				activeGlowBatch.alpha = 0.40 + 0.60 * wave;
			}
			return;
		}

		if (openflZones.length > 0 && rev != lastRevision) {
			lastRevision = rev;
			var profiles = [for (z in openflZones) Ring.tierProfile(z)];
			var dashSets = [for (i in 0...openflZones.length) Ring.dashesForRadius(openflZones[i].radius, profiles[i].pitch, profiles[i].fraction)];
			buildOpenFL(openflZones, profiles, dashSets, tracker.items);
		}
	}

	function buildStarling(zones:Array<Ring.Zone>, profiles:Array<Ring.TierProfile>, dashSets:Array<Array<Ring.Dash>>, layer:StarlingLayer):Void {
		var totalQuads = 0;
		for (i in 0...zones.length) {
			var p = profiles[i];
			var dc = dashSets[i].length;
			var compCount = companionCount(zones[i], dc);
			totalQuads += (p.washW > 0 ? dc : 0) + (dc * STEPS * 2) + (compCount * 2 * 2) + (p.teethCount * 2);
		}
		var remainingQuads = totalQuads;

		var root = new Sprite();
		root.touchable = false;
		root.visible = isVisible;

		var glow = newBatch(256);
		glow.visible = false;
		root.addChild(glow);
		activeGlowBatch = glow;

		var batch = newBatch(remainingQuads);
		var quad = new Quad(1, 1, 0xFFFFFF);
		quad.setStyle(new MeshStyle(), false);

		slices = [
			for (i in 0...zones.length) {
				zone: zones[i],
				severity: zones[i].severity,
				isUtility: profiles[i].isUtility,
				isBoss: zones[i].severity >= Ring.SEVERITY_BOSS,
				wash: null,
				casing: {batch: batch, startVert: 0, numVerts: 0},
				core: {batch: batch, startVert: 0, numVerts: 0},
				accents: null,
				lastVisualState: 0
			}
		];

		// Pass 1: Inward radial wash slots — 0.00 alpha at idle (Ware Large Area Rule), revealed only on active/inside!
		for (i in 0...zones.length) {
			var z = zones[i];
			var p = profiles[i];
			if (p.washW <= 0)
				continue;
			var segs = dashSets[i].length;
			batch = ensureCapacity(root, batch, quad, segs, remainingQuads);
			var startV = batch.numVertices;
			setQuadSplit(quad, CORE_ACTIVE, 0.0, CORE_ACTIVE, 0.0);
			emitStrip(batch, quad, z.x, z.y, Math.max(0.0, z.radius - p.washW), z.radius, segs);
			remainingQuads -= segs;
			slices[i].wash = {batch: batch, startVert: startV, numVerts: batch.numVertices - startV};
		}

		// Pass 2: Warm charcoal dual-polarity under-stroke (#14110F)
		for (i in 0...zones.length) {
			var z = zones[i];
			var p = profiles[i];
			var dashes = dashSets[i];
			var compCount = companionCount(z, dashes.length);
			var passQuads = dashes.length * STEPS + compCount * 2 + p.teethCount;
			batch = ensureCapacity(root, batch, quad, passQuads, remainingQuads);
			var startV = batch.numVertices;
			setQuadFlat(quad, INK_COLOR, armedInkAlpha(slices[i]));

			var slot = 2 * Math.PI / dashes.length;
			var maxPad = slot * (1.0 - p.fraction) * 0.36;
			var pad = ((p.inkW - p.coreW) * 0.5) / z.radius;
			if (pad > maxPad)
				pad = maxPad;
			for (d in dashes)
				emitTaperedArc(batch, quad, z.x, z.y, z.radius, p.inkW, d.from - pad, d.to + pad);

			if (compCount > 0) {
				var innerThick = slices[i].isBoss ? 3.2 : 3.6;
				var innerDuty = slices[i].isBoss ? 0.42 : 0.16;
				var inset = slices[i].isBoss ? 5.0 : (z.radius < 48.0 ? 5.5 : 7.5);
				emitCompanionDots(batch, quad, z, dashes.length, compCount, innerThick, innerDuty, inset);
			}

			if (p.teethCount > 0)
				emitTeeth(batch, quad, z, p.coreW, p.teethCount, p.teethDepth + 1.8, true);

			remainingQuads -= passQuads;
			slices[i].casing = {batch: batch, startVert: startV, numVerts: batch.numVertices - startV};
		}

		// Pass 3: Restrained mineral pigment cores
		for (i in 0...zones.length) {
			var z = zones[i];
			var p = profiles[i];
			var dashes = dashSets[i];
			var compCount = companionCount(z, dashes.length);
			var passQuads = dashes.length * STEPS + compCount * 2;
			batch = ensureCapacity(root, batch, quad, passQuads, remainingQuads);
			var startV = batch.numVertices;
			setQuadFlat(quad, Ring.tierColor(z.severity), armedCoreAlpha(slices[i]));

			for (d in dashes)
				emitTaperedArc(batch, quad, z.x, z.y, z.radius, p.coreW, d.from, d.to);

			if (compCount > 0) {
				var innerThick = slices[i].isBoss ? 1.2 : 1.5;
				var innerDuty = slices[i].isBoss ? 0.36 : 0.11;
				var inset = slices[i].isBoss ? 5.0 : (z.radius < 48.0 ? 5.5 : 7.5);
				emitCompanionDots(batch, quad, z, dashes.length, compCount, innerThick, innerDuty, inset);
			}

			remainingQuads -= passQuads;
			slices[i].core = {batch: batch, startVert: startV, numVerts: batch.numVertices - startV};
		}

		// Pass 4: Subtle cardinal inward ticks (Boss tarnished gold / Ambush tarnished brass)
		for (i in 0...zones.length) {
			var z = zones[i];
			var p = profiles[i];
			if (p.teethCount <= 0)
				continue;
			batch = ensureCapacity(root, batch, quad, p.teethCount, remainingQuads);
			var startV = batch.numVertices;
			setQuadFlat(quad, slices[i].isBoss ? BOSS_ACCENT_COLOR : Ring.COLOR_AMBUSH, slices[i].isBoss ? 0.82 : 0.72);
			emitTeeth(batch, quad, z, p.coreW, p.teethCount, p.teethDepth, false);
			remainingQuads -= p.teethCount;
			slices[i].accents = {batch: batch, startVert: startV, numVerts: batch.numVertices - startV};
		}

		if (batch.numVertices > 0)
			root.addChild(batch);
		quad.dispose();
		layer.addChild(root);
		starlingRoot = root;
	}

	function patchStarlingStates(items:Array<ZoneRuntime>):Void {
		var count = slices.length < items.length ? slices.length : items.length;
		var anyActive = false;
		var anyInside = false;

		for (i in 0...count) {
			var s = slices[i];
			var zr = items[i];
			var st = zr.status;
			var inside = st == ZoneTracker.STATUS_ARMED && zr.heroInsideNow;
			var packed = (st << 1) | (inside ? 1 : 0);
			if (st == ZoneTracker.STATUS_SPAWNED_ALIVE || inside) {
				anyActive = true;
				if (inside)
					anyInside = true;
			}
			if (packed == s.lastVisualState)
				continue;
			s.lastVisualState = packed;

			if (st == ZoneTracker.STATUS_TRIGGERED) {
				colorizeFlat(s.casing, INK_COLOR, INK_ALPHA_CLEARED);
				colorizeFlat(s.core, CORE_CLEARED, 0.24);
				if (s.wash != null)
					colorizeSplit(s.wash, CORE_CLEARED, 0.0, CORE_CLEARED, 0.0);
				if (s.accents != null)
					colorizeFlat(s.accents, CORE_CLEARED, 0.0);
			} else if (st == ZoneTracker.STATUS_SPAWNED_ALIVE) {
				colorizeFlat(s.casing, INK_COLOR, INK_ALPHA_ACTIVE);
				colorizeFlat(s.core, CORE_ACTIVE, 0.90);
				if (s.wash != null)
					colorizeSplit(s.wash, CORE_ACTIVE, 0.10, CORE_ACTIVE, 0.0);
				if (s.accents != null)
					colorizeFlat(s.accents, BOSS_ACCENT_COLOR, 0.92);
			} else if (inside) {
				colorizeFlat(s.casing, INK_COLOR, INK_ALPHA_ACTIVE);
				colorizeFlat(s.core, CORE_INSIDE, 0.88);
				if (s.wash != null)
					colorizeSplit(s.wash, CORE_INSIDE, 0.09, CORE_INSIDE, 0.0);
				if (s.accents != null)
					colorizeFlat(s.accents, s.isBoss ? BOSS_ACCENT_COLOR : CORE_INSIDE, 0.90);
			} else {
				colorizeFlat(s.casing, INK_COLOR, armedInkAlpha(s));
				colorizeFlat(s.core, Ring.tierColor(s.severity), armedCoreAlpha(s));
				if (s.wash != null)
					colorizeSplit(s.wash, CORE_ACTIVE, 0.0, CORE_ACTIVE, 0.0);
				if (s.accents != null)
					colorizeFlat(s.accents, s.isBoss ? BOSS_ACCENT_COLOR : Ring.COLOR_AMBUSH, s.isBoss ? 0.82 : 0.72);
			}
		}

		if (activeGlowBatch == null)
			return;
		activeGlowBatch.clear();
		if (!anyActive) {
			activeGlowBatch.visible = false;
			return;
		}
		activePulseRad = anyInside ? PULSE_INSIDE_RAD : PULSE_ACTIVE_RAD;
		var quad = new Quad(1, 1, 0xFFFFFF);
		quad.setStyle(new MeshStyle(), false);
		for (i in 0...count) {
			var zr = items[i];
			var st = zr.status;
			var inside = st == ZoneTracker.STATUS_ARMED && zr.heroInsideNow;
			if (st != ZoneTracker.STATUS_SPAWNED_ALIVE && !inside)
				continue;
			var z = zr.zone;
			var segs = Std.int(Math.max(16, Math.min(48, Math.round(z.radius * 0.32))));
			if (!activeGlowBatch.canAddMesh(quad, segs * 8))
				break;
			var col = st == ZoneTracker.STATUS_SPAWNED_ALIVE ? GLOW_ACTIVE_COLOR : GLOW_INSIDE_COLOR;
			setQuadSplit(quad, col, 0.24, col, 0.0);
			emitStrip(activeGlowBatch, quad, z.x, z.y, Math.max(0.0, z.radius - 10.0), z.radius, segs);
			setQuadSplit(quad, col, 0.0, col, 0.24);
			emitStrip(activeGlowBatch, quad, z.x, z.y, z.radius, z.radius + 7.0, segs);
		}
		quad.dispose();
		activeGlowBatch.visible = activeGlowBatch.numVertices > 0;
	}

	static inline function armedInkAlpha(s:ZoneSlice):Float {
		return s.isBoss ? INK_ALPHA_BOSS : (s.isUtility ? INK_ALPHA_UTIL : INK_ALPHA_ARMED);
	}

	static inline function armedCoreAlpha(s:ZoneSlice):Float {
		if (s.isBoss)
			return 0.80;
		if (s.severity >= Ring.SEVERITY_AMBUSH)
			return 0.74;
		if (s.severity >= Ring.SEVERITY_TRAP)
			return 0.72;
		return 0.60;
	}

	static function colorizeFlat(range:VertexRange, rgb:UInt, alpha:Float):Void {
		var b = range.batch;
		var end = range.startVert + range.numVerts;
		for (v in range.startVert...end) {
			b.setVertexColor(v, rgb);
			b.setVertexAlpha(v, alpha);
		}
	}

	static function colorizeSplit(range:VertexRange, outerRgb:UInt, outerAlpha:Float, innerRgb:UInt, innerAlpha:Float):Void {
		var b = range.batch;
		var end = range.startVert + range.numVerts;
		var v = range.startVert;
		while (v + 3 < end) {
			b.setVertexColor(v, outerRgb);
			b.setVertexAlpha(v, outerAlpha);
			b.setVertexColor(v + 1, outerRgb);
			b.setVertexAlpha(v + 1, outerAlpha);
			b.setVertexColor(v + 2, innerRgb);
			b.setVertexAlpha(v + 2, innerAlpha);
			b.setVertexColor(v + 3, innerRgb);
			b.setVertexAlpha(v + 3, innerAlpha);
			v += 4;
		}
	}

	static inline function companionCount(zone:Ring.Zone, outerDashes:Int):Int {
		if (zone.severity >= Ring.SEVERITY_BOSS)
			return zone.radius < 48.0 ? 8 : Std.int(Math.max(8, outerDashes));
		if (!zone.isAllHero)
			return 0;
		return zone.radius < 48.0 ? 4 : Std.int(Math.max(4, Math.floor(outerDashes * 0.5)));
	}

	static function ensureCapacity(root:Sprite, batch:MeshBatch, quad:Quad, neededQuads:Int, remainingQuads:Int):MeshBatch {
		if (batch.canAddMesh(quad, neededQuads * 4))
			return batch;
		if (batch.numVertices > 0)
			root.addChild(batch);
		return newBatch(remainingQuads > neededQuads ? remainingQuads : neededQuads);
	}

	static function newBatch(remainingQuads:Int):MeshBatch {
		var batch = new MeshBatch();
		batch.touchable = false;
		batch.setStyle(new MeshStyle(), false);
		var cap = remainingQuads > MAX_BATCH_QUADS ? MAX_BATCH_QUADS : remainingQuads;
		if (cap > 0) {
			batch.numVertices = cap * 4;
			batch.numVertices = 0;
		}
		return batch;
	}

	static inline function setQuadFlat(quad:Quad, color:UInt, alpha:Float):Void {
		for (i in 0...4) {
			quad.setVertexColor(i, color);
			quad.setVertexAlpha(i, alpha);
		}
	}

	static inline function setQuadSplit(quad:Quad, outerColor:UInt, outerAlpha:Float, innerColor:UInt, innerAlpha:Float):Void {
		quad.setVertexColor(0, outerColor);
		quad.setVertexAlpha(0, outerAlpha);
		quad.setVertexColor(1, outerColor);
		quad.setVertexAlpha(1, outerAlpha);
		quad.setVertexColor(2, innerColor);
		quad.setVertexAlpha(2, innerAlpha);
		quad.setVertexColor(3, innerColor);
		quad.setVertexAlpha(3, innerAlpha);
	}

	/** Emits a 4-quad tapered capsule/pill arc (zero extra vertices vs flat dashes). */
	static function emitTaperedArc(batch:MeshBatch, quad:Quad, cx:Float, cy:Float, radius:Float, thickness:Float, from:Float, to:Float):Void {
		var span = to - from;
		var halfBase = thickness * 0.5;
		var a0 = from;
		var c0 = Math.cos(a0);
		var s0 = Math.sin(a0);
		var hw0 = halfBase * CAP_W[0];
		var ro0 = radius + hw0;
		var ri0 = Math.max(0.0, radius - hw0);
		for (step in 1...STEPS + 1) {
			var a1 = from + span * CAP_T[step];
			var c1 = Math.cos(a1);
			var s1 = Math.sin(a1);
			var hw1 = halfBase * CAP_W[step];
			var ro1 = radius + hw1;
			var ri1 = Math.max(0.0, radius - hw1);
			quad.setVertexPosition(0, cx + ro0 * c0, cy + ro0 * s0);
			quad.setVertexPosition(1, cx + ro1 * c1, cy + ro1 * s1);
			quad.setVertexPosition(2, cx + ri0 * c0, cy + ri0 * s0);
			quad.setVertexPosition(3, cx + ri1 * c1, cy + ri1 * s1);
			batch.addMesh(quad, null, 1.0, null, true);
			c0 = c1;
			s0 = s1;
			ro0 = ro1;
			ri0 = ri1;
		}
	}

	static function emitStrip(batch:MeshBatch, quad:Quad, cx:Float, cy:Float, rIn:Float, rOut:Float, segs:Int):Void {
		var step = 2 * Math.PI / segs;
		var c0 = 1.0;
		var s0 = 0.0;
		for (k in 1...segs + 1) {
			var a1 = k == segs ? 0.0 : k * step;
			var c1 = Math.cos(a1);
			var s1 = Math.sin(a1);
			quad.setVertexPosition(0, cx + rOut * c0, cy + rOut * s0);
			quad.setVertexPosition(1, cx + rOut * c1, cy + rOut * s1);
			quad.setVertexPosition(2, cx + rIn * c0, cy + rIn * s0);
			quad.setVertexPosition(3, cx + rIn * c1, cy + rIn * s1);
			batch.addMesh(quad, null, 1.0, null, true);
			c0 = c1;
			s0 = s1;
		}
	}

	/** Emits inner companion ring dashes (Boss double-seal) or staggered dots (`PROXIMITY_ALL_HERO`). */
	static function emitCompanionDots(batch:MeshBatch, quad:Quad, z:Ring.Zone, outerDashes:Int, count:Int, thickness:Float, duty:Float, inset:Float):Void {
		var r = Math.max(8.0, z.radius - inset);
		var slot = 2 * Math.PI / count;
		var phase = Math.PI / outerDashes;
		var halfSpan = slot * duty * 0.5;
		var halfW = thickness * 0.5;
		var rOut = r + halfW;
		var rIn = Math.max(0.0, r - halfW);
		for (k in 0...count) {
			var mid = k * slot + phase;
			var a0 = mid - halfSpan;
			var a2 = mid + halfSpan;
			var c0 = Math.cos(a0);
			var s0 = Math.sin(a0);
			var cm = Math.cos(mid);
			var sm = Math.sin(mid);
			var c2 = Math.cos(a2);
			var s2 = Math.sin(a2);
			quad.setVertexPosition(0, z.x + rOut * c0, z.y + rOut * s0);
			quad.setVertexPosition(1, z.x + rOut * cm, z.y + rOut * sm);
			quad.setVertexPosition(2, z.x + rIn * c0, z.y + rIn * s0);
			quad.setVertexPosition(3, z.x + rIn * cm, z.y + rIn * sm);
			batch.addMesh(quad, null, 1.0, null, true);
			quad.setVertexPosition(0, z.x + rOut * cm, z.y + rOut * sm);
			quad.setVertexPosition(1, z.x + rOut * c2, z.y + rOut * s2);
			quad.setVertexPosition(2, z.x + rIn * cm, z.y + rIn * sm);
			quad.setVertexPosition(3, z.x + rIn * c2, z.y + rIn * s2);
			batch.addMesh(quad, null, 1.0, null, true);
		}
	}

	/** Emits subtle cardinal inward ticks (1 degenerate quad per tick). */
	static function emitTeeth(batch:MeshBatch, quad:Quad, z:Ring.Zone, coreW:Float, count:Int, depth:Float, isCasing:Bool):Void {
		var rBase = Math.max(4.0, z.radius - coreW * (isCasing ? 0.15 : 0.35));
		var rApex = Math.max(2.0, z.radius - depth);
		var halfBaseWorld = isCasing ? 5.2 : 3.2;
		var dAng = halfBaseWorld / rBase;
		var step = 2 * Math.PI / count;
		for (k in 0...count) {
			var a = k * step - Math.PI * 0.5;
			var aL = a - dAng;
			var aR = a + dAng;
			var ax = z.x + rApex * Math.cos(a);
			var ay = z.y + rApex * Math.sin(a);
			quad.setVertexPosition(0, z.x + rBase * Math.cos(aL), z.y + rBase * Math.sin(aL));
			quad.setVertexPosition(1, z.x + rBase * Math.cos(aR), z.y + rBase * Math.sin(aR));
			quad.setVertexPosition(2, ax, ay);
			quad.setVertexPosition(3, ax, ay);
			batch.addMesh(quad, null, 1.0, null, true);
		}
	}

	function buildOpenFL(zones:Array<Ring.Zone>, profiles:Array<Ring.TierProfile>, dashSets:Array<Array<Ring.Dash>>, items:Null<Array<ZoneRuntime>>):Void {
		var g = shape.graphics;
		g.clear();
		shape.visible = isVisible;

		for (i in 0...zones.length) {
			var zone = zones[i];
			var p = profiles[i];
			var dashes = dashSets[i];
			var st = (items != null && i < items.length) ? items[i].status : ZoneTracker.STATUS_ARMED;
			var cleared = st == ZoneTracker.STATUS_TRIGGERED;
			var spawned = st == ZoneTracker.STATUS_SPAWNED_ALIVE;

			var inkA = cleared ? INK_ALPHA_CLEARED : (p.isUtility ? INK_ALPHA_UTIL : INK_ALPHA_ARMED);
			var coreCol = cleared ? CORE_CLEARED : (spawned ? CORE_ACTIVE : Ring.tierColor(zone.severity));
			var coreA = cleared ? 0.24 : (spawned ? 0.90 : (p.isUtility ? 0.60 : 0.72));

			g.lineStyle(p.inkW, INK_COLOR, inkA);
			drawOpenFLDashes(g, zone, dashes);
			g.lineStyle(p.coreW, coreCol, coreA);
			drawOpenFLDashes(g, zone, dashes);
		}
	}

	static function drawOpenFLDashes(g:openfl.display.Graphics, zone:Ring.Zone, dashes:Array<Ring.Dash>):Void {
		for (dash in dashes) {
			var span = dash.to - dash.from;
			for (s in 0...STEPS + 1) {
				var a = dash.from + span * s / STEPS;
				var px = zone.x + zone.radius * Math.cos(a);
				var py = zone.y + zone.radius * Math.sin(a);
				if (s == 0)
					g.moveTo(px, py);
				else
					g.lineTo(px, py);
			}
		}
	}
}
