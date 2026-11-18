package mods.proximity_circle.ui;

import brain.starling.StarlingLayer;
import mods.proximity_circle.Ring;
import openfl.display.Shape;
import starling.display.MeshBatch;
import starling.display.Quad;
import starling.display.Sprite;
import starling.styles.MeshStyle;

/**
 * The floor's proximity trigger rings, built once in world units with no interior fill.
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

	/** Builds every zone's cased dashed ring in world units on `starlingLayer` (preferred) or `shape` (fallback). */
	public function build(zones:Array<Ring.Zone>, coreColor:UInt, starlingLayer:Null<StarlingLayer>):Void {
		clear();
		if (zones.length == 0)
			return;

		// Cache dash angles by rounded radius so zones of the same size reuse their arc layout.
		var byRadius = new Map<Int, Array<Ring.Dash>>();
		for (zone in zones) {
			var key = Math.round(zone.radius);
			if (!byRadius.exists(key))
				byRadius.set(key, Ring.dashesForRadius(zone.radius));
		}

		if (starlingLayer != null) {
			buildStarling(zones, byRadius, coreColor, starlingLayer);
			return;
		}

		buildOpenFL(zones, byRadius, coreColor);
	}

	function buildStarling(zones:Array<Ring.Zone>, byRadius:Map<Int, Array<Ring.Dash>>, coreColor:UInt, layer:StarlingLayer):Void {
		var totalDashes = 0;
		for (zone in zones)
			totalDashes += byRadius.get(Math.round(zone.radius)).length;
		var remainingQuads = totalDashes * 2 * STEPS;

		var root = new Sprite();
		root.touchable = false;
		root.visible = isVisible;

		var batch = newBatch(remainingQuads);
		var quad = new Quad(1, 1, HALO_COLOR);
		quad.setStyle(new MeshStyle(), false);
		setQuadAlpha(quad, HALO_ALPHA);
		var capWorld = (HALO_THICKNESS - CORE_THICKNESS) * 0.5;

		// 1. Deep obsidian contrast casing (#08080E) framing radial and angular edges of every dash.
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

		// 2. Biome-adaptive hazard core (#FF781F or #FF476C) with high opacity so casing does not muddy it.
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

		if (batch.numVertices > 0)
			root.addChild(batch);
		quad.dispose();
		layer.addChild(root);
		starlingRoot = root;
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

	function buildOpenFL(zones:Array<Ring.Zone>, byRadius:Map<Int, Array<Ring.Dash>>, coreColor:UInt):Void {
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
	}
}
