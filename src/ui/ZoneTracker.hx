package mods.proximity_circle.ui;

import actor.ActorGameObject;
import distributedObjects.DistributedDungeonFloor;
import distributedObjects.HeroGameObject;
import distributedObjects.NPCGameObject;
import mods.proximity_circle.Ring;

typedef ZoneTargetWatch = {
	var npc:NPCGameObject;
	var expectedActive:Int;
	var isPlate:Bool;
	var initialState:Bool;
}

typedef ZoneRuntime = {
	var zone:Ring.Zone;
	var status:Int;
	var heroInsideNow:Bool;
	var hadHeroInside:Bool;
	var heroEnterMs:Int;
	var hadLiveSpawn:Bool;
	var liveSpawns:Int;
	var spawnNpcs:Array<NPCGameObject>;
	var spawnIds:Map<String, Bool>;
	var targets:Array<ZoneTargetWatch>;
	var targetIds:Map<String, Bool>;
}

/**
 * Tracks client-observable runtime activation state for each proximity ring on the active floor:
 * - `STATUS_ARMED` (0): not yet triggered.
 * - `STATUS_SPAWNED_ALIVE` (1): linked enemy spawns are alive right now, or a repeatable trap is firing.
 * - `STATUS_TRIGGERED` (2): one-shot / finite ambush triggered & cleared, or trap/gate settled.
 */
class ZoneTracker {
	public static inline final STATUS_ARMED = 0;

	public static inline final STATUS_SPAWNED_ALIVE = 1;

	public static inline final STATUS_TRIGGERED = 2;

	static inline final TARGET_TOLERANCE:Float = 0.5;

	static inline final SPAWN_RADIUS:Float = 130.0;

	static inline final SPAWN_RADIUS_SQ:Float = SPAWN_RADIUS * SPAWN_RADIUS;

	static inline final HERO_TRIGGER_DELAY_MS = 1500;

	/** Lag-compensation margin when matching freshly spawned enemies to a zone before the next tick. */
	static inline final SPAWN_HERO_MARGIN:Float = 90.0;

	public var items(get, never):Array<ZoneRuntime>;

	/** Incremented whenever any zone changes `status` or `heroInsideNow`, for O(1) floor-ring sync. */
	public var revision(default, null):Int = 0;

	var zones:Array<ZoneRuntime> = [];

	/** Reusable per-frame buffer for live co-op hero references (avoids steady-state array allocs). */
	var remotesBuf:Array<HeroGameObject> = [];

	public function new() {}

	function get_items():Array<ZoneRuntime> {
		return zones;
	}

	public function reset(nextZones:Array<Ring.Zone>):Void {
		zones = [];
		revision++;
		for (z in nextZones) {
			zones.push({
				zone: z,
				status: STATUS_ARMED,
				heroInsideNow: false,
				hadHeroInside: false,
				heroEnterMs: 0,
				hadLiveSpawn: false,
				liveSpawns: 0,
				spawnNpcs: [],
				spawnIds: new Map(),
				targets: [],
				targetIds: new Map()
			});
		}
	}

	public function clear():Void {
		zones = [];
		revision++;
	}

	/**
	 * Matches an NPC against any zone's linked trap/gate targets or (when `allowSpawns` is true
	 * and a hero has entered/approached the zone) generator spawns.
	 */
	public function observeNpc(npc:Null<NPCGameObject>, getNpc:String->Ring.NpcMeta, allowSpawns:Bool = true,
			game:Null<DistributedDungeonFloor> = null):Void {
		if (npc == null || npc.isDestroyed || !npc.hasPosition || npc.actorData == null)
			return;
		var constant = npc.actorData.constant;
		if (constant == null)
			return;
		var idKey = Std.string(npc.id);
		var px = npc.positionX;
		var py = npc.positionY;

		var aliveCombatant = allowSpawns && !npc.isDead() && npc.hitPoints > 0 && (getNpc(constant).isCombatant || constant == "REWARD_CHEST_A");

		for (zr in zones) {
			// 1. Match linked LETriggerable prop/gate (`triggerState`)
			if (!zr.targetIds.exists(idKey)) {
				for (t in zr.zone.targets) {
					if (t.constant == constant && Math.abs(px - t.x) < TARGET_TOLERANCE && Math.abs(py - t.y) < TARGET_TOLERANCE) {
						zr.targetIds.set(idKey, true);
						zr.targets.push({
							npc: npc,
							expectedActive: t.expectedActive,
							isPlate: t.isPlate,
							initialState: npc.triggerState
						});
						break;
					}
				}
			}

			// 2. Match newly spawned enemies/chests near linked generators only after a hero engaged the zone
			if (aliveCombatant && !zr.spawnIds.exists(idKey) && zr.zone.generators.length > 0) {
				if (!zr.hadHeroInside && !isAnyHeroNear(game, zr.zone.x, zr.zone.y, zr.zone.radius + SPAWN_HERO_MARGIN))
					continue;
				for (g in zr.zone.generators) {
					if (!spawnConstantMatches(g.spawnConstant, constant))
						continue;
					var dx = px - g.x;
					var dy = py - g.y;
					if (dx * dx + dy * dy <= SPAWN_RADIUS_SQ) {
						zr.spawnIds.set(idKey, true);
						zr.spawnNpcs.push(npc);
						zr.hadLiveSpawn = true;
						break;
					}
				}
			}
		}
	}

	public function onObjectGone(id:UInt):Void {
		var key = Std.string(id);
		for (zr in zones) {
			if (zr.spawnIds.exists(key)) {
				zr.spawnIds.remove(key);
				var i = zr.spawnNpcs.length - 1;
				while (i >= 0) {
					if (Std.string(zr.spawnNpcs[i].id) == key)
						zr.spawnNpcs.splice(i, 1);
					i--;
				}
			}
			if (zr.targetIds.exists(key)) {
				zr.targetIds.remove(key);
				var i = zr.targets.length - 1;
				while (i >= 0) {
					if (Std.string(zr.targets[i].npc.id) == key)
						zr.targets.splice(i, 1);
					i--;
				}
			}
		}
	}

	/** Refreshes `status` across all floor zones using live heroes, spawned enemies, and `triggerState`. */
	public function update(nowMs:Int, game:Null<DistributedDungeonFloor>):Void {
		if (zones.length == 0 || game == null || game.isDestroyed)
			return;

		// Collect live hero references once for the frame into the reusable buffer
		var owner = game.activeOwnerAvatar;
		var hasOwner = isLiveActor(owner);
		remotesBuf.resize(0);
		if (game.remoteHeroes != null) {
			for (k in game.remoteHeroes.keysToArray()) {
				var h = Std.downcast(game.remoteHeroes.itemFor(k), HeroGameObject);
				if (isLiveActor(h))
					remotesBuf.push(h);
			}
		}
		var remotes = remotesBuf.length > 0 ? remotesBuf : null;

		for (zr in zones) {
			var prevStatus = zr.status;
			var prevInside = zr.heroInsideNow;

			// Prune dead generator spawns
			var i = zr.spawnNpcs.length - 1;
			while (i >= 0) {
				var s = zr.spawnNpcs[i];
				if (s.isDestroyed || s.isDead() || s.hitPoints <= 0) {
					zr.spawnIds.remove(Std.string(s.id));
					zr.spawnNpcs.splice(i, 1);
				}
				i--;
			}
			zr.liveSpawns = zr.spawnNpcs.length;

			// Check hero entry (single hero vs ALL_HERO)
			var z = zr.zone;
			var r2 = z.radius * z.radius;
			var insideNow = false;
			if (z.isAllHero) {
				var allInside = hasOwner && inside(owner, z.x, z.y, r2);
				if (allInside && remotes != null) {
					for (h in remotes) {
						if (!inside(h, z.x, z.y, r2)) {
							allInside = false;
							break;
						}
					}
				}
				insideNow = allInside;
				if (allInside && !zr.hadHeroInside) {
					zr.hadHeroInside = true;
					zr.heroEnterMs = nowMs;
				}
			} else {
				var anyInside = hasOwner && inside(owner, z.x, z.y, r2);
				if (!anyInside && remotes != null) {
					for (h in remotes) {
						if (inside(h, z.x, z.y, r2)) {
							anyInside = true;
							break;
						}
					}
				}
				insideNow = anyInside;
				if (anyInside && !zr.hadHeroInside) {
					zr.hadHeroInside = true;
					zr.heroEnterMs = nowMs;
				}
			}
			zr.heroInsideNow = insideNow;

			// Check linked target triggerState (traps/gates/plates)
			var hasNonPlate = false;
			var allNonPlateTriggered = false;
			var nonPlateCount = 0;
			var nonPlateMatched = 0;
			var anyNonPlateTransitioned = false;
			for (t in zr.targets) {
				if (t.npc.isDestroyed)
					continue;
				var state = t.npc.triggerState;
				var want = t.expectedActive > 0;
				if (!t.isPlate) {
					hasNonPlate = true;
					nonPlateCount++;
					if (state == want)
						nonPlateMatched++;
					if (state != t.initialState && state == want)
						anyNonPlateTransitioned = true;
				}
			}
			allNonPlateTriggered = nonPlateCount > 0 && nonPlateMatched == nonPlateCount;

			// Derive runtime status
			if (zr.liveSpawns > 0) {
				zr.status = STATUS_SPAWNED_ALIVE;
			} else if (!z.isOnce && !z.hasGenerator) {
				// Repeatable trap zone (spikes/spears/flames on timer or pressure plate)
				zr.status = (hasNonPlate && (anyNonPlateTransitioned || allNonPlateTriggered)) ? STATUS_SPAWNED_ALIVE : STATUS_ARMED;
			} else {
				// One-shot or generator-backed zone
				if (zr.hadLiveSpawn) {
					zr.status = STATUS_TRIGGERED;
				} else if (hasNonPlate && allNonPlateTriggered && zr.hadHeroInside) {
					zr.status = STATUS_TRIGGERED;
				} else if (hasNonPlate && anyNonPlateTransitioned) {
					zr.status = STATUS_TRIGGERED;
				} else if (z.isOnce && zr.hadHeroInside && (!z.hasGenerator || nowMs - zr.heroEnterMs >= HERO_TRIGGER_DELAY_MS)) {
					zr.status = STATUS_TRIGGERED;
				} else {
					zr.status = STATUS_ARMED;
				}
			}

			if (zr.status != prevStatus || zr.heroInsideNow != prevInside)
				revision++;
		}
	}

	static function isAnyHeroNear(game:Null<DistributedDungeonFloor>, zx:Float, zy:Float, radius:Float):Bool {
		if (game == null || game.isDestroyed)
			return false;
		var r2 = radius * radius;
		if (isLiveActor(game.activeOwnerAvatar) && inside(game.activeOwnerAvatar, zx, zy, r2))
			return true;
		if (game.remoteHeroes != null) {
			for (k in game.remoteHeroes.keysToArray()) {
				var h = Std.downcast(game.remoteHeroes.itemFor(k), HeroGameObject);
				if (isLiveActor(h) && inside(h, zx, zy, r2))
					return true;
			}
		}
		return false;
	}

	static inline function spawnConstantMatches(expected:String, actual:String):Bool {
		if (expected == "FODDER" || expected == "BRUISER" || expected == "MINIBOSS")
			return actual != "REWARD_CHEST_A";
		return expected == actual;
	}

	static inline function isLiveActor(a:Null<ActorGameObject>):Bool {
		return a != null && !a.isDestroyed && !a.isDead() && !a.isInReviveState() && a.hitPoints > 0 && a.hasPosition;
	}

	static inline function inside(a:ActorGameObject, zx:Float, zy:Float, r2:Float):Bool {
		var dx = a.positionX - zx;
		var dy = a.positionY - zy;
		return dx * dx + dy * dy <= r2;
	}
}
