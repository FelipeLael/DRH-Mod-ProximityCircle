package mods.proximity_circle;

/** Metadata for an NPC/prop constant read from GameMaster once per library analysis. */
typedef NpcMeta = {
	var isProp:Bool;
	var name:String;
	var isBoss:Bool;
	var isExploding:Bool;
	var isCombatant:Bool;
}

/** Expected generator spawn coordinates and constant linked to a trigger. */
typedef ZoneSpawnRef = {
	var x:Float;
	var y:Float;
	var spawnConstant:String;
	var maxSpawns:Int;
}

/** Expected trap/gate object coordinates and post-trigger `triggerState` (`1` = active, `0` = off). */
typedef ZoneTargetRef = {
	var x:Float;
	var y:Float;
	var constant:String;
	var expectedActive:Int;
	var isPlate:Bool;
}

/** Human-readable outcome, threat tier, and linked runtime sinks for a trigger or trap prop. */
typedef Outcome = {
	var summary:String;
	var severity:Int;
	var hasGenerator:Bool;
	var isDisarmOnly:Bool;
	var isGateOpenOnly:Bool;
	var generators:Array<ZoneSpawnRef>;
	var targets:Array<ZoneTargetRef>;
}

/** A zone in world units: its centre, radius, outcome, and linked runtime spawn/target refs. */
typedef Zone = {
	var x:Float;
	var y:Float;
	var radius:Float;
	var summary:String;
	var severity:Int;
	var isOnce:Bool;
	var isAllHero:Bool;
	var hasGenerator:Bool;
	var isDisarmOnly:Bool;
	var isGateOpenOnly:Bool;
	var generators:Array<ZoneSpawnRef>;
	var targets:Array<ZoneTargetRef>;
}

/** A destructible prop trap in world units: position, constant, and what happens if hit/broken. */
typedef PropTrap = {
	var x:Float;
	var y:Float;
	var constant:String;
	var propName:String;
	var triggerKind:String;
	var summary:String;
	var severity:Int;
	var hasGenerator:Bool;
}

typedef PropEntry = {
	var triggerKind:String;
	var outcome:Outcome;
}

/** Drawable proximity zones and destructible prop traps found in one library pass. */
typedef DrawableSet = {
	var zones:Map<String, Outcome>;
	var propTraps:Map<String, PropEntry>;
}

/** A tile as the mod reads it from the floor: its id in the tile library and its top-left corner. */
typedef TileInfo = {
	var id:String;
	var x:Int;
	var y:Int;
}

/**
 * An object of a tile in the library, as the library gives it: its id, type, constant and offset.
 * Flash's exporter omits `x` or `y` when 0, so coordinates and optional fields are nullable.
 */
typedef LibraryObject = {
	var id:String;
	var type:Null<String>;
	var constant:Null<String>;
	@:optional var x:Null<Float>;
	@:optional var y:Null<Float>;
	@:optional var radius:Null<Float>;
	@:optional var npcId:Null<String>;
	@:optional var spawnConstant:Null<String>;
	@:optional var maxSpawns:Null<Int>;
	@:optional var maxPopulation:Null<Int>;
	@:optional var triggerOnce:Null<Bool>;
}

/** A wire of the library: the object `triggerId` drives the object `triggerableId`. */
typedef Link = {
	var triggerId:String;
	var triggerableId:String;
}

/** One dash of a dashed circle, as angles in radians from the circle's east point. */
typedef Dash = {
	var from:Float;
	var to:Float;
}

/** Visual rhythm, stroke weight, and inward accent profile derived from a zone's severity tier. */
typedef TierProfile = {
	var pitch:Float;
	var fraction:Float;
	var coreW:Float;
	var inkW:Float;
	var washW:Float;
	var teethCount:Int;
	var teethDepth:Float;
	var isUtility:Bool;
}

private typedef SinkHit = {
	var object:LibraryObject;
	var active:Int;
}

/**
 * The zones' and prop-traps' rule, outcome classifier, colour selection and arithmetic, free of the game.
 */
class Ring {
	public static inline final TYPE = "LETrigger";

	public static inline final NPC_TYPE = "LENPC";

	public static inline final GEN_TYPE = "LENPCGenerator";

	public static inline final GEN_DEAD_TYPE = "LENPCGeneratorWithAllSpawnsDeadTrigger";

	public static inline final CONSTANT = "PROXIMITY_TRIGGER";

	public static inline final CONSTANT_ALL_HERO = "PROXIMITY_ALL_HERO";

	public static inline final LIFE_TRIGGER = "NPC_LIFE_TRIGGER";

	public static inline final DAMAGE_TRIGGER = "NPC_DAMAGE_TRIGGER";

	public static inline final SUICIDE = "NPC_SUICIDE_TRIGGER";

	public static inline final SEVERITY_BOSS = 3;

	public static inline final SEVERITY_AMBUSH = 2;

	public static inline final SEVERITY_TRAP = 1;

	public static inline final SEVERITY_GATE = 0;

	/** Objects that only pass a signal on: gates, timers and chained proximity zones. */
	static inline final GATE_TYPE = "LETriggerGate";

	static inline final NOT_GATE = "NOT_GATE";

	static inline final AUTO_TIMER = "AUTO_TIMER_TRIGGER";

	static inline final ASYM_AUTO_TIMER = "ASYM_AUTO_TIMER_TRIGGER";

	/** Non-gameplay feedback sinks that should not by themselves produce a hazard marker. */
	static inline final CAMERA_TRIGGERABLE_TYPE = "LETriggerableCamera";

	static inline final FLOOR_MESSAGE = "FLOOR_MESSAGE_TRIGGERABLE";

	static inline final PLAY_SOUND = "PLAY_SOUND_TRIGGERABLE";

	static inline final TIMELINE_TRIGGERABLE = "TIMELINE_TRIGGERABLE";

	/** Target arc pitch (dash + gap) in world units so small and large rings share the same rhythm. */
	public static inline final DASH_PITCH = 22.0;

	public static inline final MIN_DASHES = 8;

	/** Drawn share of each slot (leaves clean etched gaps around the dual-polarity dashes). */
	public static inline final DASH_FRACTION = 0.48;

	/**
	 * Restrained dungeon-mineral floor palette (Tufte Smallest Effective Difference + Ware Large
	 * Area Rule): low-saturation earth/mineral cores (30-56% HSV sat) paired with a warm charcoal
	 * under-stroke (#14110F) and distinct per-tier geometry for 9-biome & grayscale CVD legibility.
	 */
	public static inline final COLOR_TRAP:UInt = 0xC26B54; // Aged Terracotta

	public static inline final COLOR_AMBUSH:UInt = 0xC99A4E; // Tarnished Brass

	public static inline final COLOR_BOSS:UInt = 0xA34E68; // Muted Plum-Burgundy

	public static inline final COLOR_GATE:UInt = 0x6E9E9A; // Weathered Verdigris

	public static inline final COLOR_ACTIVE:UInt = 0xD96248; // Ember Vermilion (focal pop-out)

	public static inline final COLOR_CLEARED:UInt = 0x8C877E; // Stone Ash

	/** True when `object` is a hero proximity trigger zone (`PROXIMITY_TRIGGER` or `PROXIMITY_ALL_HERO`). */
	public static function isZone(object:LibraryObject):Bool {
		return object != null
			&& object.type == TYPE
			&& (object.constant == CONSTANT || object.constant == CONSTANT_ALL_HERO);
	}

	/** True when `object` watches a destructible NPC/prop (`NPC_LIFE_TRIGGER` or `NPC_DAMAGE_TRIGGER`). */
	public static function isWatchTrigger(object:LibraryObject):Bool {
		return object != null
			&& object.type == TYPE
			&& (object.constant == LIFE_TRIGGER || object.constant == DAMAGE_TRIGGER)
			&& object.npcId != null;
	}

	/** Returns the default restrained mineral trap color (per-tier colors live in `tierColor`). */
	public static function colorForFloor(theme:Null<String>, map:Null<String>):UInt {
		return COLOR_TRAP;
	}

	/** Restrained mineral pigment by threat tier (each tier also has unique CVD-safe geometry). */
	public static function tierColor(severity:Int):UInt {
		if (severity >= SEVERITY_BOSS)
			return COLOR_BOSS;
		if (severity >= SEVERITY_AMBUSH)
			return COLOR_AMBUSH;
		if (severity >= SEVERITY_TRAP)
			return COLOR_TRAP;
		return COLOR_GATE;
	}

	/**
	 * Pre-attentive geometric profile by threat tier (stroke weight, dash duty, and inward accents).
	 * Idle interior wash is 0 across all tiers (Ware's Large Area Rule); subtle wash appears only
	 * when active/firing or stepped on.
	 */
	public static function tierProfile(zone:Zone):TierProfile {
		if (zone.severity >= SEVERITY_BOSS) {
			return {
				pitch: 24.0,
				fraction: 0.72,
				coreW: 2.6,
				inkW: 5.4,
				washW: 12.0,
				teethCount: 4,
				teethDepth: 9.0,
				isUtility: false
			};
		}
		if (zone.severity >= SEVERITY_AMBUSH) {
			return {
				pitch: 26.0,
				fraction: 0.58,
				coreW: 2.2,
				inkW: 4.8,
				washW: 10.0,
				teethCount: 4,
				teethDepth: 7.5,
				isUtility: false
			};
		}
		if (zone.severity >= SEVERITY_TRAP) {
			return {
				pitch: 20.0,
				fraction: 0.50,
				coreW: 2.0,
				inkW: 4.4,
				washW: 9.0,
				teethCount: 0,
				teethDepth: 0.0,
				isUtility: false
			};
		}
		return {
			pitch: 14.0,
			fraction: 0.28,
			coreW: 1.7,
			inkW: 3.9,
			washW: 0.0,
			teethCount: 0,
			teethDepth: 0.0,
			isUtility: true
		};
	}

	/**
	 * Resolves drawable proximity zones and destructible prop traps along with human-readable
	 * outcome summaries and runtime sink references in one forward parity pass per trigger.
	 */
	public static function drawableSet(objects:Array<LibraryObject>, links:Array<Link>, getNpc:String->NpcMeta):DrawableSet {
		var known = new Map<String, LibraryObject>();
		var zones:Array<LibraryObject> = [];
		var watches:Array<LibraryObject> = [];
		for (object in objects) {
			if (object == null || object.id == null)
				continue;
			known.set(object.id, object);
			if (isZone(object))
				zones.push(object);
			else if (isWatchTrigger(object))
				watches.push(object);
		}

		var childrenOf = new Map<String, Array<String>>();
		for (link in links) {
			if (link == null || link.triggerId == null || link.triggerableId == null || !known.exists(link.triggerId) || !known.exists(link.triggerableId))
				continue;
			var list = childrenOf.get(link.triggerId);
			if (list == null) {
				list = [];
				childrenOf.set(link.triggerId, list);
			}
			list.push(link.triggerableId);
		}

		var zoneOut = new Map<String, Outcome>();
		for (zone in zones) {
			var hits = collectSinks(zone.id, 1, childrenOf, known, getNpc, false);
			if (hits.length > 0)
				zoneOut.set(zone.id, summarizeHits(hits, getNpc));
		}

		var propOut = new Map<String, PropEntry>();
		for (trig in watches) {
			// NPC_LIFE_TRIGGER drops from 1->0 when broken (0 = inactive until flipped by NOT_GATE);
			// NPC_DAMAGE_TRIGGER asserts 1 when damaged. Only sinks reached at active==1 fire on trigger.
			var startActive = trig.constant == DAMAGE_TRIGGER ? 1 : 0;
			var hits = collectSinks(trig.id, startActive, childrenOf, known, getNpc, true);
			if (hits.length == 0)
				continue;
			var npc = known.get(trig.npcId);
			if (npc == null || npc.id == null || npc.type != NPC_TYPE || npc.constant == null)
				continue;
			if (npc.constant.indexOf("WALL_SECRET") >= 0)
				continue;
			var meta = getNpc(npc.constant);
			if (!meta.isProp)
				continue;
			var outcome = summarizeHits(hits, getNpc);
			var kind = trig.constant == DAMAGE_TRIGGER ? "HIT" : "BREAK";
			var existing = propOut.get(npc.id);
			if (existing == null || kind == "HIT" && existing.triggerKind != "HIT" || outcome.severity > existing.outcome.severity)
				propOut.set(npc.id, {triggerKind: kind, outcome: outcome});
		}

		return {zones: zoneOut, propTraps: propOut};
	}

	/** Backwards-compatible helper returning only drawable proximity zone ids. */
	public static function drawable(objects:Array<LibraryObject>, links:Array<Link>):Map<String, Bool> {
		var set = drawableSet(objects, links, defaultNpcMeta);
		var out = new Map<String, Bool>();
		for (id in set.zones.keys())
			out.set(id, true);
		return out;
	}

	/** The zones of the floor's tiles that are in `drawable`, with world-space generator & target refs. */
	public static function zonesOf(tiles:Array<TileInfo>, objectsByTile:Map<String, Array<LibraryObject>>, drawable:Map<String, Outcome>):Array<Zone> {
		var out:Array<Zone> = [];
		for (tile in tiles) {
			if (tile == null || tile.id == null || !objectsByTile.exists(tile.id))
				continue;
			for (object in objectsByTile.get(tile.id)) {
				if (object == null || object.id == null || !isZone(object))
					continue;
				var outcome = drawable.get(object.id);
				if (outcome == null)
					continue;
				var r = coord(object.radius);
				if (r <= 0)
					continue;
				var worldGens:Array<ZoneSpawnRef> = [
					for (g in outcome.generators) {
						x: tile.x + g.x,
						y: tile.y + g.y,
						spawnConstant: g.spawnConstant,
						maxSpawns: g.maxSpawns
					}
				];
				var worldTargets:Array<ZoneTargetRef> = [
					for (t in outcome.targets) {
						x: tile.x + t.x,
						y: tile.y + t.y,
						constant: t.constant,
						expectedActive: t.expectedActive,
						isPlate: t.isPlate
					}
				];
				out.push({
					x: tile.x + coord(object.x),
					y: tile.y + coord(object.y),
					radius: r,
					summary: outcome.summary,
					severity: outcome.severity,
					isOnce: object.triggerOnce == true,
					isAllHero: object.constant == CONSTANT_ALL_HERO,
					hasGenerator: outcome.hasGenerator,
					isDisarmOnly: outcome.isDisarmOnly,
					isGateOpenOnly: outcome.isGateOpenOnly,
					generators: worldGens,
					targets: worldTargets
				});
			}
		}
		return out;
	}

	/** The destructible prop traps of the floor's tiles that are in `drawableProps`. */
	public static function propTrapsOf(tiles:Array<TileInfo>, objectsByTile:Map<String, Array<LibraryObject>>, drawableProps:Map<String, PropEntry>,
			getNpc:String->NpcMeta):Array<PropTrap> {
		var out:Array<PropTrap> = [];
		for (tile in tiles) {
			if (tile == null || tile.id == null || !objectsByTile.exists(tile.id))
				continue;
			for (object in objectsByTile.get(tile.id)) {
				if (object == null || object.id == null || object.constant == null)
					continue;
				var entry = drawableProps.get(object.id);
				if (entry == null)
					continue;
				out.push({
					x: tile.x + coord(object.x),
					y: tile.y + coord(object.y),
					constant: object.constant,
					propName: cleanPropName(getNpc(object.constant).name, object.constant),
					triggerKind: entry.triggerKind,
					summary: entry.outcome.summary,
					severity: entry.outcome.severity,
					hasGenerator: entry.outcome.hasGenerator
				});
			}
		}
		return out;
	}

	/** The dashes for a ring of `radius`: uniform world-space pitch, at least `MIN_DASHES`. */
	public static function dashesForRadius(radius:Float, pitch:Float = DASH_PITCH, fraction:Float = DASH_FRACTION):Array<Dash> {
		var raw = Math.round(2 * Math.PI * radius / pitch);
		var count = raw < MIN_DASHES ? MIN_DASHES : raw;
		var slot = 2 * Math.PI / count;
		var out:Array<Dash> = [];
		for (i in 0...count) {
			var from = i * slot;
			out.push({from: from, to: from + slot * fraction});
		}
		return out;
	}

	static function collectSinks(startId:String, startActive:Int, childrenOf:Map<String, Array<String>>, known:Map<String, LibraryObject>,
			getNpc:String->NpcMeta, onlyActivated:Bool):Array<SinkHit> {
		var seen0 = new Map<String, Bool>();
		var seen1 = new Map<String, Bool>();
		var qIds:Array<String> = [startId];
		var qStates:Array<Int> = [startActive];
		if (startActive == 0)
			seen0.set(startId, true);
		else
			seen1.set(startId, true);

		var hits:Array<SinkHit> = [];
		var hitKeys = new Map<String, Bool>();

		var head = 0;
		while (head < qIds.length) {
			var id = qIds[head];
			var state = qStates[head];
			head++;
			var nexts = childrenOf.get(id);
			if (nexts == null)
				continue;
			for (nextId in nexts) {
				var obj = known.get(nextId);
				if (obj == null)
					continue;
				var nextState = obj.constant == NOT_GATE ? (1 - state) : state;
				if (isPassing(obj)) {
					var visited = nextState == 0 ? seen0 : seen1;
					if (!visited.exists(nextId)) {
						visited.set(nextId, true);
						qIds.push(nextId);
						qStates.push(nextState);
					}
				} else if (obj.type != TYPE || obj.constant == SUICIDE) {
					if (isIgnoredSink(obj, known, getNpc))
						continue;
					if (onlyActivated && nextState != 1)
						continue;
					var key = nextId + ":" + nextState;
					if (!hitKeys.exists(key)) {
						hitKeys.set(key, true);
						hits.push({object: obj, active: nextState});
					}
				}
			}
		}
		return hits;
	}

	static function summarizeHits(hits:Array<SinkHit>, getNpc:String->NpcMeta):Outcome {
		var spawnCounts = new Map<String, Int>();
		var spawnOrder:Array<String> = [];
		var spawnMeta = new Map<String, {name:String, sev:Int}>();
		var otherClauses:Array<{label:String, sev:Int}> = [];
		var otherSeen = new Map<String, Bool>();
		var generators:Array<ZoneSpawnRef> = [];
		var targets:Array<ZoneTargetRef> = [];
		var maxSev = SEVERITY_GATE;
		var allDisarm = true;
		var allGateOpen = true;
		var hasAnyNonGen = false;

		for (hit in hits) {
			var obj = hit.object;
			if ((obj.type == GEN_TYPE || obj.type == GEN_DEAD_TYPE) && obj.spawnConstant != null) {
				if (hit.active == 0)
					continue;
				allDisarm = false;
				allGateOpen = false;
				var sc = obj.spawnConstant;
				var count = obj.maxSpawns != null && obj.maxSpawns > 0 ? obj.maxSpawns : 1;
				generators.push({
					x: coord(obj.x),
					y: coord(obj.y),
					spawnConstant: sc,
					maxSpawns: count
				});
				if (!spawnCounts.exists(sc)) {
					spawnCounts.set(sc, count);
					spawnOrder.push(sc);
					spawnMeta.set(sc, classifySpawn(sc, getNpc));
				} else {
					spawnCounts.set(sc, spawnCounts.get(sc) + count);
				}
				var sev = spawnMeta.get(sc).sev;
				if (sev > maxSev)
					maxSev = sev;
			} else {
				hasAnyNonGen = true;
				var classified = classifyNonGenerator(obj, hit.active);
				if (classified.sev > maxSev)
					maxSev = classified.sev;
				if (classified.label != "Disarms Trap")
					allDisarm = false;
				if (classified.label != "Opens Gate" && classified.label != "Opens Wall")
					allGateOpen = false;
				if (!otherSeen.exists(classified.label)) {
					otherSeen.set(classified.label, true);
					otherClauses.push(classified);
				}
				if (obj.constant != null && obj.constant != SUICIDE && obj.type == "LETriggerable") {
					targets.push({
						x: coord(obj.x),
						y: coord(obj.y),
						constant: obj.constant,
						expectedActive: hit.active,
						isPlate: obj.constant.indexOf("TRAP_TRIGGER") >= 0
					});
				}
			}
		}

		// Order spawn clauses by severity descending (Mini-Boss before Bruiser/Fodder).
		spawnOrder.sort(function(a:String, b:String):Int {
			return spawnMeta.get(b).sev - spawnMeta.get(a).sev;
		});

		var parts:Array<String> = [];
		for (sc in spawnOrder) {
			var total = spawnCounts.get(sc);
			var info = spawnMeta.get(sc);
			if (sc == "REWARD_CHEST_A") {
				parts.push(total > 1 ? total + "x Loot Chest" : "Loot Chest");
			} else if (info.sev == SEVERITY_BOSS) {
				if (sc == "MINIBOSS")
					parts.push(total > 1 ? total + "x Mini-Boss" : "Mini-Boss");
				else
					parts.push(total > 1 ? "Mini-Boss: " + total + "x " + info.name : "Mini-Boss: " + info.name);
			} else {
				parts.push((total > 1 ? total + "x " : "") + info.name);
			}
		}

		otherClauses.sort(function(a, b):Int return b.sev - a.sev);
		var firstIsBossOrChest = parts.length > 0 && (spawnOrder[0] == "REWARD_CHEST_A" || spawnMeta.get(spawnOrder[0]).sev == SEVERITY_BOSS);
		var spawnPrefix = parts.length > 0 && !firstIsBossOrChest ? "Spawns " : "";
		var combined:Array<String> = [];
		if (parts.length > 0)
			combined.push(spawnPrefix + parts.slice(0, 2).join(" + "));
		for (clause in otherClauses) {
			if (combined.length >= 2)
				break;
			if (parts.length > 0 && clause.label == "Breaks Wall/Cage")
				continue;
			combined.push(clause.label);
		}

		return {
			summary: combined.length > 0 ? combined.join(" + ") : "Trap Trigger",
			severity: maxSev,
			hasGenerator: generators.length > 0,
			isDisarmOnly: hasAnyNonGen && generators.length == 0 && allDisarm,
			isGateOpenOnly: hasAnyNonGen && generators.length == 0 && allGateOpen,
			generators: generators,
			targets: targets
		};
	}

	static function classifySpawn(spawnConstant:String, getNpc:String->NpcMeta):{name:String, sev:Int} {
		if (spawnConstant == "MINIBOSS")
			return {name: "Mini-Boss", sev: SEVERITY_BOSS};
		if (spawnConstant == "BRUISER")
			return {name: "Bruiser", sev: SEVERITY_AMBUSH};
		if (spawnConstant == "FODDER")
			return {name: "Fodder", sev: SEVERITY_AMBUSH};
		if (spawnConstant == "REWARD_CHEST_A")
			return {name: "Loot Chest", sev: SEVERITY_GATE};
		var meta = getNpc(spawnConstant);
		var name = meta.name != "" ? meta.name : humanizeConstant(spawnConstant);
		return {
			name: name,
			sev: meta.isBoss ? SEVERITY_BOSS : SEVERITY_AMBUSH
		};
	}

	static function classifyNonGenerator(obj:LibraryObject, active:Int):{label:String, sev:Int} {
		var c = obj.constant == null ? "" : obj.constant.toUpperCase();
		if (c == SUICIDE)
			return {label: "Breaks Wall/Cage", sev: SEVERITY_GATE};
		if (c.indexOf("FLOOR_FAILURE") >= 0)
			return {label: "Mission Failure", sev: SEVERITY_BOSS};
		if (c.indexOf("FLOOR_COMPLETE") >= 0 || c.indexOf("FLOOR_COMPLETION") >= 0)
			return {label: "Completes Floor", sev: SEVERITY_GATE};

		if (c.indexOf("EXITGATE") >= 0 || c.indexOf("EXIT_GATE") >= 0 || c.indexOf("GATE") >= 0 || c.indexOf("JAIL") >= 0 || c.indexOf("WALL") >= 0) {
			if (active == 0)
				return {label: c.indexOf("WALL") >= 0 ? "Opens Wall" : "Opens Gate", sev: SEVERITY_GATE};
			if (c.indexOf("JAIL") >= 0)
				return {label: "Jail Trap", sev: SEVERITY_TRAP};
			return {label: c.indexOf("WALL") >= 0 ? "Raises Wall" : "Locks Gate", sev: SEVERITY_GATE};
		}

		if (active == 0)
			return {label: "Disarms Trap", sev: SEVERITY_GATE};

		if (c.indexOf("FLAMESPIKE") >= 0)
			return {label: "Flame Spikes", sev: SEVERITY_TRAP};
		if (c.indexOf("FLAME") >= 0)
			return {label: "Flame Jet", sev: SEVERITY_TRAP};
		if (c.indexOf("SPIKE") >= 0)
			return {label: "Spike Trap", sev: SEVERITY_TRAP};
		if (c.indexOf("SPEAR") >= 0)
			return {label: "Spear Trap", sev: SEVERITY_TRAP};
		if (c.indexOf("ARROW") >= 0)
			return {label: "Arrow Trap", sev: SEVERITY_TRAP};
		if (c.indexOf("MINE_") >= 0)
			return {label: "Proximity Mines", sev: SEVERITY_TRAP};
		if (c.indexOf("FIREBOMB") >= 0)
			return {label: "Firebombs", sev: SEVERITY_TRAP};
		if (c.indexOf("BURNING_FIRE") >= 0)
			return {label: "Fire Trap", sev: SEVERITY_TRAP};
		if (c.indexOf("GARLIC") >= 0)
			return {label: "Garlic Trap", sev: SEVERITY_TRAP};
		if (c.indexOf("BLADE") >= 0 || c.indexOf("SLICER") >= 0)
			return {label: "Blade Trap", sev: SEVERITY_TRAP};
		if (c.indexOf("CRUSHER") >= 0)
			return {label: "Crusher Trap", sev: SEVERITY_TRAP};
		if (c.indexOf("MACE") >= 0)
			return {label: "Swinging Mace", sev: SEVERITY_TRAP};
		if (c.indexOf("BOULDER") >= 0)
			return {label: "Boulder Trap", sev: SEVERITY_TRAP};
		if (c.indexOf("LOG") >= 0)
			return {label: "Rolling Log", sev: SEVERITY_TRAP};
		if (c.indexOf("LAVA") >= 0)
			return {label: "Lava Trap", sev: SEVERITY_TRAP};
		if (c.indexOf("EMITTER") >= 0)
			return {label: "Magic Trap", sev: SEVERITY_TRAP};
		if (c.indexOf("LOKI") >= 0 || c.indexOf("THOR") >= 0)
			return {label: "Statue Trap", sev: SEVERITY_TRAP};
		return {label: "Floor Trap", sev: SEVERITY_TRAP};
	}

	static function cleanPropName(rawName:String, fallbackConst:String):String {
		var s = rawName != null && rawName != "" ? rawName : humanizeConstant(fallbackConst);
		for (prefix in ["Smashable ", "Trap "])
			if (StringTools.startsWith(s, prefix))
				s = s.substr(prefix.length);
		var words = s.split(" ");
		var out:Array<String> = [];
		for (w in words) {
			if (w == "" || w == "A" || w == "B" || w == "C" || w == "D")
				continue;
			out.push(w.charAt(0).toUpperCase() + w.substr(1));
		}
		return out.length > 0 ? out.join(" ") : "Trap Object";
	}

	static function humanizeConstant(c:String):String {
		var parts = c.split("_");
		var out:Array<String> = [];
		for (p in parts)
			if (p != "" && p.length > 1)
				out.push(p.charAt(0).toUpperCase() + p.substr(1).toLowerCase());
		return out.join(" ");
	}

	static inline function coord(value:Null<Float>):Float {
		return value == null || Math.isNaN(value) ? 0.0 : value;
	}

	/** Gates, timers and proximity zones only pass a signal on. */
	static function isPassing(object:LibraryObject):Bool {
		return object.type == GATE_TYPE
			|| isZone(object)
			|| object.constant == AUTO_TIMER
			|| object.constant == ASYM_AUTO_TIMER;
	}

	/** Exploding-barrel fuses and purely cosmetic audio/camera/text triggers do not count as hazards. */
	static function isIgnoredSink(object:LibraryObject, known:Map<String, LibraryObject>, getNpc:String->NpcMeta):Bool {
		var c = object.constant == null ? "" : object.constant;
		if (c == SUICIDE) {
			if (object.npcId == null)
				return true;
			var npc = known.get(object.npcId);
			if (npc == null || npc.constant == null)
				return true;
			return getNpc(npc.constant).isExploding;
		}
		return object.type == CAMERA_TRIGGERABLE_TYPE
			|| c == FLOOR_MESSAGE
			|| c == PLAY_SOUND
			|| c == TIMELINE_TRIGGERABLE
			|| c.indexOf("SOUNDOBJ") >= 0;
	}

	static function defaultNpcMeta(constant:String):NpcMeta {
		return {
			isProp: false,
			name: humanizeConstant(constant),
			isBoss: constant.indexOf("BOSS") >= 0 || constant.indexOf("JUGGERNAUT") >= 0,
			isExploding: constant.indexOf("EXPLODING_BARREL") >= 0,
			isCombatant: false
		};
	}
}
