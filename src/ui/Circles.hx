package mods.proximity_circle.ui;

import mods.proximity_circle.Ring;
import openfl.display.Shape;

/**
 * The floor's rings, drawn once in world units into one shape.
 *
 * The shape is added to the game's world layer, not to the overlay, so the camera moves it with the
 * floor and every popup and menu draws above it. Nothing is redrawn per frame.
 */
class Circles {
	/** Vivid coral-vermilion (#FF5238): clear hazard telegraph, high luminance on dark floors, CVD-safe. */
	static inline final COLOR:UInt = 0xFF5238;

	static inline final ALPHA:Float = 0.78;

	/** Thin world-unit stroke so floor cues and characters underneath stay readable. */
	static inline final THICKNESS:Float = 3.0;

	/** Translucent dark halo underneath for dual-contrast separation on bright or fiery floors. */
	static inline final HALO_COLOR:UInt = 0x000000;

	static inline final HALO_ALPHA:Float = 0.48;

	static inline final HALO_THICKNESS:Float = 5.5;

	/** Segments per dash's arc: enough to look round at any zoom. */
	static inline final STEPS = 4;

	public var shape(default, null):Shape;

	public function new() {
		shape = new Shape();
	}

	public function setVisible(on:Bool):Void {
		shape.visible = on;
	}

	public function clear():Void {
		shape.graphics.clear();
	}

	/** Draws every zone's ring, in world units. Called once per floor, never per frame. */
	public function build(zones:Array<Ring.Zone>):Void {
		var g = shape.graphics;
		g.clear();

		// Cache dash angles by radius so zones of the same size reuse their arc layout
		var byRadius = new Map<Int, Array<Ring.Dash>>();
		for (zone in zones) {
			var key = Math.round(zone.radius);
			if (!byRadius.exists(key))
				byRadius.set(key, Ring.dashesForRadius(zone.radius));
		}

		// 1. Thin translucent dark halo underneath for contrast across light and fiery tiles
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

		// 2. Main dashed hazard ring in luminous coral-vermilion (#FF5238)
		g.lineStyle(THICKNESS, COLOR, ALPHA);
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
