extends Node
## Playtest agent adapter for the Trials (docs/features/trials.md): hosts a TrialsRoot and exposes
## the `current_room`, `current_room_id`, `room_changed` and `_busy` contract that the loop and the
## telemetry read from CampaignRoot. The trial runs on its own fixed kit and saves nothing, because
## no campaign snapshot is set (TrialsEntry.record needs one to write).

signal room_changed(room_id: String)

const TRIALS_SCENE := preload("res://scenes/trials/trials.tscn")

var trials: TrialsRoot
## The trial's run_finished result ({mode, cleared, time_ms, hits}); empty while it runs.
var result: Dictionary = {}
var current_room: Node2D:
	get:
		return trials.room if is_instance_valid(trials) else null
var current_room_id: String:
	get:
		return _room_id()
var player: Player:
	get:
		return trials.player if is_instance_valid(trials) else null
## True once the trial is over, so the loop stops deciding.
var _busy: bool:
	get:
		return not result.is_empty()
var _last_room: Node2D


func _init(mode: StringName) -> void:
	TrialsEntry.campaign_snapshot = {}
	TrialsEntry.mode = mode
	trials = TRIALS_SCENE.instantiate() as TrialsRoot
	trials.run_finished.connect(func(finished: Dictionary) -> void: result = finished)
	add_child(trials)


func _ready() -> void:
	_last_room = current_room


func _physics_process(_delta: float) -> void:
	if current_room != _last_room:
		_last_room = current_room
		if current_room != null:
			room_changed.emit(_room_id())


func _room_id() -> String:
	if not is_instance_valid(trials):
		return ""
	if trials.mode == TrialCatalog.BOSS_RUSH and trials.boss_index >= 0:
		return "trials_%s" % TrialCatalog.BOSSES[trials.boss_index]
	return "trials_%s" % trials.mode
