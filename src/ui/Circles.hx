package mods.proximity_circle.ui;

import brain.starling.StarlingLayer;
import mods.proximity_circle.Ring;
import openfl.display.Shape;
import starling.display.MeshBatch;
import starling.display.Quad;
import starling.display.Sprite;
import starling.styles.MeshStyle;

/**
 * The floor's rings, built once in world units with no interior fill.
 *
 * When Starling is active, the rings are batched into GPU `MeshBatch` geometry (`touchable = false`)
 * on a world `StarlingLayer` directly on the dungeon floor—beneath heroes, monsters, walls, room fades
 * and the HUD, with zero OpenFL `nativeOverlay` hit-testing or click blocking. An OpenFL `Shape`
 * fallback is kept if Starling is unavailable.
 */
class Circles {
	static inline final CORE_ALPHA:Float = 0.95;

	/** Crisp world-unit core stroke leaving floor hazards and decals inside completely unoccluded. */
	static inline final CORE_THICKNESS:Float = 3.6;

	/** Deep obsidian casing (#08080E) framing all four sides of each dash for >= 3:1 contrast on every biome. */
	static inline final HALO_COLOR:UInt = 0x08080E;

	static inline final HALO_ALPHA:Float = 0.85;

	static inline final HALO_THICKNESS:Float = 8.0;

	/** Segments per dash's arc: seamless annular quads with shared edges (no gaps, no double-alpha joints). */
	static inline final STEPS = 4;

	/** Half-diagonal of the diamond hazard frame around a destructible-prop trap (world units). */
	static inline final PROP_DIAMOND_RADIUS:Float = 26.0;

	/** Half-extent of the inner "do not destroy" X mark inside the diamond. */
	static inline final PROP_CROSS_RADIUS:Float = 9.0;

	/** Quads emitted per prop trap across halo + core passes: 2 passes * (4 diamond edges + 2 X strokes). */
	static inline final QUADS_PER_PROP_TRAP = 12;

	/** Max quads fitting within Starling's 65,535-vertex `MeshBatch` limit (`floor(65535 / 4)`). */
	static inline final MAX_BATCH_QUADS = 16383;

	public var shape(default, null):Shape;

	var starlingRoot:Null<Sprite> = null;

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
		if (starlingRoot != null) {
			if (starlingRoot.parent != null)
				starlingRoot.removeFromParent(true);
			else
				starlingRoot.dispose();
			starlingRoot = null;
		}
	}

	/** Builds every zone's cased dashed ring and prop-trap diamond+X marker on `starlingLayer` or `shape`. */
	public function build(zones:Array<Ring.Zone>, propTraps:Array<Ring.PropTrap>, coreColor:UInt, starlingLayer:Null<StarlingLayer>):Void {
		clear();
		if (zones.length == 0 && propTraps.length == 0)
			return;

		// Cache dash angles by rounded radius so zones of the same size reuse their arc layout.
		var byRadius = new Map<Int, Array<Ring.Dash>>();
		for (zone in zones) {
			var key = Math.round(zone.radius);
			if (!byRadius.exists(key))
				byRadius.set(key, Ring.dashesForRadius(zone.radius));
		}

		if (starlingLayer != null) {
			buildStarling(zones, propTraps, byRadius, coreColor, starlingLayer);
			return;
		}

		buildOpenFL(zones, propTraps, byRadius, coreColor);
	}

	function buildStarling(zones:Array<Ring.Zone>, propTraps:Array<Ring.PropTrap>, byRadius:Map<Int, Array<Ring.Dash>>, coreColor:UInt,
			layer:StarlingLayer):Void {
		var totalDashes = 0;
		for (zone in zones)
			totalDashes += byRadius.get(Math.round(zone.radius)).length;
		var remainingQuads = totalDashes * 2 * STEPS + propTraps.length * QUADS_PER_PROP_TRAP;

		var root = new Sprite();
		root.touchable = false;
		root.visible = isVisible;

		var batch = newBatch(remainingQuads);
		var quad = new Quad(1, 1, HALO_COLOR);
		quad.setStyle(new MeshStyle(), false);
		setQuadAlpha(quad, HALO_ALPHA);
		var capWorld = (HALO_THICKNESS - CORE_THICKNESS) * 0.5;

		// 1. Deep obsidian contrast casing (#08080E) for rings and prop-trap diamond+X markers.
		for (zone in zones) {
			var dashes = byRadius.get(Math.round(zone.radius));
			var slot = 2 * Math.PI / dashes.length;
			var maxPad = slot * (1.0 - Ring.DASH_FRACTION) * 0.42;
			var pad = capWorld / zone.radius;
			if (pad > maxPad)
				pad = maxPad;
			var rIn = Math.max(0.0, zone.radius - HALO_THICKNESS * 0.5);
			var rOut = zone.radius + HALO_THICKNESS * 0.5;
			for (dash in dashes) {
				batch = emitArc(root, batch, quad, zone.x, zone.y, rIn, rOut, dash.from - pad, dash.to + pad, remainingQuads);
				remainingQuads -= STEPS;
			}
		}
		for (prop in propTraps) {
			batch = emitPropMarker(root, batch, quad, prop.x, prop.y, HALO_THICKNESS, capWorld, remainingQuads);
			remainingQuads -= 6;
		}

		// 2. High-opacity cores: biome-adaptive hue for proximity rings, amber-gold (#FFD028) for prop traps.
		quad.color = coreColor;
		setQuadAlpha(quad, CORE_ALPHA);
		for (zone in zones) {
			var dashes = byRadius.get(Math.round(zone.radius));
			var rIn = Math.max(0.0, zone.radius - CORE_THICKNESS * 0.5);
			var rOut = zone.radius + CORE_THICKNESS * 0.5;
			for (dash in dashes) {
				batch = emitArc(root, batch, quad, zone.x, zone.y, rIn, rOut, dash.from, dash.to, remainingQuads);
				remainingQuads -= STEPS;
			}
		}
		if (propTraps.length > 0) {
			quad.color = Ring.COLOR_PROP_TRAP;
			for (prop in propTraps) {
				batch = emitPropMarker(root, batch, quad, prop.x, prop.y, CORE_THICKNESS, 0.0, remainingQuads);
				remainingQuads -= 6;
			}
		}

		if (batch.numVertices > 0)
			root.addChild(batch);
		quad.dispose();
		layer.addChild(root);
		starlingRoot = root;
	}

	static function emitPropMarker(root:Sprite, batch:MeshBatch, quad:Quad, cx:Float, cy:Float, thickness:Float, capExtend:Float,
			remainingQuads:Int):MeshBatch {
		var r = PROP_DIAMOND_RADIUS;
		var x = PROP_CROSS_RADIUS + capExtend * 0.7071;
		// 4 diamond edges + 2 inner X strokes
		batch = emitSegment(root, batch, quad, cx, cy - r, cx + r, cy, thickness, capExtend, remainingQuads);
		batch = emitSegment(root, batch, quad, cx + r, cy, cx, cy + r, thickness, capExtend, remainingQuads - 1);
		batch = emitSegment(root, batch, quad, cx, cy + r, cx - r, cy, thickness, capExtend, remainingQuads - 2);
		batch = emitSegment(root, batch, quad, cx - r, cy, cx, cy - r, thickness, capExtend, remainingQuads - 3);
		batch = emitSegment(root, batch, quad, cx - x, cy - x, cx + x, cy + x, thickness, 0.0, remainingQuads - 4);
		return emitSegment(root, batch, quad, cx + x, cy - x, cx - x, cy + x, thickness, 0.0, remainingQuads - 5);
	}

	static function emitSegment(root:Sprite, batch:MeshBatch, quad:Quad, x1:Float, y1:Float, x2:Float, y2:Float, thickness:Float, capExtend:Float,
			remainingQuads:Int):MeshBatch {
		var dx = x2 - x1;
		var dy = y2 - y1;
		var len = Math.sqrt(dx * dx + dy * dy);
		if (len <= 0.0001)
			return batch;
		var ux = dx / len;
		var uy = dy / len;
		var half = thickness * 0.5;
		var nx = -uy * half;
		var ny = ux * half;
		var sx = x1 - ux * capExtend;
		var sy = y1 - uy * capExtend;
		var ex = x2 + ux * capExtend;
		var ey = y2 + uy * capExtend;
		quad.setVertexPosition(0, sx + nx, sy + ny);
		quad.setVertexPosition(1, ex + nx, ey + ny);
		quad.setVertexPosition(2, sx - nx, sy - ny);
		quad.setVertexPosition(3, ex - nx, ey - ny);
		if (!batch.canAddMesh(quad, 4)) {
			root.addChild(batch);
			batch = newBatch(remainingQuads);
		}
		batch.addMesh(quad, null, 1.0, null, true);
		return batch;
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

	static inline function setQuadAlpha(quad:Quad, alpha:Float):Void {
		for (i in 0...4)
			quad.setVertexAlpha(i, alpha);
	}

	static function emitArc(root:Sprite, batch:MeshBatch, quad:Quad, cx:Float, cy:Float, rIn:Float, rOut:Float, from:Float, to:Float,
			remainingQuads:Int):MeshBatch {
		var span = to - from;
		var c0 = Math.cos(from);
		var s0 = Math.sin(from);
		for (step in 1...STEPS + 1) {
			var a1 = from + span * step / STEPS;
			var c1 = Math.cos(a1);
			var s1 = Math.sin(a1);
			quad.setVertexPosition(0, cx + rOut * c0, cy + rOut * s0);
			quad.setVertexPosition(1, cx + rOut * c1, cy + rOut * s1);
			quad.setVertexPosition(2, cx + rIn * c0, cy + rIn * s0);
			quad.setVertexPosition(3, cx + rIn * c1, cy + rIn * s1);
			if (!batch.canAddMesh(quad, 4)) {
				root.addChild(batch);
				batch = newBatch(remainingQuads - (step - 1));
			}
			batch.addMesh(quad, null, 1.0, null, true);
			c0 = c1;
			s0 = s1;
		}
		return batch;
	}

	function buildOpenFL(zones:Array<Ring.Zone>, propTraps:Array<Ring.PropTrap>, byRadius:Map<Int, Array<Ring.Dash>>, coreColor:UInt):Void {
		var g = shape.graphics;
		shape.visible = isVisible;

		g.lineStyle(HALO_THICKNESS, HALO_COLOR, HALO_ALPHA);
		for (zone in zones) {
			var dashes = byRadius.get(Math.round(zone.radius));
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
		for (prop in propTraps)
			drawOpenFLProp(g, prop.x, prop.y);

		g.lineStyle(CORE_THICKNESS, coreColor, CORE_ALPHA);
		for (zone in zones) {
			var dashes = byRadius.get(Math.round(zone.radius));
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
		if (propTraps.length > 0) {
			g.lineStyle(CORE_THICKNESS, Ring.COLOR_PROP_TRAP, CORE_ALPHA);
			for (prop in propTraps)
				drawOpenFLProp(g, prop.x, prop.y);
		}
	}

	static function drawOpenFLProp(g:openfl.display.Graphics, cx:Float, cy:Float):Void {
		var r = PROP_DIAMOND_RADIUS;
		var x = PROP_CROSS_RADIUS;
		g.moveTo(cx, cy - r);
		g.lineTo(cx + r, cy);
		g.lineTo(cx, cy + r);
		g.lineTo(cx - r, cy);
		g.lineTo(cx, cy - r);
		g.moveTo(cx - x, cy - x);
		g.lineTo(cx + x, cy + x);
		g.moveTo(cx + x, cy - x);
		g.lineTo(cx - x, cy + x);
	}
}
