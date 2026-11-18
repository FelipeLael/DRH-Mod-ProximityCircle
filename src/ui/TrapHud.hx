package mods.proximity_circle.ui;

import brain.assetRepository.AssetLoadingComponent;
import brain.assetRepository.SwfAsset;
import distributedObjects.DistributedDungeonFloor;
import facade.DBFacade;
import mods.proximity_circle.Ring;
import mods.proximity_circle.ui.PropHighlight;
import mods.proximity_circle.ui.ZoneTracker;
import openfl.display.GradientType;
import openfl.display.Graphics;
import openfl.display.MovieClip;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.filters.GlowFilter;
import openfl.geom.Matrix;
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
	var liveSpawns:Int;
	var isAllHero:Bool;
	var sourceLabel:String;
	var outcome:String;
	var chipText:String;
	var chipKind:Int; // 0=armed, 1=step_off, 2=avoid_prop, 3=spawned, 4=firing, 5=cleared
	var key:String;
}

private typedef RowView = {
	var outcome:TextField;
	var source:TextField;
	var chip:TextField;
}

/**
 * DRH-native Trap Inspector HUD on `ctx.overlay` styled after `db_UI_HUD.swf` (`ui_hud` &
 * `UI_currency_coin`) using DRH's `Fat Rhino PB` and `Futura Bold` fonts (`db_UI_town.swf`),
 * carved chestnut-wood bevel gradients, recessed espresso tray, and outcome-first stacked rows.
 *
 * Anchored in the Top-Right combat telemetry rail (`x = viewWidth - 336 - 18, y = 184`) below the
 * settings gear and above `party_dps_meter` (`y = 362`) with zero pixel-distance jitter and
 * zero steady-state 60 FPS allocations.
 */
class TrapHud {
	static inline final TOWN_SWF = "Resources/Art2D/UI/db_UI_town.swf";

	static inline final CARD_WIDTH:Float = 336.0;

	static inline final RIGHT_MARGIN:Float = 18.0;

	static inline final ANCHOR_Y:Float = 184.0;

	static inline final HEADER_H:Float = 26.0;

	static inline final ROW_H:Float = 36.0;

	static inline final ROW_GAP:Float = 4.0;

	static inline final FOOTER_H:Float = 15.0;

	static inline final PAD_X:Float = 10.0;

	static inline final PAD_BOTTOM:Float = 7.0;

	static inline final MAX_ROWS:Int = 3;

	/** Advance warning distances (~1.2s at 250 px/s) with +30 px hysteresis to stop flicker. */
	static inline final RING_NEAR_ENTER:Float = 300.0;

	static inline final RING_NEAR_EXIT:Float = 330.0;

	static inline final PROP_NEAR_ENTER:Float = 320.0;

	static inline final PROP_NEAR_EXIT:Float = 350.0;

	static inline final PROP_DANGER_DIST:Float = 80.0;

	static inline final VIS_IN_SPEED:Float = 0.0077; // ~130 ms

	static inline final VIS_OUT_SPEED:Float = 0.0059; // ~170 ms

	static inline final DANGER_PULSE_RAD_PER_MS:Float = 0.0091106; // 1.45 Hz

	static inline final ONSET_DURATION_MS:Int = 180;

	/** Chip style kinds. */
	static inline final CHIP_ARMED = 0;

	static inline final CHIP_STEP_OFF = 1;

	static inline final CHIP_AVOID_PROP = 2;

	static inline final CHIP_SPAWNED = 3;

	static inline final CHIP_FIRING = 4;

	static inline final CHIP_CLEARED = 5;

	/** DRH UI palette constants (sampled from db_UI_HUD.swf & db_UI_town.swf). */
	static inline final COL_INK_WOOD:UInt = 0x351700;

	static inline final COL_INK_DANGER:UInt = 0x35000A;

	static inline final COL_WELL:UInt = 0x2C1408;

	static inline final COL_GOLD_RIM:UInt = 0xE6A03C;

	static inline final COL_GOLD_BOSS:UInt = 0xF9DE0B;

	static inline final COL_BRONZE_DARK:UInt = 0x6E5334;

	static inline final COL_SHADOW:UInt = 0x140701;

	var root:Sprite;

	var bgShape:Shape;

	var dangerBorder:Shape;

	var onsetFlash:Shape;

	var badgesShape:Shape;

	var primaryLabelsLayer:Sprite;

	var metaLabelsLayer:Sprite;

	var alertIcon:Null<MovieClip> = null;

	var alertIconPlaying:Bool = false;

	var headerLabel:TextField;

	var pillLabel:TextField;

	var moreLabel:TextField;

	var rowViews:Array<RowView> = [];

	var gradMatrix:Matrix = new Matrix();

	var loader:Null<AssetLoadingComponent> = null;

	var titleFont:String = "_sans";

	var bodyFont:String = "_sans";

	var embedded:Bool = false;

	var visT:Float = 0.0;

	var currentAlpha:Float = 0.0;

	var targetAlpha:Float = 0.94;

	var lastFrameMs:Int = 0;

	var wasShown:Bool = false;

	var lastSigHash:Int = 0;

	var lastSigCount:Int = -1;

	var lastSigColor:UInt = 0;

	var lastCardHeight:Float = 78.0;

	var lastDanger:Bool = false;

	var lastHasActiveSpawn:Bool = false;

	var onsetStartMs:Int = -1;

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
		dangerBorder.visible = false;
		dangerBorder.filters = [new GlowFilter(0xFF1A24, 0.85, 8.0, 8.0, 2.2, 2)];

		onsetFlash = new Shape();
		onsetFlash.visible = false;

		badgesShape = new Shape();

		primaryLabelsLayer = new Sprite();
		primaryLabelsLayer.mouseEnabled = false;
		primaryLabelsLayer.mouseChildren = false;
		primaryLabelsLayer.filters = [new GlowFilter(0x2D1600, 1.0, 3.0, 3.0, 3.5, 2)];

		metaLabelsLayer = new Sprite();
		metaLabelsLayer.mouseEnabled = false;
		metaLabelsLayer.mouseChildren = false;
		metaLabelsLayer.filters = [new GlowFilter(0x180902, 0.90, 2.0, 2.0, 2.6, 2)];

		root.addChild(bgShape);
		root.addChild(dangerBorder);
		root.addChild(onsetFlash);
		root.addChild(badgesShape);
		root.addChild(primaryLabelsLayer);
		root.addChild(metaLabelsLayer);

		headerLabel = makeField(true, 13, 0xFFF3D6, CARD_WIDTH - 96, TextFormatAlign.LEFT);
		headerLabel.x = PAD_X;
		headerLabel.y = 4;
		primaryLabelsLayer.addChild(headerLabel);

		pillLabel = makeField(false, 10, 0xFFFFFF, 72, TextFormatAlign.CENTER);
		pillLabel.x = CARD_WIDTH - PAD_X - 72;
		pillLabel.y = 6;
		metaLabelsLayer.addChild(pillLabel);

		for (i in 0...MAX_ROWS) {
			var rowY = HEADER_H + 5 + i * (ROW_H + ROW_GAP);
			var out = makeField(false, 12, 0xFFF3D6, 192, TextFormatAlign.LEFT);
			out.x = 48;
			out.y = rowY + 3;
			out.visible = false;
			primaryLabelsLayer.addChild(out);

			var src = makeField(false, 10, 0xC8AE86, 192, TextFormatAlign.LEFT);
			src.x = 48;
			src.y = rowY + 19;
			src.visible = false;
			metaLabelsLayer.addChild(src);

			var chp = makeField(false, 10, 0xFFFFFF, 74, TextFormatAlign.CENTER);
			chp.x = 246;
			chp.y = rowY + 10;
			chp.visible = false;
			metaLabelsLayer.addChild(chp);

			rowViews.push({outcome: out, source: src, chip: chp});
		}

		moreLabel = makeField(false, 10, 0xC4A87C, CARD_WIDTH - PAD_X * 2, TextFormatAlign.RIGHT);
		moreLabel.x = PAD_X;
		moreLabel.visible = false;
		metaLabelsLayer.addChild(moreLabel);

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
				// Force next visible frame to re-measure fitText with embedded metrics.
				lastSigCount = -1;
			}
		}

		var exType:Dynamic = asset.getClass("exclaimation_icon");
		if (exType != null) {
			var icon:MovieClip = cast ASCompat.createInstance(exType, []);
			if (icon != null) {
				icon.gotoAndStop(1);
				var bounds = icon.getBounds(icon);
				var maxDim = Math.max(bounds.width, bounds.height);
				var s = maxDim > 0 ? (15.0 / maxDim) : 1.0;
				icon.scaleX = s;
				icon.scaleY = s;
				// Center using true SWF bounds (exclaimation_icon has asymmetric Y center -3.1).
				var cx = bounds.x + bounds.width * 0.5;
				var cy = bounds.y + bounds.height * 0.5;
				icon.x = (PAD_X + 8.0) - cx * s;
				icon.y = (HEADER_H * 0.5 + 1.0) - cy * s;
				icon.visible = false;
				icon.mouseEnabled = false;
				icon.mouseChildren = false;
				alertIcon = icon;
				alertIconPlaying = false;
				root.addChild(icon);
				lastSigCount = -1;
			}
		}
	}

	function applyFonts():Void {
		reformat(headerLabel, true, 13, TextFormatAlign.LEFT);
		reformat(pillLabel, false, 10, TextFormatAlign.CENTER);
		reformat(moreLabel, false, 10, TextFormatAlign.RIGHT);
		for (rv in rowViews) {
			reformat(rv.outcome, false, 12, TextFormatAlign.LEFT);
			reformat(rv.source, false, 10, TextFormatAlign.LEFT);
			reformat(rv.chip, false, 10, TextFormatAlign.CENTER);
		}
	}

	public function reset():Void {
		wasShown = false;
		visT = 0.0;
		currentAlpha = 0.0;
		targetAlpha = 0.94;
		lastSigHash = 0;
		lastSigCount = -1;
		lastSigColor = 0;
		lastDanger = false;
		lastHasActiveSpawn = false;
		onsetStartMs = -1;
		root.visible = false;
		root.alpha = 0.0;
		dangerBorder.visible = false;
		onsetFlash.visible = false;
		setAlertIconActive(false);
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

		var hitCount = 0;
		var sigHash:Int = 0x811C9DC5;

		// Pass 1: Rings (semantic state + inside + liveSpawns; NO twitchy pixel distances!)
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
			hitCount++;
			var inside = d2 <= z.radius * z.radius ? 1 : 0;
			sigHash = mixHash(sigHash, 1);
			sigHash = mixHash(sigHash, i);
			sigHash = mixHash(sigHash, (zr.status << 8) | (inside << 7) | (zr.liveSpawns & 0x7F));
		}

		// Pass 2: Live shiny prop traps (semantic state + danger range; NO pixel churn)
		var propEntries = highlights.entries;
		var propDangerSq = PROP_DANGER_DIST * PROP_DANGER_DIST;
		for (p in propEntries) {
			if (!PropHighlight.isAliveProp(p.npc) || !p.npc.hasPosition)
				continue;
			var dx = hx - p.npc.positionX;
			var dy = hy - p.npc.positionY;
			var d2 = dx * dx + dy * dy;
			if (d2 > propThresholdSq)
				continue;
			hitCount++;
			var close = d2 <= propDangerSq ? 1 : 0;
			var hitFired = (p.trap.triggerKind == "HIT" && PropHighlight.isDamaged(p)) ? 1 : 0;
			sigHash = mixHash(sigHash, 2);
			sigHash = mixHash(sigHash, (p.npc.id : Int));
			sigHash = mixHash(sigHash, (hitFired << 1) | close);
		}

		// Pass 3: Recently broken prop traps (`SPAWNED` / `BROKEN`)
		var brokenProps = highlights.recentBroken;
		for (i in 0...brokenProps.length) {
			var bp = brokenProps[i];
			var dx = hx - bp.x;
			var dy = hy - bp.y;
			if (dx * dx + dy * dy > propThresholdSq)
				continue;
			hitCount++;
			sigHash = mixHash(sigHash, 3);
			sigHash = mixHash(sigHash, i);
			sigHash = mixHash(sigHash, bp.expiresAtMs);
		}

		if (hitCount == 0) {
			wasShown = false;
			lastSigCount = -1;
			lastDanger = false;
			setAlertIconActive(false);
			fadeOut(dt, viewWidth, viewHeight);
			return;
		}

		wasShown = true;
		activeCoreColor = coreColor;
		var prevDanger = lastDanger;
		if (sigHash != lastSigHash || hitCount != lastSigCount || coreColor != lastSigColor) {
			lastSigHash = sigHash;
			lastSigCount = hitCount;
			lastSigColor = coreColor;
			rebuildCard(hx, hy, ringThreshold, propThresholdSq, zones, propEntries, brokenProps);
			if (lastDanger && !prevDanger)
				onsetStartMs = nowMs;
		}

		// Ease-out cubic visibility slide + smooth tiered alpha lerp
		visT = Math.min(1.0, visT + dt * VIS_IN_SPEED);
		var desiredAlpha = visT * targetAlpha;
		var lerpStep = dt * (desiredAlpha > currentAlpha ? 0.0085 : 0.0055);
		if (Math.abs(desiredAlpha - currentAlpha) <= lerpStep)
			currentAlpha = desiredAlpha;
		else
			currentAlpha += desiredAlpha > currentAlpha ? lerpStep : -lerpStep;

		var invVis = 1.0 - visT;
		var slideX = invVis * invVis * invVis * 12.0;

		// Brief 180 ms onset attention nudge + inner rim flash when entering danger
		var nudgeX = 0.0;
		if (lastDanger && onsetStartMs >= 0) {
			var elapsed = nowMs - onsetStartMs;
			if (elapsed >= 0 && elapsed < ONSET_DURATION_MS) {
				var p = elapsed / ONSET_DURATION_MS;
				nudgeX = -3.0 * Math.sin(p * Math.PI);
				onsetFlash.visible = true;
				onsetFlash.alpha = 0.75 * (1.0 - p);
			} else {
				onsetStartMs = -1;
				onsetFlash.visible = false;
			}
		} else {
			onsetFlash.visible = false;
		}

		root.visible = true;
		root.alpha = currentAlpha;
		positionCard(viewWidth, viewHeight, slideX + nudgeX);

		if (lastDanger) {
			dangerBorder.visible = true;
			dangerBorder.alpha = 0.35 + 0.65 * (0.5 + 0.5 * Math.sin(nowMs * DANGER_PULSE_RAD_PER_MS));
		} else if (lastHasActiveSpawn) {
			dangerBorder.visible = true;
			dangerBorder.alpha = 0.75;
		} else {
			dangerBorder.visible = false;
		}
	}

	static inline function mixHash(h:Int, v:Int):Int {
		return ((h ^ v) * 16777619) | 0;
	}

	function fadeOut(dt:Int, viewWidth:Float, viewHeight:Float):Void {
		if (visT <= 0.0) {
			root.visible = false;
			dangerBorder.visible = false;
			onsetFlash.visible = false;
			return;
		}
		visT = Math.max(0.0, visT - dt * VIS_OUT_SPEED);
		currentAlpha = visT * visT * targetAlpha;
		root.alpha = currentAlpha;
		var invVis = 1.0 - visT;
		positionCard(viewWidth, viewHeight, invVis * invVis * invVis * 12.0);
		if (visT <= 0.0) {
			root.visible = false;
			dangerBorder.visible = false;
			onsetFlash.visible = false;
		}
	}

	function positionCard(viewWidth:Float, viewHeight:Float, slideOffset:Float):Void {
		var targetX = Math.max(8.0, viewWidth - CARD_WIDTH - RIGHT_MARGIN + slideOffset);
		var targetY = Math.min(ANCHOR_Y, Math.max(8.0, viewHeight - lastCardHeight - 120.0));
		root.x = Math.round(targetX);
		root.y = Math.round(targetY);
	}

	function setAlertIconActive(active:Bool):Void {
		if (alertIcon == null)
			return;
		alertIcon.visible = active;
		if (active && !alertIconPlaying) {
			alertIcon.play();
			alertIconPlaying = true;
		} else if (!active && alertIconPlaying) {
			alertIcon.gotoAndStop(1);
			alertIconPlaying = false;
		}
	}

	function rebuildCard(hx:Float, hy:Float, ringThreshold:Float, propThresholdSq:Float, zones:Array<ZoneRuntime>, propEntries:Array<TrackedProp>,
			brokenProps:Array<BrokenProp>):Void {
		var groupMap = new Map<String, ThreatItem>();
		var groups:Array<ThreatItem> = [];
		var totalNearby = 0;

		for (zr in zones) {
			var z = zr.zone;
			var dx = hx - z.x;
			var dy = hy - z.y;
			var reach = z.radius + ringThreshold;
			var d2 = dx * dx + dy * dy;
			if (d2 > reach * reach)
				continue;
			totalNearby++;
			var edge = Math.sqrt(d2) - z.radius;
			var inside = edge <= 0.0;
			var st = zr.status;
			var inDanger = (st == ZoneTracker.STATUS_ARMED && inside) || (st == ZoneTracker.STATUS_SPAWNED_ALIVE && !z.hasGenerator && inside);

			var chipText:String;
			var chipKind:Int;
			if (inDanger) {
				chipText = "STEP OFF!";
				chipKind = CHIP_STEP_OFF;
			} else if (st == ZoneTracker.STATUS_SPAWNED_ALIVE) {
				if (z.hasGenerator) {
					chipText = zr.liveSpawns > 0 ? (zr.liveSpawns + " ALIVE") : "SPAWNED";
					chipKind = CHIP_SPAWNED;
				} else {
					chipText = "FIRING!";
					chipKind = CHIP_FIRING;
				}
			} else if (st == ZoneTracker.STATUS_TRIGGERED) {
				chipKind = CHIP_CLEARED;
				chipText = if (z.hasGenerator) "CLEARED";
					else if (z.isGateOpenOnly) "OPENED";
					else if (z.isDisarmOnly) "SAFE";
					else "CLEARED";
			} else {
				chipText = "ARMED";
				chipKind = CHIP_ARMED;
			}

			var key = "R|" + st + "|" + chipKind + "|" + (z.isAllHero ? "A" : "S") + "|" + z.summary;
			var existing = groupMap.get(key);
			if (existing == null) {
				var item:ThreatItem = {
					isProp: false,
					inDanger: inDanger,
					runtimeState: st,
					severity: z.severity,
					dist: edge < 0.0 ? 0.0 : edge,
					count: 1,
					liveSpawns: zr.liveSpawns,
					isAllHero: z.isAllHero,
					sourceLabel: z.isAllHero ? "Floor Ring (All Hero)" : "Floor Ring",
					outcome: condenseOutcome(z.summary),
					chipText: chipText,
					chipKind: chipKind,
					key: key
				};
				groupMap.set(key, item);
				groups.push(item);
			} else {
				existing.count++;
				existing.liveSpawns += zr.liveSpawns;
				if (inDanger)
					existing.inDanger = true;
				var d = edge < 0.0 ? 0.0 : edge;
				if (d < existing.dist)
					existing.dist = d;
				if (existing.chipKind == CHIP_SPAWNED && existing.liveSpawns > 0)
					existing.chipText = existing.liveSpawns + " ALIVE";
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
			totalNearby++;
			var d = Math.sqrt(d2);
			var close = d <= PROP_DANGER_DIST;
			var trap = p.trap;
			var alreadyHitSpawned = trap.triggerKind == "HIT" && PropHighlight.isDamaged(p);
			var st = alreadyHitSpawned ? ZoneTracker.STATUS_SPAWNED_ALIVE : ZoneTracker.STATUS_ARMED;
			var inDanger = !alreadyHitSpawned && close;
			var chipKind = alreadyHitSpawned ? CHIP_SPAWNED : (inDanger ? CHIP_AVOID_PROP : CHIP_ARMED);
			var chipText = if (alreadyHitSpawned) "SPAWNED";
				else if (inDanger) (trap.triggerKind == "HIT" ? "DON'T HIT" : "NO BREAK");
				else "ARMED";
			var actionHint = trap.triggerKind == "HIT" ? " (Hit)" : " (Break)";

			var key = "P|" + st + "|" + chipKind + "|" + trap.propName + "|" + trap.summary;
			var existing = groupMap.get(key);
			if (existing == null) {
				var item:ThreatItem = {
					isProp: true,
					inDanger: inDanger,
					runtimeState: st,
					severity: trap.severity,
					dist: d,
					count: 1,
					liveSpawns: 0,
					isAllHero: false,
					sourceLabel: trap.propName + actionHint,
					outcome: condenseOutcome(trap.summary),
					chipText: chipText,
					chipKind: chipKind,
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
			}
		}

		for (bp in brokenProps) {
			var dx = hx - bp.x;
			var dy = hy - bp.y;
			var d2 = dx * dx + dy * dy;
			if (d2 > propThresholdSq)
				continue;
			totalNearby++;
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
					liveSpawns: 0,
					isAllHero: false,
					sourceLabel: trap.propName + " (Broken)",
					outcome: condenseOutcome(trap.summary),
					chipText: trap.hasGenerator ? "SPAWNED" : "BROKEN",
					chipKind: CHIP_SPAWNED,
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

		// Sort: Danger -> Armed / Active Spawn -> Cleared -> Severity -> Distance
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
		lastHasActiveSpawn = hasActiveSpawn;
		targetAlpha = hasDanger ? 1.0 : (allCleared ? 0.58 : 0.94);

		var cardH = HEADER_H + 5 + visibleCount * ROW_H + (visibleCount > 1 ? (visibleCount - 1) * ROW_GAP : 0) + (extraCount > 0 ? FOOTER_H + 2 : 0) + PAD_BOTTOM;
		lastCardHeight = cardH;

		// Non-redundant Header (situation/imperative) + Pill (unambiguous state)
		var headerText = if (hasRingDanger && hasPropDanger) "WATCH OUT!"
			else if (hasRingDanger) "STEPPING ON TRAP!"
			else if (hasPropDanger) "TRAP OBJECT NEAR!"
			else if (allCleared) "TRAP CLEARED"
			else if (hasActiveSpawn) "TRAP TRIGGERED"
			else (totalNearby > 1 ? totalNearby + " TRAPS AHEAD" : "TRAP AHEAD");
		var headerColor = hasDanger ? 0xFFCC00 : (allCleared ? 0xB59C7A : (hasActiveSpawn ? 0xFFE082 : 0xFFF3D6));
		setAlertIconActive(hasDanger);
		headerLabel.x = (alertIcon != null && hasDanger) ? (PAD_X + 18) : PAD_X;
		fitText(headerLabel, headerText, headerColor, CARD_WIDTH - headerLabel.x - 86);

		var pillText = if (hasRingDanger) "DANGER"
			else if (hasPropDanger) "AVOID"
			else if (allCleared) "SAFE"
			else if (hasActiveSpawn) "LIVE"
			else "ARMED";
		setFieldText(pillLabel, pillText, allCleared ? 0xC8B294 : 0xFFFFFF);

		// Draw DRH-native carved chestnut-wood bevel chrome
		var bg = bgShape.graphics;
		bg.clear();

		// 1. Soft grounded drop shadow
		bg.lineStyle(0, 0, 0);
		bg.beginFill(COL_SHADOW, 0.52);
		bg.drawRoundRect(2, 4, CARD_WIDTH, cardH, 11, 11);
		bg.endFill();

		// 2. Thick comic ink outer wood bezel gradient
		var frameStroke = hasDanger ? COL_INK_DANGER : COL_INK_WOOD;
		var frameCols = hasDanger ? [0xB81818, 0x7D080A, 0x450406] : (allCleared ? [0x59402A, 0x3E2B1C, 0x2B1D12] : [0xA85716, 0x7A3608, 0x4E2104]);
		bg.lineStyle(3.0, frameStroke, 1.0);
		beginVertGradient(bg, frameCols, [0.98, 0.98, 0.98], [0, 115, 255], 0, 0, CARD_WIDTH, cardH);
		bg.drawRoundRect(0, 0, CARD_WIDTH, cardH, 10, 10);
		bg.endFill();

		// 3. Flush top header cap (rounded top, squared bottom over carved seam)
		var hdrCols = hasDanger ? [0xD41418, 0x870508] : (allCleared ? [0x453020, 0x2F2015] : (hasActiveSpawn ? [0x9E510D, 0x612E06] : [0x8F430A, 0x5E2804]));
		bg.lineStyle(0, 0, 0);
		beginVertGradient(bg, hdrCols, [0.98, 0.98], [0, 255], 3, 3, CARD_WIDTH - 6, HEADER_H - 2);
		bg.drawRoundRect(3, 3, CARD_WIDTH - 6, HEADER_H - 2, 7, 7);
		bg.drawRect(3, HEADER_H - 5, CARD_WIDTH - 6, 6);
		bg.endFill();

		// 4. Crisp top specular bevel highlight rim (signature DRH dimensional chrome)
		var specCol = hasDanger ? 0xFF6B5A : (allCleared ? 0x7A5E40 : COL_GOLD_RIM);
		bg.lineStyle(1.5, specCol, 0.80);
		bg.moveTo(8, 2.0);
		bg.lineTo(CARD_WIDTH - 8, 2.0);

		// 5. 2px carved seam beneath header + subtle side brass studs (clear of all text)
		bg.lineStyle(1.0, 0x1D0A02, 0.95);
		bg.moveTo(3, HEADER_H + 1);
		bg.lineTo(CARD_WIDTH - 3, HEADER_H + 1);
		bg.lineStyle(1.0, 0xC79844, allCleared ? 0.25 : 0.55);
		bg.moveTo(4, HEADER_H + 2);
		bg.lineTo(CARD_WIDTH - 4, HEADER_H + 2);
		for (sx in [4.0, CARD_WIDTH - 4.0]) {
			bg.lineStyle(1.0, 0x351700, 0.95);
			bg.beginFill(allCleared ? 0x8C735B : 0xF2C14E, 0.90);
			bg.drawCircle(sx, HEADER_H + 1.5, 2.2);
			bg.endFill();
		}

		// 6. Header status pill
		var pillCols = if (hasRingDanger) [0xFF2B2B, 0xA8060B];
			else if (hasPropDanger) [0xE0166C, 0x8A083E];
			else if (allCleared) [0x3D2C1E, 0x291D14];
			else if (hasActiveSpawn) [0xD47A10, 0x7A3C06];
			else [0x6E3810, 0x452006];
		var pillRim = hasDanger ? COL_INK_DANGER : (allCleared ? 0x523E29 : 0xC79844);
		bg.lineStyle(1.2, pillRim, 0.95);
		beginVertGradient(bg, pillCols, [0.98, 0.98], [0, 255], CARD_WIDTH - PAD_X - 72, 5, 72, 16);
		bg.drawRoundRect(CARD_WIDTH - PAD_X - 72, 5, 72, 16, 6, 6);
		bg.endFill();

		// 7. Recessed espresso content well + 3px top inner shadow
		var wellX = 5.0;
		var wellY = HEADER_H + 4.0;
		var wellW = CARD_WIDTH - 10.0;
		var wellH = cardH - HEADER_H - 9.0;
		bg.lineStyle(1.0, 0x1D0A02, 0.92);
		bg.beginFill(COL_WELL, 0.96);
		bg.drawRoundRect(wellX, wellY, wellW, wellH, 6, 6);
		bg.endFill();
		bg.lineStyle(0, 0, 0);
		bg.beginFill(0x120601, 0.45);
		bg.drawRect(wellX + 2, wellY + 1, wellW - 4, 3);
		bg.endFill();

		// Danger / Active outer halo border + onset flash overlay
		var db = dangerBorder.graphics;
		db.clear();
		if (hasDanger) {
			db.lineStyle(2.5, 0xFF3333, 1.0);
			db.drawRoundRect(0, 0, CARD_WIDTH, cardH, 10, 10);
		} else if (hasActiveSpawn) {
			db.lineStyle(2.0, 0xE69C24, 1.0);
			db.drawRoundRect(0, 0, CARD_WIDTH, cardH, 10, 10);
		}
		var fl = onsetFlash.graphics;
		fl.clear();
		if (hasDanger) {
			fl.lineStyle(2.0, 0xFFD24C, 1.0);
			fl.drawRoundRect(2, 2, CARD_WIDTH - 4, cardH - 4, 9, 9);
		}

		// 8. Draw stacked outcome-first rows
		var bdg = badgesShape.graphics;
		bdg.clear();
		for (i in 0...MAX_ROWS) {
			var rv = rowViews[i];
			if (i >= visibleCount) {
				rv.outcome.visible = false;
				rv.source.visible = false;
				rv.chip.visible = false;
				continue;
			}
			var item = groups[i];
			var rowY = HEADER_H + 6 + i * (ROW_H + ROW_GAP);
			var cleared = item.runtimeState == ZoneTracker.STATUS_TRIGGERED;
			var spawned = item.runtimeState == ZoneTracker.STATUS_SPAWNED_ALIVE;
			var isBoss = item.severity >= Ring.SEVERITY_BOSS;
			var rowAlpha = (cleared && !allCleared) ? 0.55 : 1.0;

			// Row card fill gradient
			if (item.inDanger) {
				bg.lineStyle(1.0, 0xB8281E, 0.85);
				beginVertGradient(bg, [0x661A12, 0x450E08], [0.96, 0.96], [0, 255], PAD_X, rowY, CARD_WIDTH - PAD_X * 2, ROW_H);
			} else if (cleared) {
				bg.lineStyle(1.0, 0x423020, 0.70);
				bg.beginFill(0x281A10, 0.65);
			} else {
				bg.lineStyle(1.0, 0x1A0C04, 0.85);
				beginVertGradient(bg, [0x462B16, 0x331E0E], [0.95, 0.95], [0, 255], PAD_X, rowY, CARD_WIDTH - PAD_X * 2, ROW_H);
			}
			bg.drawRoundRect(PAD_X, rowY, CARD_WIDTH - PAD_X * 2, ROW_H, 6, 6);
			bg.endFill();
			if (!cleared && !item.inDanger) {
				bg.lineStyle(1.0, 0x6E4725, 0.60);
				bg.moveTo(PAD_X + 4, rowY + 1);
				bg.lineTo(CARD_WIDTH - PAD_X - 4, rowY + 1);
			}

			// Left 4px threat stripe
			var stripeCol = cleared ? COL_BRONZE_DARK : (isBoss ? 0xFFCC00 : (item.isProp ? PropHighlight.GLOW_COLOR : activeCoreColor));
			bg.lineStyle(0, 0, 0);
			bg.beginFill(stripeCol, cleared ? 0.55 : 0.96);
			bg.drawRoundRect(PAD_X + 1, rowY + 4, 4, ROW_H - 8, 2, 2);
			bg.endFill();

			// 24x24 recessed medallion socket
			var sockX = 18.0;
			var sockY = rowY + 6.0;
			var sockRim = cleared ? 0x4D3824 : (isBoss ? COL_GOLD_BOSS : 0x6E451D);
			bdg.lineStyle(1.2, sockRim, rowAlpha);
			bdg.beginFill(0x1A0B04, 0.95 * rowAlpha);
			bdg.drawRoundRect(sockX, sockY, 24, 24, 5, 5);
			bdg.endFill();

			var cx = sockX + 12.0;
			var cy = sockY + 12.0;
			if (item.isProp)
				drawPropBadge(bdg, cx, cy, cleared, rowAlpha);
			else
				drawRingBadge(bdg, cx, cy, cleared ? COL_BRONZE_DARK : activeCoreColor, item.inDanger, spawned, cleared, rowAlpha);

			// Right 74x20 semantic gradient state chip
			drawStateChip(bg, 246, rowY + 8, 74, 20, item.chipKind, rowAlpha);

			// Outcome (Primary 12px) + Source (Secondary 10px) + Chip (10px)
			rv.outcome.visible = true;
			rv.source.visible = true;
			rv.chip.visible = true;
			rv.outcome.y = rowY + 3;
			rv.source.y = rowY + 19;
			rv.chip.y = rowY + 10;
			rv.outcome.alpha = rowAlpha;
			rv.source.alpha = rowAlpha;
			rv.chip.alpha = rowAlpha;

			var outCol = if (cleared) 0xB59C7A; else if (isBoss) 0xFFCC00; else 0xFFF3D6;
			var srcCol = if (cleared) 0x8D775C; else if (item.isProp) 0xFF9ED0; else 0xC8AE86;
			var chipTextCol = switch (item.chipKind) {
				case CHIP_CLEARED: 0x9E886B;
				case CHIP_ARMED: 0xF2C14E;
				case CHIP_SPAWNED | CHIP_FIRING: 0xFFF1D0;
				default: 0xFFFFFF;
			};

			var srcText = (item.count > 1 ? item.count + "x " : "") + item.sourceLabel;
			fitText(rv.outcome, item.outcome, outCol, 192);
			fitText(rv.source, srcText, srcCol, 192);
			setFieldText(rv.chip, item.chipText, chipTextCol);
		}

		if (extraCount > 0) {
			moreLabel.visible = true;
			moreLabel.y = HEADER_H + 6 + visibleCount * (ROW_H + ROW_GAP);
			setFieldText(moreLabel, "+" + extraCount + " more nearby", 0xC4A87C);
		} else {
			moreLabel.visible = false;
		}
	}

	function beginVertGradient(g:Graphics, colors:Array<UInt>, alphas:Array<Float>, ratios:Array<Int>, x:Float, y:Float, w:Float, h:Float):Void {
		gradMatrix.createGradientBox(w, h, Math.PI * 0.5, x, y);
		g.beginGradientFill(GradientType.LINEAR, colors, alphas, ratios, gradMatrix);
	}

	function drawStateChip(g:Graphics, x:Float, y:Float, w:Float, h:Float, kind:Int, alphaScale:Float):Void {
		var cols:Array<UInt>;
		var rim:UInt;
		switch (kind) {
			case CHIP_STEP_OFF:
				cols = [0xFF2B2B, 0xA8060B];
				rim = 0x35000A;
			case CHIP_AVOID_PROP:
				cols = [0xE0166C, 0x8A083E];
				rim = 0x350016;
			case CHIP_SPAWNED:
				cols = [0xD47A10, 0x7A3C06];
				rim = 0x3A1900;
			case CHIP_FIRING:
				cols = [0xE0620B, 0x8F2604];
				rim = 0x350F00;
			case CHIP_CLEARED:
				cols = [0x2D2016, 0x211710];
				rim = 0x523E29;
			default:
				cols = [0x5C3210, 0x3A1E08];
				rim = 0x8C6A2A;
		}
		g.lineStyle(1.1, rim, 0.95 * alphaScale);
		beginVertGradient(g, cols, [0.98 * alphaScale, 0.98 * alphaScale], [0, 255], x, y, w, h);
		g.drawRoundRect(x, y, w, h, 5, 5);
		g.endFill();
	}

	static function drawRingBadge(g:Graphics, cx:Float, cy:Float, coreColor:UInt, inDanger:Bool, spawned:Bool, cleared:Bool, alphaScale:Float):Void {
		var r = 7.5;
		var segs = 6;
		var span = 0.62;
		for (pass in 0...2) {
			g.lineStyle(pass == 0 ? 3.5 : 1.8, pass == 0 ? 0x120A04 : coreColor, 0.95 * alphaScale);
			for (i in 0...segs) {
				var a0 = i * (2 * Math.PI / segs);
				var a1 = a0 + span;
				for (s in 0...4) {
					var a = a0 + (a1 - a0) * (s / 3.0);
					var px = cx + r * Math.cos(a);
					var py = cy + r * Math.sin(a);
					if (s == 0)
						g.moveTo(px, py);
					else
						g.lineTo(px, py);
				}
			}
		}
		if (cleared) {
			drawTinyCheck(g, cx, cy, 0xB59C7A, alphaScale);
		} else if (inDanger || spawned) {
			g.lineStyle(0, 0, 0);
			g.beginFill(inDanger ? 0xFF1E32 : 0xFFCC00, 0.98 * alphaScale);
			g.drawCircle(cx, cy, 2.8);
			g.endFill();
		}
	}

	static function drawPropBadge(g:Graphics, cx:Float, cy:Float, cleared:Bool, alphaScale:Float):Void {
		var r = 7.5;
		var rim = cleared ? COL_BRONZE_DARK : PropHighlight.GLOW_COLOR;
		var fill = cleared ? 0x3A281A : 0x56163C;
		g.lineStyle(2.0, rim, 0.95 * alphaScale);
		g.beginFill(fill, 0.92 * alphaScale);
		g.moveTo(cx, cy - r);
		g.lineTo(cx + r, cy);
		g.lineTo(cx, cy + r);
		g.lineTo(cx - r, cy);
		g.lineTo(cx, cy - r);
		g.endFill();
		if (cleared) {
			drawTinyCheck(g, cx, cy, 0xB59C7A, alphaScale);
		} else {
			g.lineStyle(1.5, PropHighlight.SHIMMER_COLOR, 0.95 * alphaScale);
			g.moveTo(cx, cy - 3.5);
			g.lineTo(cx, cy + 3.5);
			g.moveTo(cx - 3.5, cy);
			g.lineTo(cx + 3.5, cy);
		}
	}

	static function drawTinyCheck(g:Graphics, cx:Float, cy:Float, color:UInt, alphaScale:Float):Void {
		g.lineStyle(1.6, color, 0.95 * alphaScale);
		g.moveTo(cx - 3.2, cy + 0.2);
		g.lineTo(cx - 0.8, cy + 2.6);
		g.lineTo(cx + 3.4, cy - 2.4);
	}

	/** Strips redundant `"Spawns "` prefix so primary threat lines scan faster beside the icon. */
	static function condenseOutcome(summary:String):String {
		if (summary == null)
			return "Trap Trigger";
		var s = summary;
		if (StringTools.startsWith(s, "Spawns "))
			s = s.substr(7);
		if (StringTools.startsWith(s, "Mini-Boss: "))
			s = "BOSS: " + s.substr(11);
		return s;
	}

	function makeField(isTitle:Bool, size:Int, color:UInt, width:Float, align:TextFormatAlign):TextField {
		var tf = new TextField();
		tf.selectable = false;
		tf.mouseEnabled = false;
		tf.tabEnabled = false;
		tf.multiline = false;
		tf.wordWrap = false;
		tf.width = width;
		tf.height = size + 8;
		tf.embedFonts = embedded;
		var fmt = new TextFormat(isTitle ? titleFont : bodyFont, size, color, null, null, null, null, null, align);
		tf.defaultTextFormat = fmt;
		tf.setTextFormat(fmt);
		return tf;
	}

	function reformat(tf:TextField, isTitle:Bool, size:Int, align:TextFormatAlign):Void {
		var col:UInt = tf.defaultTextFormat != null && tf.defaultTextFormat.color != null ? tf.defaultTextFormat.color : 0xFFFFFF;
		tf.embedFonts = embedded;
		var fmt = new TextFormat(isTitle ? titleFont : bodyFont, size, col, null, null, null, null, null, align);
		tf.defaultTextFormat = fmt;
		if (tf.text != null && tf.text.length > 0)
			tf.setTextFormat(fmt);
	}

	function setFieldText(tf:TextField, text:String, color:UInt):Void {
		var fmt = tf.defaultTextFormat;
		if (fmt != null) {
			fmt.color = color;
			tf.defaultTextFormat = fmt;
		}
		tf.text = text;
		if (fmt != null)
			tf.setTextFormat(fmt);
	}

	/** Pixel-measured text fit using embedded `…` (U+2026) so long strings never hard-clip. */
	function fitText(tf:TextField, raw:String, color:UInt, maxWidth:Float):Void {
		setFieldText(tf, raw, color);
		if (tf.textWidth <= maxWidth - 4 || raw.length <= 4)
			return;
		var lo = 3;
		var hi = raw.length - 1;
		while (lo < hi) {
			var mid = (lo + hi + 1) >> 1;
			setFieldText(tf, raw.substr(0, mid) + "\u2026", color);
			if (tf.textWidth <= maxWidth - 4)
				lo = mid;
			else
				hi = mid - 1;
		}
		setFieldText(tf, raw.substr(0, lo) + "\u2026", color);
	}
}
