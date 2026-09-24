class_name TrialsEntry
extends RefCounted
## Entry and exit of the post-ending Trials (docs/features/trials.md). The Trials run on a fixed
## full kit in GameState; the campaign snapshot loaded at entry is kept here and restored before
## anything is saved, so the only change a trial can make to the campaign save is a better
## `trial_bests` entry.

const TITLE_SCENE := "res://scenes/ui/start_menu.tscn"
const TITLE_META := &"hollowtide_returned_to_title"

static var mode: StringName = TrialCatalog.GAUNTLET
## Campaign state loaded from disk at entry; empty when a trial was launched without a save.
static var campaign_snapshot: Dictionary = {}


## Reads the campaign save without disturbing GameState: whether the campaign is finished and the
## stored best results.
static func peek() -> Dictionary:
	var state := _node("GameState")
	var store := _node("SaveStore")
	var result := {"finished": false, "records": {}}
	if state == null or store == null:
		return result
	var before: Dictionary = state.call("snapshot")
	if store.call("load_game") == OK:
		result["finished"] = bool(state.call("has_world_flag", TrialCatalog.UNLOCK_FLAG))
		result["records"] = (state.get("trial_bests") as Dictionary).duplicate(true)
	state.call("restore_snapshot", before)
	return result


static func is_unlocked() -> bool:
	return bool(peek()["finished"])


## Loads the finished campaign save, remembers it, equips the trial kit and changes scene. Returns
## false (and changes nothing) when there is no finished save.
static func start(requested: StringName) -> bool:
	if not prepare(requested):
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.paused = false
		tree.change_scene_to_file(TrialCatalog.SCENE)
	return true


static func prepare(requested: StringName) -> bool:
	var state := _node("GameState")
	var store := _node("SaveStore")
	if state == null or store == null or not TrialCatalog.is_mode(requested):
		return false
	var before: Dictionary = state.call("snapshot")
	if store.call("load_game") != OK or not state.call("has_world_flag", TrialCatalog.UNLOCK_FLAG):
		state.call("restore_snapshot", before)
		return false
	campaign_snapshot = state.call("snapshot")
	mode = requested
	apply_kit()
	return true


## Replaces GameState with the fixed full kit at full health and ammunition.
static func apply_kit() -> void:
	GameState.reset_progress()
	for id in TrialCatalog.KIT_ABILITIES:
		GameState.unlock_ability(id)
	for index in ContentCatalog.MAX_ENERGY_TANKS:
		GameState.collect_pickup("trials.energy.%d" % index, &"energy_tank")
	for index in ContentCatalog.MAX_MISSILE_TANKS:
		GameState.collect_pickup("trials.quiver.%d" % index, &"missile_tank")
	GameState.set_active_beam(&"base")
	GameState.refill()


## Records a clear. Restores the campaign snapshot, keeps the result only when it beats the stored
## best, and saves only then. Returns the previous best, whether this run is the new best and the
## save result (ERR_UNAVAILABLE without a campaign snapshot, OK when nothing needed saving).
static func record(finished_mode: StringName, time_ms: int, hits: int) -> Dictionary:
	var outcome := {"previous": {}, "new_best": false, "saved": ERR_UNAVAILABLE}
	if campaign_snapshot.is_empty():
		return outcome
	GameState.restore_snapshot(campaign_snapshot)
	var records: Dictionary = GameState.trial_bests
	outcome["previous"] = TrialRecords.best(records, finished_mode)
	outcome["saved"] = OK
	if TrialRecords.is_better(records, finished_mode, time_ms):
		GameState.trial_bests = TrialRecords.with_result(records, finished_mode, time_ms, hits)
		var store := _node("SaveStore")
		var saved: Error = store.call("save_game") if store != null else ERR_UNAVAILABLE
		outcome["saved"] = saved
		if saved == OK:
			outcome["new_best"] = true
		else:
			GameState.trial_bests = records
	campaign_snapshot = GameState.snapshot()
	return outcome


## Leaves the Trials without saving: GameState returns to the campaign state loaded at entry.
static func leave_to_title() -> void:
	if not campaign_snapshot.is_empty():
		GameState.restore_snapshot(campaign_snapshot)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.paused = false
	Engine.set_meta(TITLE_META, true)
	tree.change_scene_to_file(TITLE_SCENE)


static func _node(autoload: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload)
