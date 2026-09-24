class_name SurpriseSfx
extends RefCounted
## Positional one-shots for the D20 surprise enemies (assets/audio/sfx/enemies/<id>.wav, made by
## tools/gen_audio.py). Kept outside Audio.SFX_PATHS so the audio lane's catalog stays untouched;
## missing files are skipped silently.

const DIR := "res://assets/audio/sfx/enemies/"
const PLAYER_SCRIPT = preload("res://scripts/enemies/surprise/surprise_sfx_player.gd")
const MIN_REPEAT_SECONDS := 0.07
const MAX_DISTANCE := 1800.0

static var _last_played: Dictionary = {}


static func play(source: Node2D, id: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	if source == null or not source.is_inside_tree():
		return
	var stream := _stream(id)
	if stream == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(id, -10.0)) < MIN_REPEAT_SECONDS:
		return
	_last_played[id] = now
	var audio := source.get_tree().root.get_node_or_null("Audio")
	if audio != null and bool(audio.get(&"_shutting_down")):
		return
	var player := AudioStreamPlayer2D.new()
	player.set_script(PLAYER_SCRIPT)
	player.stream = stream
	player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = MAX_DISTANCE
	player.attenuation = 1.4
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	var parent := source.get_tree().current_scene
	if parent == null:
		parent = source.get_tree().root
	parent.add_child(player)
	player.global_position = source.global_position
	player.play()


## No static stream cache: static vars outlive the scene tree and would leak the streams at
## exit. ResourceLoader already caches loaded resources while something references them.
static func _stream(id: StringName) -> AudioStream:
	var path := DIR + String(id) + ".wav"
	return load(path) as AudioStream if ResourceLoader.exists(path) else null
