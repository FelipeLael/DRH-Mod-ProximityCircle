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
	var isUtility:Bool;
	var isBoss:Bool;
	var wash:Null<VertexRange>;
	var casing:VertexRange;
	var core:VertexRange;
	var accents:Null<VertexRange>;
	var lastVisualState:Int;
}

/**
 * The floor's proximity trigger rings, built once in world units with no center fill.
 *
 * Uses DRH's warm espresso comic ink (`0x120A04`), tapered hand-inked pill dashes, 2-tone cel
 * shading (`0xFF7EB8` crest -> `0xE62E7A` outer edge), feathered inward rim wash, redundant
 * threat-tier geometry (Boss crown teeth, Ambush cardinal teeth, All-Hero inner companion dots),
 * and live floor state demotion/pulsing synchronized with `ZoneTracker` at 0 steady-state VBO uploads.
 */
class Circles {
	/** Warm espresso comic ink matching DRH props, trees, pickups, and `TrapHud.COL_INK`. */
	static inline final INK_COLOR:UInt = 0x120A04;

	static inline final INK_ALPHA_ARMED:Float = 0.88;

	static inline final INK_ALPHA_ACTIVE:Float = 0.94;

	static inline final INK_ALPHA_CLEARED:Float = 0.22;

	/** Armed 2-tone rose-magenta cel pair (mean hue #FF4794, H=335 deg). */
	static inline final CORE_ARMED_IN:UInt = 0xFF7EB8;

	static inline final CORE_ARMED_OUT:UInt = 0xE62E7A;

	static inline final CORE_UTIL_IN:UInt = 0xFFC0DC;

	static inline final CORE_UTIL_OUT:UInt = 0xE57AA8;

	/** Stepping-inside brightened rose pair. */
	static inline final CORE_INSIDE_IN:UInt = 0xFFB8D9;

	static inline final CORE_INSIDE_OUT:UInt = 0xFF4794;

	/** Active / spawned / firing molten gold-coral pair (+0.43 luminance jump, CVD-safe). */
	static inline final CORE_SPAWN_IN:UInt = 0xFFE066;

	static inline final CORE_SPAWN_OUT:UInt = 0xFF4D2E;

	/** Cleared / triggered "spent chalk trace" warm stone-bronze pair. */
	static inline final CORE_CLEAR_IN:UInt = 0xB39B82;

	static inline final CORE_CLEAR_OUT:UInt = 0x8C735B;

	/** Threat-tier inward tooth fills. */
	static inline final BOSS_TEETH_COLOR:UInt = 0xFFD24C;

	static inline final SPAWN_TEETH_COLOR:UInt = 0xFFE680;

	/** Active floor halo colors & pulse speeds. */
	static inline final GLOW_INSIDE_COLOR:UInt = 0xFFC4DF;

	static inline final GLOW_SPAWN_COLOR:UInt = 0xFFCC33;

	static inline final PULSE_INSIDE_RAD:Float = 0.0113097; // 1.8 Hz

	static inline final PULSE_SPAWN_RAD:Float = 0.0087965; // 1.4 Hz

	static inline final STEPS = 4;

	static inline final MAX_BATCH_QUADS = 16383;

	/** 5-station capsule taper along each 4-quad dash: flowing comic pills at zero extra vertices. */
	static final CAP_T:Array<Float> = [0.0, 0.16, 0.50, 0.84, 1.0];

	static final CAP_W:Array<Float> = [0.42, 1.0, 1.0, 1.0, 0.42];

	public var shape(default, null):Shape;

	var starlingRoot:Null<Sprite> = null;

	var activeGlowBatch:Null<MeshBatch> = null;

	var slices:Array<ZoneSlice> = [];

	var openflZones:Array<Ring.Zone> = [];

	var activeCoreColor:UInt = Ring.COLOR_ROSE;

	var lastRevision:Int = -1;

	var activePulseRad:Float = PULSE_SPAWN_RAD;

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

	/** Builds every zone's comic-inked ring in world units on `starlingLayer` (preferred) or `shape`. */
	public function build(zones:Array<Ring.Zone>, coreColor:UInt, starlingLayer:Null<StarlingLayer>):Void {
		clear();
		activeCoreColor = coreColor;
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
	 * Synchronizes live floor ring visuals with `ZoneTracker` (`STATUS_ARMED`, `heroInsideNow`,
	 * `STATUS_SPAWNED_ALIVE`, `STATUS_TRIGGERED`). Returns in O(1) on steady idle frames.
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
				activeGlowBatch.alpha = 0.35 + 0.65 * wave;
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
				isUtility: profiles[i].isUtility,
				isBoss: zones[i].severity >= Ring.SEVERITY_BOSS,
				wash: null,
				casing: {batch: batch, startVert: 0, numVerts: 0},
				core: {batch: batch, startVert: 0, numVerts: 0},
				accents: null,
				lastVisualState: 0
			}
		];

		// Pass 1: Soft feathered inward rim wash (grounding + Gestalt inside/outside polarity)
		for (i in 0...zones.length) {
			var z = zones[i];
			var p = profiles[i];
			if (p.washW <= 0)
				continue;
			var segs = dashSets[i].length;
			batch = ensureCapacity(root, batch, quad, segs, remainingQuads);
			var startV = batch.numVertices;
			setQuadSplit(quad, Ring.COLOR_ROSE, 0.14, Ring.COLOR_ROSE, 0.0);
			emitStrip(batch, quad, z.x, z.y, Math.max(0.0, z.radius - p.washW), z.radius, segs);
			remainingQuads -= segs;
			slices[i].wash = {batch: batch, startVert: startV, numVerts: batch.numVertices - startV};
		}

		// Pass 2: Warm espresso comic ink casing (outer pills + All-Hero inner dots + tier teeth casings)
		for (i in 0...zones.length) {
			var z = zones[i];
			var p = profiles[i];
			var dashes = dashSets[i];
			var compCount = companionCount(z, dashes.length);
			var passQuads = dashes.length * STEPS + compCount * 2 + p.teethCount;
			batch = ensureCapacity(root, batch, quad, passQuads, remainingQuads);
			var startV = batch.numVertices;
			setQuadFlat(quad, INK_COLOR, INK_ALPHA_ARMED);

			var slot = 2 * Math.PI / dashes.length;
			var maxPad = slot * (1.0 - p.fraction) * 0.38;
			var pad = ((p.inkW - p.coreW) * 0.5) / z.radius;
			if (pad > maxPad)
				pad = maxPad;
			for (d in dashes)
				emitTaperedArc(batch, quad, z.x, z.y, z.radius, p.inkW, d.from - pad, d.to + pad);

			if (compCount > 0)
				emitCompanionDots(batch, quad, z, dashes.length, compCount, 4.6, 0.16);

			if (p.teethCount > 0)
				emitTeeth(batch, quad, z, p.coreW, p.teethCount, p.teethDepth + 2.2, true);

			remainingQuads -= passQuads;
			slices[i].casing = {batch: batch, startVert: startV, numVerts: batch.numVertices - startV};
		}

		// Pass 3: 2-tone cel-shaded core pills + All-Hero companion dot cores
		for (i in 0...zones.length) {
			var z = zones[i];
			var p = profiles[i];
			var dashes = dashSets[i];
			var compCount = companionCount(z, dashes.length);
			var passQuads = dashes.length * STEPS + compCount * 2;
			batch = ensureCapacity(root, batch, quad, passQuads, remainingQuads);
			var startV = batch.numVertices;
			if (p.isUtility)
				setQuadSplit(quad, CORE_UTIL_OUT, 0.82, CORE_UTIL_IN, 0.82);
			else
				setQuadSplit(quad, CORE_ARMED_OUT, 0.95, CORE_ARMED_IN, 0.95);

			for (d in dashes)
				emitTaperedArc(batch, quad, z.x, z.y, z.radius, p.coreW, d.from, d.to);

			if (compCount > 0)
				emitCompanionDots(batch, quad, z, dashes.length, compCount, 1.8, 0.11);

			remainingQuads -= passQuads;
			slices[i].core = {batch: batch, startVert: startV, numVerts: batch.numVertices - startV};
		}

		// Pass 4: Inward perimeter teeth fills (Boss gold crown / Ambush luminous rose)
		for (i in 0...zones.length) {
			var z = zones[i];
			var p = profiles[i];
			if (p.teethCount <= 0)
				continue;
			batch = ensureCapacity(root, batch, quad, p.teethCount, remainingQuads);
			var startV = batch.numVertices;
			setQuadFlat(quad, slices[i].isBoss ? BOSS_TEETH_COLOR : CORE_ARMED_IN, 0.96);
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
				colorizeSplit(s.core, CORE_CLEAR_OUT, 0.28, CORE_CLEAR_IN, 0.28);
				if (s.wash != null)
					colorizeSplit(s.wash, CORE_CLEAR_OUT, 0.0, CORE_CLEAR_OUT, 0.0);
				if (s.accents != null)
					colorizeFlat(s.accents, CORE_CLEAR_OUT, 0.0);
			} else if (st == ZoneTracker.STATUS_SPAWNED_ALIVE) {
				colorizeFlat(s.casing, INK_COLOR, INK_ALPHA_ACTIVE);
				colorizeSplit(s.core, CORE_SPAWN_OUT, 1.0, CORE_SPAWN_IN, 1.0);
				if (s.wash != null)
					colorizeSplit(s.wash, 0xFFAA22, 0.22, 0xFFAA22, 0.0);
				if (s.accents != null)
					colorizeFlat(s.accents, SPAWN_TEETH_COLOR, 1.0);
			} else if (inside) {
				colorizeFlat(s.casing, INK_COLOR, INK_ALPHA_ACTIVE);
				colorizeSplit(s.core, CORE_INSIDE_OUT, 1.0, CORE_INSIDE_IN, 1.0);
				if (s.wash != null)
					colorizeSplit(s.wash, CORE_ARMED_IN, 0.24, CORE_ARMED_IN, 0.0);
				if (s.accents != null)
					colorizeFlat(s.accents, s.isBoss ? BOSS_TEETH_COLOR : CORE_INSIDE_IN, 1.0);
			} else {
				colorizeFlat(s.casing, INK_COLOR, INK_ALPHA_ARMED);
				if (s.isUtility)
					colorizeSplit(s.core, CORE_UTIL_OUT, 0.82, CORE_UTIL_IN, 0.82);
				else
					colorizeSplit(s.core, CORE_ARMED_OUT, 0.95, CORE_ARMED_IN, 0.95);
				if (s.wash != null)
					colorizeSplit(s.wash, Ring.COLOR_ROSE, 0.14, Ring.COLOR_ROSE, 0.0);
				if (s.accents != null)
					colorizeFlat(s.accents, s.isBoss ? BOSS_TEETH_COLOR : CORE_ARMED_IN, 0.96);
			}
		}

		if (activeGlowBatch == null)
			return;
		activeGlowBatch.clear();
		if (!anyActive) {
			activeGlowBatch.visible = false;
			return;
		}
		activePulseRad = anyInside ? PULSE_INSIDE_RAD : PULSE_SPAWN_RAD;
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
			var col = st == ZoneTracker.STATUS_SPAWNED_ALIVE ? GLOW_SPAWN_COLOR : GLOW_INSIDE_COLOR;
			// Inner feathered halo (r -> r - 14) + outer feathered halo (r + 10 -> r)
			setQuadSplit(quad, col, 0.50, col, 0.0);
			emitStrip(activeGlowBatch, quad, z.x, z.y, Math.max(0.0, z.radius - 14.0), z.radius, segs);
			setQuadSplit(quad, col, 0.0, col, 0.50);
			emitStrip(activeGlowBatch, quad, z.x, z.y, z.radius, z.radius + 10.0, segs);
		}
		quad.dispose();
		activeGlowBatch.visible = activeGlowBatch.numVertices > 0;
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

	/** Emits a continuous annular strip (inward wash or feathered active halo). */
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

	/** Emits staggered inner companion dots for `PROXIMITY_ALL_HERO` party-gather rings. */
	static function emitCompanionDots(batch:MeshBatch, quad:Quad, z:Ring.Zone, outerDashes:Int, count:Int, thickness:Float, duty:Float):Void {
		var r = Math.max(8.0, z.radius - (z.radius < 48.0 ? 6.0 : 8.0));
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
			// 2 quads per short dot
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

	/** Emits inward-pointing triangular teeth (1 degenerate quad per tooth) around the perimeter. */
	static function emitTeeth(batch:MeshBatch, quad:Quad, z:Ring.Zone, coreW:Float, count:Int, depth:Float, isCasing:Bool):Void {
		var rBase = Math.max(4.0, z.radius - coreW * (isCasing ? 0.15 : 0.35));
		var rApex = Math.max(2.0, z.radius - depth);
		var halfBaseWorld = (isCasing ? 6.4 : 4.2);
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

			var inkA = cleared ? INK_ALPHA_CLEARED : INK_ALPHA_ARMED;
			var coreCol = cleared ? CORE_CLEAR_OUT : (spawned ? CORE_SPAWN_IN : (p.isUtility ? CORE_UTIL_OUT : activeCoreColor));
			var coreA = cleared ? 0.28 : (p.isUtility ? 0.82 : 0.95);

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
