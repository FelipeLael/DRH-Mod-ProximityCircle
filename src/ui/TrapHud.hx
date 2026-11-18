package mods.proximity_circle.ui;

import brain.assetRepository.AssetLoadingComponent;
import brain.assetRepository.SwfAsset;
import distributedObjects.DistributedDungeonFloor;
import facade.DBFacade;
import mods.proximity_circle.Ring;
import openfl.display.MovieClip;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.filters.GlowFilter;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;

private typedef ThreatItem = {
	var isProp:Bool;
	var inDanger:Bool;
	var severity:Int;
	var dist:Float;
	var count:Int;
	var titleTag:String;
	var outcome:String;
	var actionVerb:String;
	var key:String;
}

private typedef RowView = {
	var badge:TextField;
	var outcome:TextField;
}

/**
 * Progressive-disclosure proximity HUD card rendered on `ctx.overlay` using DRH's in-game
 * `Fat Rhino PB` and `Futura Bold` fonts (`db_UI_town.swf`).
 *
 * Stays hidden when nothing is near to avoid banner blindness, and surfaces grouped, severity-
 * ranked warnings only while the player approaches or stands on a ring / near a shiny trap prop.
 */
class TrapHud {
	static inline final TOWN_SWF = "Resources/Art2D/UI/db_UI_town.swf";

	static inline final CARD_WIDTH:Float = 480.0;

	static inline final CARD_Y:Float = 92.0;

	static inline final HEADER_H:Float = 28.0;

	static inline final ROW_H:Float = 32.0;

	static inline final ROW_GAP:Float = 4.0;

	static inline final FOOTER_H:Float = 18.0;

	static inline final PAD_X:Float = 10.0;

	static inline final PAD_BOTTOM:Float = 8.0;

	static inline final MAX_ROWS:Int = 3;

	/** World-unit detection radii with +20 px exit hysteresis to stop border flicker. */
	static inline final RING_NEAR_ENTER:Float = 165.0;

	static inline final RING_NEAR_EXIT:Float = 185.0;

	static inline final PROP_NEAR_ENTER:Float = 200.0;

	static inline final PROP_NEAR_EXIT:Float = 220.0;

	static inline final PROP_DANGER_DIST:Float = 75.0;

	static inline final FADE_IN_SPEED:Float = 0.0085; // ~120ms

	static inline final FADE_OUT_SPEED:Float = 0.0065; // ~155ms

	static inline final DANGER_PULSE_RAD_PER_MS:Float = 0.0075398; // 1.2 Hz

	var root:Sprite;

	var bgShape:Shape;

	var dangerBorder:Shape;

	var badgesShape:Shape;

	var labelsLayer:Sprite;

	var headerLabel:TextField;

	var pillLabel:TextField;

	var moreLabel:TextField;

	var rowViews:Array<RowView> = [];

	var loader:Null<AssetLoadingComponent> = null;

	var titleFont:String = "_sans";

	var bodyFont:String = "_sans";

	var embedded:Bool = false;

	var shownAlpha:Float = 0.0;

	var lastFrameMs:Int = 0;

	var wasShown:Bool = false;

	var lastSignature:String = "";

	var lastCardHeight:Float = 0.0;

	var lastDanger:Bool = false;

	var activeCoreColor:UInt = Ring.COLOR_FLAME;

	var currentGroups:Array<ThreatItem> = [];

	public function new(overlay:Sprite, facade:Null<DBFacade>) {
		root = new Sprite();
		root.mouseEnabled = false;
		root.mouseChildren = false;
		root.tabEnabled = false;
		root.visible = false;
		root.alpha = 0.0;

		bgShape = new Shape();
		dangerBorder = new Shape();
		badgesShape = new Shape();
		labelsLayer = new Sprite();
		labelsLayer.mouseEnabled = false;
		labelsLayer.mouseChildren = false;
		labelsLayer.filters = [new GlowFilter(0x08080E, 1, 3.5, 3.5, 5)];

		root.addChild(bgShape);
		root.addChild(dangerBorder);
		root.addChild(badgesShape);
		root.addChild(labelsLayer);

		headerLabel = makeField(true, 14, 0xFFF1D0, 290, TextFormatAlign.LEFT);
		headerLabel.x = PAD_X;
		headerLabel.y = 4;
		labelsLayer.addChild(headerLabel);

		pillLabel = makeField(false, 10, 0xFFFFFF, 96, TextFormatAlign.CENTER);
		pillLabel.x = CARD_WIDTH - PAD_X - 96;
		pillLabel.y = 6;
		labelsLayer.addChild(pillLabel);

		for (i in 0...MAX_ROWS) {
			var rowY = HEADER_H + 4 + i * (ROW_H + ROW_GAP);
			var tag = makeField(false, 11, 0xFFD0A0, 152, TextFormatAlign.LEFT);
			tag.x = PAD_X + 34;
			tag.y = rowY + 7;
			tag.visible = false;
			labelsLayer.addChild(tag);

			var out = makeField(false, 12, 0xFFF1D0, CARD_WIDTH - (PAD_X * 2 + 186), TextFormatAlign.RIGHT);
			out.x = PAD_X + 184;
			out.y = rowY + 6;
			out.visible = false;
			labelsLayer.addChild(out);

			rowViews.push({badge: tag, outcome: out});
		}

		moreLabel = makeField(false, 10, 0xB9AEC7, CARD_WIDTH - PAD_X * 2, TextFormatAlign.RIGHT);
		moreLabel.x = PAD_X;
		moreLabel.visible = false;
		labelsLayer.addChild(moreLabel);

		if (overlay != null)
			overlay.addChild(root);

		if (facade != null) {
			loader = new AssetLoadingComponent(facade);
			loader.getSwfAsset(DBFacade.buildFullDownloadPath(TOWN_SWF), onTownSwf);
		}
	}

	function onTownSwf(asset:SwfAsset):Void {
		if (asset == null)
			return;
		var type:Dynamic = asset.getClass("popup");
		var sample:MovieClip = type == null ? null : cast ASCompat.createInstance(type, []);
		if (sample == null)
			return;
		var title = Std.downcast(sample.getChildByName("title_label"), TextField);
		var body = Std.downcast(sample.getChildByName("message_label"), TextField);
		if (title == null || body == null)
			return;
		titleFont = title.defaultTextFormat.font;
		bodyFont = body.defaultTextFormat.font;
		embedded = title.embedFonts;
		applyFonts();
	}

	function applyFonts():Void {
		reformat(headerLabel, true, 14, TextFormatAlign.LEFT);
		reformat(pillLabel, false, 10, TextFormatAlign.CENTER);
		reformat(moreLabel, false, 10, TextFormatAlign.RIGHT);
		for (rv in rowViews) {
			reformat(rv.badge, false, 11, TextFormatAlign.LEFT);
			reformat(rv.outcome, false, 12, TextFormatAlign.RIGHT);
		}
	}

	public function reset():Void {
		wasShown = false;
		shownAlpha = 0.0;
		lastSignature = "";
		lastDanger = false;
		currentGroups = [];
		root.visible = false;
		root.alpha = 0.0;
	}

	public function dispose():Void {
		reset();
		if (root.parent != null)
			root.parent.removeChild(root);
		if (loader != null) {
			loader.destroy();
			loader = null;
		}
	}

	public function update(nowMs:Int, viewWidth:Float, viewHeight:Float, facade:Null<DBFacade>, game:Null<DistributedDungeonFloor>, ringsVisible:Bool,
			coreColor:UInt, zones:Array<Ring.Zone>, highlights:PropHighlight):Void {
		var dt = lastFrameMs == 0 ? 16 : (nowMs - lastFrameMs);
		if (dt < 0)
			dt = 16;
		else if (dt > 100)
			dt = 100;
		lastFrameMs = nowMs;

		var allowHud = ringsVisible
			&& viewWidth > 0
			&& viewHeight > 0
			&& game != null
			&& !game.isDestroyed
			&& game.isAlive()
			&& facade != null
			&& (facade.uiHideToggle == null || !facade.uiHideToggle.hidden)
			&& (facade.mainStateMachine == null || facade.mainStateMachine.currentStateName == "RunState");

		var avatar = allowHud ? game.activeOwnerAvatar : null;
		var heroOk = avatar != null
			&& !avatar.isDestroyed
			&& !avatar.isDead()
			&& !avatar.isInReviveState()
			&& avatar.hitPoints > 0
			&& avatar.hasPosition;

		if (!allowHud || !heroOk) {
			fadeOut(dt, viewWidth);
			return;
		}

		var hx = avatar.positionX;
		var hy = avatar.positionY;
		var ringThreshold = wasShown ? RING_NEAR_EXIT : RING_NEAR_ENTER;
		var propThreshold = wasShown ? PROP_NEAR_EXIT : PROP_NEAR_ENTER;
		var propThresholdSq = propThreshold * propThreshold;

		var found = false;
		var sigParts:Array<String> = [];

		// Fast pass 1: check rings with squared-distance early reject before sqrt.
		for (i in 0...zones.length) {
			var z = zones[i];
			var dx = hx - z.x;
			var dy = hy - z.y;
			var reach = z.radius + ringThreshold;
			var d2 = dx * dx + dy * dy;
			if (d2 > reach * reach)
				continue;
			found = true;
			var edge = Math.sqrt(d2) - z.radius;
			var danger = edge <= 0.0 ? 1 : 0;
			var q = danger == 1 ? 0 : Std.int(edge / 15.0);
			sigParts.push("R" + i + ":" + danger + ":" + q);
		}

		// Fast pass 2: check live shiny prop traps with squared-distance early reject.
		var propEntries = highlights.entries;
		for (p in propEntries) {
			if (!PropHighlight.isAliveProp(p.npc) || !p.npc.hasPosition)
				continue;
			var dx = hx - p.npc.positionX;
			var dy = hy - p.npc.positionY;
			var d2 = dx * dx + dy * dy;
			if (d2 > propThresholdSq)
				continue;
			found = true;
			var d = Math.sqrt(d2);
			var danger = d <= PROP_DANGER_DIST ? 1 : 0;
			var q = danger == 1 ? 0 : Std.int(d / 15.0);
			sigParts.push("P" + p.idKey + ":" + danger + ":" + q);
		}

		if (!found) {
			wasShown = false;
			lastSignature = "";
			fadeOut(dt, viewWidth);
			return;
		}

		wasShown = true;
		activeCoreColor = coreColor;
		var sig = sigParts.join("|") + "|" + coreColor;
		if (sig != lastSignature) {
			lastSignature = sig;
			rebuildCard(hx, hy, ringThreshold, propThresholdSq, zones, propEntries);
		}

		// Smoothly fade in and position at top-center (1920x1080 design coordinates).
		shownAlpha = Math.min(1.0, shownAlpha + dt * FADE_IN_SPEED);
		root.visible = true;
		root.alpha = shownAlpha;
		root.x = Math.round((viewWidth - CARD_WIDTH) * 0.5);
		root.y = Math.round(CARD_Y + (1.0 - shownAlpha) * -6.0);

		if (lastDanger) {
			dangerBorder.visible = true;
			dangerBorder.alpha = 0.72 + 0.28 * (0.5 + 0.5 * Math.sin(nowMs * DANGER_PULSE_RAD_PER_MS));
		} else {
			dangerBorder.visible = false;
		}
	}

	function fadeOut(dt:Int, viewWidth:Float):Void {
		if (shownAlpha <= 0.0) {
			root.visible = false;
			return;
		}
		shownAlpha = Math.max(0.0, shownAlpha - dt * FADE_OUT_SPEED);
		root.alpha = shownAlpha;
		root.x = Math.round((viewWidth - CARD_WIDTH) * 0.5);
		root.y = Math.round(CARD_Y + (1.0 - shownAlpha) * -6.0);
		if (shownAlpha <= 0.0)
			root.visible = false;
	}

	function rebuildCard(hx:Float, hy:Float, ringThreshold:Float, propThresholdSq:Float, zones:Array<Ring.Zone>, propEntries:Array<TrackedProp>):Void {
		var groupMap = new Map<String, ThreatItem>();
		var groups:Array<ThreatItem> = [];

		for (z in zones) {
			var dx = hx - z.x;
			var dy = hy - z.y;
			var reach = z.radius + ringThreshold;
			var d2 = dx * dx + dy * dy;
			if (d2 > reach * reach)
				continue;
			var edge = Math.sqrt(d2) - z.radius;
			var inDanger = edge <= 0.0;
			var key = "R|" + z.summary;
			var existing = groupMap.get(key);
			if (existing == null) {
				var item:ThreatItem = {
					isProp: false,
					inDanger: inDanger,
					severity: z.severity,
					dist: edge < 0.0 ? 0.0 : edge,
					count: 1,
					titleTag: "STEP RING",
					outcome: z.summary,
					actionVerb: inDanger ? "ON IT!" : Std.int(Math.max(1, edge)) + "px",
					key: key
				};
				groupMap.set(key, item);
				groups.push(item);
			} else {
				existing.count++;
				if (inDanger)
					existing.inDanger = true;
				var d = edge < 0.0 ? 0.0 : edge;
				if (d < existing.dist)
					existing.dist = d;
				existing.actionVerb = existing.inDanger ? "ON IT!" : Std.int(Math.max(1, existing.dist)) + "px";
			}
		}

		for (p in propEntries) {
			if (!PropHighlight.isAliveProp(p.npc) || !p.npc.hasPosition)
				continue;
			var dx = hx - p.npc.positionX;
			var dy = hy - p.npc.positionY;
			var d2 = dx * dx + dy * dy;
			if (d2 > propThresholdSq)
				continue;
			var d = Math.sqrt(d2);
			var inDanger = d <= PROP_DANGER_DIST;
			var trap = p.trap;
			var verb = trap.triggerKind == "HIT" ? "DON'T HIT!" : "DON'T BREAK!";
			var key = "P|" + trap.propName + "|" + trap.summary + "|" + trap.triggerKind;
			var existing = groupMap.get(key);
			if (existing == null) {
				var item:ThreatItem = {
					isProp: true,
					inDanger: inDanger,
					severity: trap.severity,
					dist: d,
					count: 1,
					titleTag: trap.propName.toUpperCase(),
					outcome: trap.summary,
					actionVerb: inDanger ? verb : Std.int(Math.max(1, d)) + "px",
					key: key
				};
				groupMap.set(key, item);
				groups.push(item);
			} else {
				existing.count++;
				if (inDanger)
					existing.inDanger = true;
				if (d < existing.dist)
					existing.dist = d;
				existing.actionVerb = existing.inDanger ? verb : Std.int(Math.max(1, existing.dist)) + "px";
			}
		}

		// Sort: active danger first -> higher severity -> closest (with 12px tie-breaker).
		groups.sort(function(a:ThreatItem, b:ThreatItem):Int {
			if (a.inDanger != b.inDanger)
				return a.inDanger ? -1 : 1;
			if (a.severity != b.severity)
				return b.severity - a.severity;
			var diff = a.dist - b.dist;
			if (Math.abs(diff) > 12.0)
				return diff < 0 ? -1 : 1;
			return a.key < b.key ? -1 : 1;
		});

		currentGroups = groups;
		var visibleCount = groups.length > MAX_ROWS ? MAX_ROWS : groups.length;
		var extraCount = groups.length - visibleCount;

		var hasDanger = false;
		var hasRingDanger = false;
		var hasPropDanger = false;
		for (g in groups) {
			if (g.inDanger) {
				hasDanger = true;
				if (g.isProp)
					hasPropDanger = true;
				else
					hasRingDanger = true;
			}
		}
		lastDanger = hasDanger;

		var cardH = HEADER_H + 4 + visibleCount * ROW_H + (visibleCount > 1 ? (visibleCount - 1) * ROW_GAP : 0) + (extraCount > 0 ? FOOTER_H + 2 : 0) + PAD_BOTTOM;
		lastCardHeight = cardH;

		// Header text & colors
		var headerText = if (hasRingDanger && hasPropDanger) "ON TRIGGER — DON'T BREAK!"
			else if (hasRingDanger) "STEPPING ON TRIGGER!"
			else if (hasPropDanger) "TRAP OBJECT — DON'T BREAK!"
			else "NEARBY TRAP";
		setFieldText(headerLabel, headerText, hasDanger ? 0xFFE066 : 0xFFF1D0);
		setFieldText(pillLabel, hasDanger ? "ACTIVE" : "NEARBY", 0xFFFFFF);

		// Draw card frame & rows
		var bg = bgShape.graphics;
		bg.clear();
		// Soft vector drop shadow
		bg.beginFill(0x08080E, 0.55);
		bg.drawRoundRect(0, 3, CARD_WIDTH, cardH, 10, 10);
		bg.endFill();
		// Main background fill
		bg.lineStyle(2.0, 0x3D3248, 0.95);
		bg.beginFill(0x141118, 0.90);
		bg.drawRoundRect(0, 0, CARD_WIDTH, cardH, 10, 10);
		bg.endFill();
		// Inner obsidian bevel
		bg.lineStyle(1.0, 0x08080E, 0.95);
		bg.drawRoundRect(2, 2, CARD_WIDTH - 4, cardH - 4, 8, 8);
		// Header tint bar
		bg.lineStyle(0, 0, 0);
		bg.beginFill(hasDanger ? 0x3A171C : 0x1D1724, 0.95);
		bg.drawRoundRect(3, 3, CARD_WIDTH - 6, HEADER_H - 3, 7, 7);
		bg.endFill();
		// Header status pill
		bg.beginFill(hasDanger ? 0xFF476C : 0x393147, 0.95);
		bg.drawRoundRect(CARD_WIDTH - PAD_X - 88, 6, 84, 17, 6, 6);
		bg.endFill();

		// Danger border overlay (alpha modulated separately on pulse frames)
		var db = dangerBorder.graphics;
		db.clear();
		if (hasDanger) {
			db.lineStyle(2.5, 0xFF5A36, 1.0);
			db.drawRoundRect(0, 0, CARD_WIDTH, cardH, 10, 10);
		}

		// Draw row containers, mini-badges, and row text
		var bdg = badgesShape.graphics;
		bdg.clear();
		for (i in 0...MAX_ROWS) {
			var rv = rowViews[i];
			if (i >= visibleCount) {
				rv.badge.visible = false;
				rv.outcome.visible = false;
				continue;
			}
			var item = groups[i];
			var rowY = HEADER_H + 4 + i * (ROW_H + ROW_GAP);
			var accent = item.isProp ? PropHighlight.GLOW_COLOR : activeCoreColor;

			// Row card fill + left accent strip
			bg.lineStyle(0, 0, 0);
			bg.beginFill(item.inDanger ? 0x2D1622 : 0x1E1924, 0.88);
			bg.drawRoundRect(PAD_X, rowY, CARD_WIDTH - PAD_X * 2, ROW_H, 6, 6);
			bg.endFill();
			bg.beginFill(accent, 0.95);
			bg.drawRoundRect(PAD_X, rowY + 3, 4, ROW_H - 6, 2, 2);
			bg.endFill();

			// Vector mini-badge at (PAD_X + 18, rowY + 16)
			var cx = PAD_X + 19;
			var cy = rowY + ROW_H * 0.5;
			if (item.isProp)
				drawPropBadge(bdg, cx, cy);
			else
				drawRingBadge(bdg, cx, cy, activeCoreColor, item.inDanger);

			rv.badge.visible = true;
			rv.outcome.visible = true;
			var prefix = (item.count > 1 ? item.count + "x " : "") + item.titleTag + " • " + item.actionVerb;
			var tagColor = item.inDanger ? 0xFFFFFF : (item.isProp ? 0xE99EFF : 0xFFB078);
			var outColor = item.severity >= Ring.SEVERITY_BOSS ? 0xFFE066 : 0xFFF1D0;
			setFieldText(rv.badge, prefix, tagColor);
			setFieldText(rv.outcome, item.outcome, outColor);
		}

		if (extraCount > 0) {
			moreLabel.visible = true;
			moreLabel.y = HEADER_H + 4 + visibleCount * (ROW_H + ROW_GAP);
			setFieldText(moreLabel, "+" + extraCount + " more nearby", 0xB9AEC7);
		} else {
			moreLabel.visible = false;
		}
	}

	static function drawRingBadge(g:openfl.display.Graphics, cx:Float, cy:Float, coreColor:UInt, solidDot:Bool):Void {
		var r = 8.5;
		var segs = 6;
		var span = 0.62;
		// Obsidian casing + biome core dashed ring
		for (pass in 0...2) {
			g.lineStyle(pass == 0 ? 4.0 : 2.0, pass == 0 ? 0x08080E : coreColor, 0.95);
			for (i in 0...segs) {
				var a0 = i * (2 * Math.PI / segs);
				var a1 = a0 + span;
				var steps = 3;
				for (s in 0...steps + 1) {
					var a = a0 + (a1 - a0) * (s / steps);
					var px = cx + r * Math.cos(a);
					var py = cy + r * Math.sin(a);
					if (s == 0)
						g.moveTo(px, py);
					else
						g.lineTo(px, py);
				}
			}
		}
		g.lineStyle(0, 0, 0);
		g.beginFill(coreColor, solidDot ? 1.0 : 0.45);
		g.drawCircle(cx, cy, solidDot ? 3.2 : 1.8);
		g.endFill();
	}

	static function drawPropBadge(g:openfl.display.Graphics, cx:Float, cy:Float):Void {
		var r = 8.5;
		g.lineStyle(2.5, 0x08080E, 0.95);
		g.beginFill(0x2B1038, 0.95);
		g.moveTo(cx, cy - r);
		g.lineTo(cx + r, cy);
		g.lineTo(cx, cy + r);
		g.lineTo(cx - r, cy);
		g.lineTo(cx, cy - r);
		g.endFill();

		g.lineStyle(1.6, PropHighlight.GLOW_COLOR, 1.0);
		g.moveTo(cx, cy - r);
		g.lineTo(cx + r, cy);
		g.lineTo(cx, cy + r);
		g.lineTo(cx - r, cy);
		g.lineTo(cx, cy - r);

		var k = 3.2;
		g.lineStyle(1.8, PropHighlight.SHIMMER_COLOR, 0.95);
		g.moveTo(cx - k, cy - k);
		g.lineTo(cx + k, cy + k);
		g.moveTo(cx + k, cy - k);
		g.lineTo(cx - k, cy + k);
	}

	function makeField(isTitle:Bool, size:Int, color:UInt, width:Float, align:TextFormatAlign):TextField {
		var tf = new TextField();
		tf.selectable = false;
		tf.mouseEnabled = false;
		tf.tabEnabled = false;
		tf.embedFonts = embedded;
		tf.width = width;
		tf.height = size * 1.8;
		var fmt = new TextFormat(isTitle ? titleFont : bodyFont, size, color);
		fmt.align = align;
		tf.defaultTextFormat = fmt;
		return tf;
	}

	function reformat(tf:TextField, isTitle:Bool, size:Int, align:TextFormatAlign):Void {
		var fmt = tf.defaultTextFormat;
		var color:UInt = fmt != null && fmt.color != null ? fmt.color : 0xFFFFFF;
		var next = new TextFormat(isTitle ? titleFont : bodyFont, size, color);
		next.align = align;
		tf.embedFonts = embedded;
		tf.defaultTextFormat = next;
		tf.setTextFormat(next);
	}

	function setFieldText(tf:TextField, text:String, color:UInt):Void {
		var fmt = tf.defaultTextFormat;
		if (fmt == null || fmt.color != color) {
			var next = new TextFormat(fmt != null ? fmt.font : bodyFont, fmt != null ? fmt.size : 12, color);
			if (fmt != null)
				next.align = fmt.align;
			tf.defaultTextFormat = next;
			tf.text = text;
			tf.setTextFormat(next);
			return;
		}
		if (tf.text != text) {
			tf.text = text;
			tf.setTextFormat(fmt);
		}
	}
}
