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
	static inline final COLOR:UInt = 0xF2D27A;

	static inline final ALPHA:Float = 0.9;

	/** In world units, so the line scales with the camera like the floor does. */
	static inline final THICKNESS:Float = 4;

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
		g.lineStyle(THICKNESS, COLOR, ALPHA);
		var dashes = Ring.dashes();
		for (zone in zones) {
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
