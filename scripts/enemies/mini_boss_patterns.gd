extends RefCounted
## Registry of the optional mini-bosses (docs/features/mini-bosses.md). Each boss owns one data
## file under scripts/enemies/mini/<id>.gd with the same constants; this file only merges them, so a
## new boss never edits boss_patterns.gd. A boss whose ROTATIONS are empty is a stub: known to the
## catalog and layouts but not fightable yet.
##
## Data file contract (all constants, all optional except ID, MAX_HEALTH, CONTACT_DAMAGE):
##   ID, MAX_HEALTH, CONTACT_DAMAGE, ACCENT (Color), CHARGE_SPEED,
##   TIMING {attack: {telegraph, active, punish}}, CHARGES [attack], MOVE_SPEEDS [stage1, stage2],
##   ROTATIONS [stage 1 chains, stage 2 chains]
## Emission hooks (static, optional): plan(boss, attack, result, target, helpers) fills
## result["directions"/"marks"/...]; emissions(boss, attack, locked, helpers) -> Array of shots
## (same dictionaries as boss_attacks.gd `_shot`); `helpers` is the boss_attacks.gd script.
## Visual hook (static, optional): draw_body(boss, canvas) in scripts/enemies/effects/.

const STAGE_COUNT := 2
## Health ratio at or below which stage 2 starts.
const STAGE_THRESHOLDS: Array[float] = [0.5]
## Stage 2 uses protection row M2 (Harpoon only during the punish window).
const ARMORED_STAGE := 2
const OPENINGS_PER_STAGE := 3
const IDLE_SECONDS: Array[float] = [1.1, 0.8]
const MIN_PUNISH: Array[float] = [1.2, 1.4]

const FERNMAW = preload("res://scripts/enemies/mini/fernmaw.gd")
const TOLLWING = preload("res://scripts/enemies/mini/tollwing.gd")
const RIMEWEAVER = preload("res://scripts/enemies/mini/rimeweaver.gd")
const EMBERKITE = preload("res://scripts/enemies/mini/emberkite.gd")
const LANTERNJAW = preload("res://scripts/enemies/mini/lanternjaw.gd")


static func tables() -> Array:
	return [FERNMAW, TOLLWING, RIMEWEAVER, EMBERKITE, LANTERNJAW]


static func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for table in tables():
		result.append(table.ID)
	return result


## Ids that have a rotation, i.e. can be fought.
static func implemented_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for table in tables():
		if not table.ROTATIONS.is_empty():
			result.append(table.ID)
	return result


static func has(id: StringName) -> bool:
	return table_for(id) != null


static func table_for(id: StringName):
	for table in tables():
		if table.ID == id:
			return table
	return null


static func table_for_attack(attack: StringName):
	for table in tables():
		if table.TIMING.has(attack):
			return table
	return null


static func has_attack(attack: StringName) -> bool:
	return table_for_attack(attack) != null


static func timing(attack: StringName) -> Dictionary:
	return table_for_attack(attack).TIMING[attack]


static func is_charge(attack: StringName) -> bool:
	var table = table_for_attack(attack)
	return table != null and table.CHARGES.has(attack)


static func charge_speed(attack: StringName) -> float:
	var table = table_for_attack(attack)
	return float(table.CHARGE_SPEED) if table != null else 600.0


static func data(id: StringName) -> Dictionary:
	var table = table_for(id)
	if table == null:
		return {}
	return {"max_health": table.MAX_HEALTH, "contact_damage": table.CONTACT_DAMAGE}


static func accent(id: StringName) -> Color:
	var table = table_for(id)
	return table.ACCENT if table != null else Color(1.0, 0.76, 0.24, 1.0)


static func plan(
	boss: Node2D, attack: StringName, result: Dictionary, target: Vector2, helpers
) -> void:
	var table = table_for_attack(attack)
	if table != null and table.has_method(&"plan"):
		table.plan(boss, attack, result, target, helpers)


static func emissions(
	boss: Node2D, attack: StringName, locked: Dictionary, helpers
) -> Array[Dictionary]:
	var table = table_for_attack(attack)
	if table != null and table.has_method(&"emissions"):
		return table.emissions(boss, attack, locked, helpers)
	return []
