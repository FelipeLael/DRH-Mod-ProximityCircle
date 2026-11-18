package mods.proximity_circle.ui;

import brain.assetRepository.AssetLoadingComponent;
import brain.assetRepository.SwfAsset;
import distributedObjects.DistributedDungeonFloor;
import facade.DBFacade;
import mods.proximity_circle.Ring;
import mods.proximity_circle.ui.PropHighlight;
import mods.proximity_circle.ui.ZoneTracker;
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
	var runtimeState:Int; // 0 = armed, 1 = active/spawned, 2 = triggered/cleared
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
 * DRH-native progressive-disclosure proximity HUD card on `ctx.overlay` using the game's
 * `Fat Rhino PB` and `Futura Bold` fonts (`db_UI_town.swf`) and warm espresso-oak / burnished
 * gold-bronze framing matching `UI_currency_coin` and `popup_base`.
 *
 * Anchored in the Top-Right combat telemetry rail (`x = viewWidth - 368 - 18, y = 184`) below the
 * settings gear and above `party_dps_meter` so it never overlaps `hudStyle = 0/1` widgets or
 * blocks the upper-central forward movement lane.
 */
class TrapHud {
	static inline final TOWN_SWF = "Resources/Art2D/UI/db_UI_town.swf";

	static inline final CARD_WIDTH:Float = 368.0;

	static inline final RIGHT_MARGIN:Float = 18.0;

	static inline final ANCHOR_Y:Float = 184.0;

	static inline final HEADER_H:Float = 28.0;

	static inline final ROW_H:Float = 32.0;

	static inline final ROW_GAP:Float = 4.0;

	static inline final FOOTER_H:Float = 18.0;

	static inline final PAD_X:Float = 10.0;

	static inline final PAD_BOTTOM:Float = 8.0;

	static inline final MAX_ROWS:Int = 3;

	/** Advance warning distances (~1.2s at 250 px/s) with +30 px hysteresis to stop flicker. */
	static inline final RING_NEAR_ENTER:Float = 300.0;

	static inline final RING_NEAR_EXIT:Float = 330.0;

	static inline final PROP_NEAR_ENTER:Float = 320.0;

	static inline final PROP_NEAR_EXIT:Float = 350.0;

	static inline final PROP_DANGER_DIST:Float = 80.0;

	static inline final FADE_IN_SPEED:Float = 0.0085;

	static inline final FADE_OUT_SPEED:Float = 0.0065;

	static inline final DANGER_PULSE_RAD_PER_MS:Float = 0.0075398; // 1.2 Hz

	/** DRH UI palette constants (from db_UI_HUD.swf / db_UI_town.swf / RecArt.OUTLINE). */
	static inline final COL_INK:UInt = 0x120A04;

	static inline final COL_SHADOW:UInt = 0x0C0502;

	static inline final COL_OUTLINE:UInt = 0x330000;

	static inline final COL_BODY:UInt = 0x2C1408;

	static inline final COL_GOLD:UInt = 0xC79844;

	static inline final COL_GOLD_BRIGHT:UInt = 0xF2C14E;

	static inline final COL_BRONZE_DARK:UInt = 0x8C6A2A;

	static inline final COL_HEADER_OAK:UInt = 0x6E3200;

	static inline final COL_HEADER_DANGER:UInt = 0x8C0407;

	static inline final COL_HEADER_SPAWNED:UInt = 0x5E380C;

	static inline final COL_HEADER_CLEARED:UInt = 0x3D291A;

	static inline final COL_ROW_OAK:UInt = 0x3A2412;

	static inline final COL_ROW_DANGER:UInt = 0x4B140C;

	static inline final COL_ROW_MUTED:UInt = 0x291B10;

	var root:Sprite;

	var bgShape:Shape;

	var dangerBorder:Shape;

	var badgesShape:Shape;

	var alertIcon:Null<MovieClip> = null;

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

	var lastCardHeight:Float = 78.0;

	var lastDanger:Bool = false;

	var activeCoreColor:UInt = Ring.COLOR_ROSE;

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
		labelsLayer.filters = [new GlowFilter(COL_OUTLINE, 1, 4, 4, 4)];

		root.addChild(bgShape);
		root.addChild(dangerBorder);
		root.addChild(badgesShape);
		root.addChild(labelsLayer);

		headerLabel = makeField(true, 13, 0xFFF1D0, 236, TextFormatAlign.LEFT);
		headerLabel.x = PAD_X;
		headerLabel.y = 4;
		labelsLayer.addChild(headerLabel);

		pillLabel = makeField(false, 10, 0xFFFFFF, 90, TextFormatAlign.CENTER);
		pillLabel.x = CARD_WIDTH - PAD_X - 90;
		pillLabel.y = 6;
		labelsLayer.addChild(pillLabel);

		for (i in 0...MAX_ROWS) {
			var rowY = HEADER_H + 5 + i * (ROW_H + ROW_GAP);
			var tag = makeField(false, 11, 0xF2C14E, 146, TextFormatAlign.LEFT);
			tag.x = PAD_X + 32;
			tag.y = rowY + 7;
			tag.visible = false;
			labelsLayer.addChild(tag);

			var out = makeField(false, 11, 0xFFF1D0, CARD_WIDTH - (PAD_X * 2 + 180), TextFormatAlign.RIGHT);
			out.x = PAD_X + 178;
			out.y = rowY + 7;
			out.visible = false;
			labelsLayer.addChild(out);

			rowViews.push({badge: tag, outcome: out});
		}

		moreLabel = makeField(false, 10, 0xC4A87C, CARD_WIDTH - PAD_X * 2, TextFormatAlign.RIGHT);
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
		if (sample != null) {
			var title = Std.downcast(sample.getChildByName("title_label"), TextField);
			var body = Std.downcast(sample.getChildByName("message_label"), TextField);
			if (title != null && body != null) {
				titleFont = title.defaultTextFormat.font;
				bodyFont = body.defaultTextFormat.font;
				embedded = title.embedFonts;
				applyFonts();
			}
		}

		var exType:Dynamic = asset.getClass("exclaimation_icon");
		if (exType != null) {
			var icon:MovieClip = cast ASCompat.createInstance(exType, []);
			if (icon != null) {
				var bounds = icon.getBounds(icon);
				var maxDim = Math.max(bounds.width, bounds.height);
				if (maxDim > 0) {
					var s = 16.0 / maxDim;
					icon.scaleX = s;
					icon.scaleY = s;
				}
				icon.x = PAD_X + 8;
				icon.y = 14;
				icon.visible = false;
				icon.mouseEnabled = false;
				icon.mouseChildren = false;
				alertIcon = icon;
				root.addChild(icon);
			}
		}
	}

	function applyFonts():Void {
		reformat(headerLabel, true, 13, TextFormatAlign.LEFT);
		reformat(pillLabel, false, 10, TextFormatAlign.CENTER);
		reformat(moreLabel, false, 10, TextFormatAlign.RIGHT);
		for (rv in rowViews) {
			reformat(rv.badge, false, 11, TextFormatAlign.LEFT);
			reformat(rv.outcome, false, 11, TextFormatAlign.RIGHT);
		}
	}

	public function reset():Void {
		wasShown = false;
		shownAlpha = 0.0;
		lastSignature = "";
		lastDanger = false;
		root.visible = false;
		root.alpha = 0.0;
		if (alertIcon != null)
			alertIcon.visible = false;
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
			coreColor:UInt, tracker:ZoneTracker, highlights:PropHighlight):Void {
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
			fadeOut(dt, viewWidth, viewHeight);
			return;
		}

		var hx = avatar.positionX;
		var hy = avatar.positionY;
		var ringThreshold = wasShown ? RING_NEAR_EXIT : RING_NEAR_ENTER;
		var propThreshold = wasShown ? PROP_NEAR_EXIT : PROP_NEAR_ENTER;
		var propThresholdSq = propThreshold * propThreshold;

		var found = false;
		var sigParts:Array<String> = [];

		// Pass 1: Rings with runtime status (Armed / Spawned / Cleared)
		var zones = tracker.items;
		for (i in 0...zones.length) {
			var zr = zones[i];
			var z = zr.zone;
			var dx = hx - z.x;
			var dy = hy - z.y;
			var reach = z.radius + ringThreshold;
			var d2 = dx * dx + dy * dy;
			if (d2 > reach * reach)
				continue;
			found = true;
			var edge = Math.sqrt(d2) - z.radius;
			var inside = edge <= 0.0 ? 1 : 0;
			var q = inside == 1 ? 0 : Std.int(edge / 15.0);
			sigParts.push("R" + i + ":" + zr.status + ":" + inside + ":" + q);
		}

		// Pass 2: Live shiny prop traps (Armed / Already Hit / Damaged)
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
			var close = d <= PROP_DANGER_DIST ? 1 : 0;
			var dmg = PropHighlight.isDamaged(p) ? 1 : 0;
			var q = close == 1 ? 0 : Std.int(d / 15.0);
			sigParts.push("P" + p.idKey + ":" + dmg + ":" + close + ":" + q);
		}

		// Pass 3: Recently broken prop traps (`BROKEN — SPAWNED!`)
		var brokenProps = highlights.recentBroken;
		for (i in 0...brokenProps.length) {
			var bp = brokenProps[i];
			var dx = hx - bp.x;
			var dy = hy - bp.y;
			if (dx * dx + dy * dy > propThresholdSq)
				continue;
			found = true;
			sigParts.push("B" + i + ":" + bp.trap.constant);
		}

		if (!found) {
			wasShown = false;
			lastSignature = "";
			fadeOut(dt, viewWidth, viewHeight);
			return;
		}

		wasShown = true;
		activeCoreColor = coreColor;
		var sig = sigParts.join("|") + "|" + coreColor;
		if (sig != lastSignature) {
			lastSignature = sig;
			rebuildCard(hx, hy, ringThreshold, propThresholdSq, zones, propEntries, brokenProps);
		}

		shownAlpha = Math.min(1.0, shownAlpha + dt * FADE_IN_SPEED);
		root.visible = true;
		root.alpha = shownAlpha;
		positionCard(viewWidth, viewHeight, (1.0 - shownAlpha) * 10.0);

		if (lastDanger) {
			dangerBorder.visible = true;
			dangerBorder.alpha = 0.72 + 0.28 * (0.5 + 0.5 * Math.sin(nowMs * DANGER_PULSE_RAD_PER_MS));
		} else {
			dangerBorder.visible = false;
		}
	}

	function fadeOut(dt:Int, viewWidth:Float, viewHeight:Float):Void {
		if (shownAlpha <= 0.0) {
			root.visible = false;
			return;
		}
		shownAlpha = Math.max(0.0, shownAlpha - dt * FADE_OUT_SPEED);
		root.alpha = shownAlpha;
		positionCard(viewWidth, viewHeight, (1.0 - shownAlpha) * 10.0);
		if (shownAlpha <= 0.0)
			root.visible = false;
	}

	function positionCard(viewWidth:Float, viewHeight:Float, slideOffset:Float):Void {
		var targetX = Math.max(8.0, viewWidth - CARD_WIDTH - RIGHT_MARGIN + slideOffset);
		var targetY = Math.min(ANCHOR_Y, Math.max(8.0, viewHeight - lastCardHeight - 120.0));
		root.x = Math.round(targetX);
		root.y = Math.round(targetY);
	}

	function rebuildCard(hx:Float, hy:Float, ringThreshold:Float, propThresholdSq:Float, zones:Array<ZoneRuntime>, propEntries:Array<TrackedProp>,
			brokenProps:Array<BrokenProp>):Void {
		var groupMap = new Map<String, ThreatItem>();
		var groups:Array<ThreatItem> = [];

		for (zr in zones) {
			var z = zr.zone;
			var dx = hx - z.x;
			var dy = hy - z.y;
			var reach = z.radius + ringThreshold;
			var d2 = dx * dx + dy * dy;
			if (d2 > reach * reach)
				continue;
			var edge = Math.sqrt(d2) - z.radius;
			var inside = edge <= 0.0;
			var st = zr.status;
			var inDanger = (st == ZoneTracker.STATUS_ARMED && inside) || (st == ZoneTracker.STATUS_SPAWNED_ALIVE && !z.hasGenerator && inside);

			var verb = switch (st) {
				case ZoneTracker.STATUS_SPAWNED_ALIVE: z.hasGenerator ? "SPAWNED!" : "FIRING!";
				case ZoneTracker.STATUS_TRIGGERED:
					if (z.hasGenerator) "CLEARED";
					else if (z.isGateOpenOnly) "OPENED";
					else if (z.isDisarmOnly) "DISARMED";
					else "TRIGGERED";
				default: inside ? "ON IT!" : Std.int(Math.max(1, edge)) + "px";
			};

			var key = "R|" + st + "|" + z.summary;
			var existing = groupMap.get(key);
			if (existing == null) {
				var item:ThreatItem = {
					isProp: false,
					inDanger: inDanger,
					runtimeState: st,
					severity: z.severity,
					dist: edge < 0.0 ? 0.0 : edge,
					count: 1,
					titleTag: "RING",
					outcome: z.summary,
					actionVerb: verb,
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
				if (st == ZoneTracker.STATUS_ARMED)
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
			var close = d <= PROP_DANGER_DIST;
			var damaged = PropHighlight.isDamaged(p);
			var trap = p.trap;
			var alreadyHitSpawned = trap.triggerKind == "HIT" && damaged;
			var st = alreadyHitSpawned ? ZoneTracker.STATUS_SPAWNED_ALIVE : ZoneTracker.STATUS_ARMED;
			var inDanger = !alreadyHitSpawned && close;
			var verb = if (alreadyHitSpawned) "SPAWNED!";
				else if (close) (trap.triggerKind == "HIT" ? "DON'T HIT!" : "DON'T BREAK!");
				else Std.int(Math.max(1, d)) + "px";

			var key = "P|" + st + "|" + trap.propName + "|" + trap.summary;
			var existing = groupMap.get(key);
			if (existing == null) {
				var item:ThreatItem = {
					isProp: true,
					inDanger: inDanger,
					runtimeState: st,
					severity: trap.severity,
					dist: d,
					count: 1,
					titleTag: trap.propName.toUpperCase(),
					outcome: trap.summary,
					actionVerb: verb,
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
				if (st == ZoneTracker.STATUS_ARMED)
					existing.actionVerb = existing.inDanger ? (trap.triggerKind == "HIT" ? "DON'T HIT!" : "DON'T BREAK!") : Std.int(Math.max(1, existing.dist)) + "px";
			}
		}

		for (bp in brokenProps) {
			var dx = hx - bp.x;
			var dy = hy - bp.y;
			var d2 = dx * dx + dy * dy;
			if (d2 > propThresholdSq)
				continue;
			var d = Math.sqrt(d2);
			var trap = bp.trap;
			var key = "B|" + trap.propName + "|" + trap.summary;
			var existing = groupMap.get(key);
			if (existing == null) {
				var item:ThreatItem = {
					isProp: true,
					inDanger: false,
					runtimeState: ZoneTracker.STATUS_SPAWNED_ALIVE,
					severity: trap.severity,
					dist: d,
					count: 1,
					titleTag: trap.propName.toUpperCase(),
					outcome: trap.summary,
					actionVerb: trap.hasGenerator ? "SPAWNED!" : "BROKEN!",
					key: key
				};
				groupMap.set(key, item);
				groups.push(item);
			} else {
				existing.count++;
				if (d < existing.dist)
					existing.dist = d;
			}
		}

		// Sort: Armed danger -> Armed nearby / active spawned -> Cleared/triggered -> Severity -> Distance
		groups.sort(function(a:ThreatItem, b:ThreatItem):Int {
			if (a.inDanger != b.inDanger)
				return a.inDanger ? -1 : 1;
			var aCleared = a.runtimeState == ZoneTracker.STATUS_TRIGGERED;
			var bCleared = b.runtimeState == ZoneTracker.STATUS_TRIGGERED;
			if (aCleared != bCleared)
				return aCleared ? 1 : -1;
			if (a.runtimeState != b.runtimeState)
				return a.runtimeState - b.runtimeState;
			if (a.severity != b.severity)
				return b.severity - a.severity;
			var diff = a.dist - b.dist;
			if (Math.abs(diff) > 12.0)
				return diff < 0 ? -1 : 1;
			return a.key < b.key ? -1 : 1;
		});

		var visibleCount = groups.length > MAX_ROWS ? MAX_ROWS : groups.length;
		var extraCount = groups.length - visibleCount;

		var hasDanger = false;
		var hasRingDanger = false;
		var hasPropDanger = false;
		var hasActiveSpawn = false;
		var allCleared = groups.length > 0;
		for (g in groups) {
			if (g.runtimeState != ZoneTracker.STATUS_TRIGGERED)
				allCleared = false;
			if (g.runtimeState == ZoneTracker.STATUS_SPAWNED_ALIVE)
				hasActiveSpawn = true;
			if (g.inDanger) {
				hasDanger = true;
				if (g.isProp)
					hasPropDanger = true;
				else
					hasRingDanger = true;
			}
		}
		lastDanger = hasDanger;

		var cardH = HEADER_H + 5 + visibleCount * ROW_H + (visibleCount > 1 ? (visibleCount - 1) * ROW_GAP : 0) + (extraCount > 0 ? FOOTER_H + 2 : 0) + PAD_BOTTOM;
		lastCardHeight = cardH;

		// Header copy & alert icon
		var headerText = if (hasRingDanger && hasPropDanger) "ON TRIGGER — WATCH OUT!"
			else if (hasRingDanger) "STEPPING ON TRIGGER!"
			else if (hasPropDanger) "TRAP OBJECT — AVOID!"
			else if (allCleared) "TRAP ALREADY TRIGGERED"
			else if (hasActiveSpawn) "TRAP ACTIVATED!"
			else "TRAP AHEAD";
		var headerColor = hasDanger ? 0xFFCC00 : (allCleared ? 0xC4A87C : 0xFFF1D0);
		if (alertIcon != null) {
			alertIcon.visible = hasDanger;
			headerLabel.x = hasDanger ? (PAD_X + 20) : PAD_X;
		} else {
			headerLabel.x = PAD_X;
		}
		setFieldText(headerLabel, headerText, headerColor);

		var pillText = if (hasDanger) "ACTIVE"
			else if (allCleared) "CLEARED"
			else if (hasActiveSpawn) "SPAWNED"
			else "NEARBY";
		setFieldText(pillLabel, pillText, allCleared ? 0xE5D4B3 : 0xFFFFFF);

		// Draw DRH-native dark espresso-oak & burnished gold-bronze frame
		var bg = bgShape.graphics;
		bg.clear();
		bg.lineStyle(0, 0, 0);
		// Warm umber drop shadow
		bg.beginFill(COL_SHADOW, 0.55);
		bg.drawRoundRect(2, 4, CARD_WIDTH, cardH, 10, 10);
		bg.endFill();
		// Thick comic ink + espresso-oak body
		bg.lineStyle(2.5, COL_INK, 0.96);
		bg.beginFill(COL_BODY, 0.94);
		bg.drawRoundRect(0, 0, CARD_WIDTH, cardH, 10, 10);
		bg.endFill();
		// Burnished gold/bronze inner bevel lip
		bg.lineStyle(1.5, allCleared ? COL_BRONZE_DARK : COL_GOLD, 0.90);
		bg.drawRoundRect(2.5, 2.5, CARD_WIDTH - 5, cardH - 5, 8, 8);
		// Header bar fill
		var headerFill = hasDanger ? COL_HEADER_DANGER : (allCleared ? COL_HEADER_CLEARED : (hasActiveSpawn ? COL_HEADER_SPAWNED : COL_HEADER_OAK));
		bg.lineStyle(0, 0, 0);
		bg.beginFill(headerFill, 0.96);
		bg.drawRoundRect(3.5, 3.5, CARD_WIDTH - 7, HEADER_H - 3, 7, 7);
		bg.endFill();
		// Header divider hairline
		bg.lineStyle(1.0, COL_BRONZE_DARK, 0.85);
		bg.moveTo(4, HEADER_H + 1);
		bg.lineTo(CARD_WIDTH - 4, HEADER_H + 1);
		// Header status pill
		var pillFill = hasDanger ? 0xED0C14 : (allCleared ? 0x38281C : (hasActiveSpawn ? 0x7A4212 : 0x4D2405));
		var pillRim = hasDanger ? 0x35000A : (allCleared ? COL_BRONZE_DARK : (hasActiveSpawn ? COL_GOLD_BRIGHT : COL_GOLD));
		bg.lineStyle(1.2, pillRim, 0.95);
		bg.beginFill(pillFill, 0.96);
		bg.drawRoundRect(CARD_WIDTH - PAD_X - 88, 6, 84, 17, 6, 6);
		bg.endFill();
		// Four subtle DRH corner gold rivets
		for (rx in [7.0, CARD_WIDTH - 7.0]) {
			for (ry in [7.0, cardH - 7.0]) {
				bg.lineStyle(1.0, 0x351700, 0.95);
				bg.beginFill(COL_GOLD_BRIGHT, 0.88);
				bg.drawCircle(rx, ry, 2.0);
				bg.endFill();
			}
		}

		// Pulsing crimson border overlay during un-triggered active danger
		var db = dangerBorder.graphics;
		db.clear();
		if (hasDanger) {
			db.lineStyle(2.5, 0xED0C14, 1.0);
			db.drawRoundRect(0, 0, CARD_WIDTH, cardH, 10, 10);
		}

		// Draw rows
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
			var rowY = HEADER_H + 5 + i * (ROW_H + ROW_GAP);
			var cleared = item.runtimeState == ZoneTracker.STATUS_TRIGGERED;
			var spawned = item.runtimeState == ZoneTracker.STATUS_SPAWNED_ALIVE;
			var accent = cleared ? COL_BRONZE_DARK : (item.isProp ? PropHighlight.GLOW_COLOR : activeCoreColor);
			var rowFill = item.inDanger ? COL_ROW_DANGER : (cleared ? COL_ROW_MUTED : COL_ROW_OAK);

			bg.lineStyle(1.0, cleared ? 0x4D3824 : 0x6E4C28, 0.85);
			bg.beginFill(rowFill, 0.92);
			bg.drawRoundRect(PAD_X, rowY, CARD_WIDTH - PAD_X * 2, ROW_H, 6, 6);
			bg.endFill();

			bg.lineStyle(0, 0, 0);
			bg.beginFill(accent, cleared ? 0.55 : 0.95);
			bg.drawRoundRect(PAD_X + 1, rowY + 3, 4, ROW_H - 6, 2, 2);
			bg.endFill();

			var cx = PAD_X + 18;
			var cy = rowY + ROW_H * 0.5;
			if (item.isProp)
				drawPropBadge(bdg, cx, cy, cleared);
			else
				drawRingBadge(bdg, cx, cy, cleared ? COL_BRONZE_DARK : activeCoreColor, item.inDanger || spawned);

			rv.badge.visible = true;
			rv.outcome.visible = true;
			var prefix = (item.count > 1 ? item.count + "x " : "") + item.titleTag + " • " + item.actionVerb;
			var tagColor = if (cleared) 0xA89270
				else if (item.inDanger) 0xFFFFFF
				else if (spawned) 0xFFCC00
				else if (item.isProp) 0xE99EFF
				else 0xF2C14E;
			var outColor = if (cleared) 0xC4A87C
				else if (item.severity >= Ring.SEVERITY_BOSS) 0xFFCC00
				else 0xFFF1D0;
			setFieldText(rv.badge, prefix, tagColor);
			setFieldText(rv.outcome, item.outcome, outColor);
		}

		if (extraCount > 0) {
			moreLabel.visible = true;
			moreLabel.y = HEADER_H + 5 + visibleCount * (ROW_H + ROW_GAP);
			setFieldText(moreLabel, "+" + extraCount + " more nearby", 0xC4A87C);
		} else {
			moreLabel.visible = false;
		}
	}

	static function drawRingBadge(g:openfl.display.Graphics, cx:Float, cy:Float, coreColor:UInt, solidDot:Bool):Void {
		var r = 8.0;
		var segs = 6;
		var span = 0.62;
		for (pass in 0...2) {
			g.lineStyle(pass == 0 ? 4.0 : 2.0, pass == 0 ? COL_INK : coreColor, 0.95);
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
		g.drawCircle(cx, cy, solidDot ? 3.0 : 1.8);
		g.endFill();
	}

	static function drawPropBadge(g:openfl.display.Graphics, cx:Float, cy:Float, cleared:Bool):Void {
		var r = 8.0;
		var rim = cleared ? COL_BRONZE_DARK : PropHighlight.GLOW_COLOR;
		var cross = cleared ? 0xC4A87C : PropHighlight.SHIMMER_COLOR;
		g.lineStyle(2.5, COL_INK, 0.95);
		g.beginFill(cleared ? 0x291B10 : 0x2B1038, 0.95);
		g.moveTo(cx, cy - r);
		g.lineTo(cx + r, cy);
		g.lineTo(cx, cy + r);
		g.lineTo(cx - r, cy);
		g.lineTo(cx, cy - r);
		g.endFill();

		g.lineStyle(1.6, rim, 1.0);
		g.moveTo(cx, cy - r);
		g.lineTo(cx + r, cy);
		g.lineTo(cx, cy + r);
		g.lineTo(cx - r, cy);
		g.lineTo(cx, cy - r);

		var k = 3.0;
		g.lineStyle(1.8, cross, 0.95);
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
			var next = new TextFormat(fmt != null ? fmt.font : bodyFont, fmt != null ? fmt.size : 11, color);
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
