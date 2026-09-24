extends Node
## Music, area ambience and SFX. Buses: Master, Music, SFX, Ambience.
## Public API: play_sfx, play_area, play_music, stop_music, set_boss_music,
## configure_positional_loop/one_shot, clear_positional_player, shutdown.

const AREA_IDS: Array[StringName] = [&"fringe", &"nexus", &"vaults", &"kiln", &"depths"]
const SFX_PATHS: Dictionary[StringName, String] = {
	&"jump": "res://assets/audio/sfx/jump.wav",
	&"land": "res://assets/audio/sfx/land.wav",
	&"step": "res://assets/audio/sfx/step.wav",
	&"beam_fire": "res://assets/audio/sfx/beam_fire.wav",
	&"missile_fire": "res://assets/audio/sfx/missile_fire.wav",
	&"beam_ricochet": "res://assets/audio/sfx/beam_ricochet.wav",
	&"missile_hit": "res://assets/audio/sfx/missile_hit.wav",
	&"enemy_death": "res://assets/audio/sfx/enemy_death.wav",
	&"orb_pickup": "res://assets/audio/sfx/orb_pickup.wav",
	&"weapon_pickup": "res://assets/audio/sfx/weapon_pickup.wav",
	&"slip_in": "res://assets/audio/sfx/slip_in.wav",
	&"slip_out": "res://assets/audio/sfx/slip_out.wav",
	&"player_hurt": "res://assets/audio/sfx/player_hurt.wav",
	&"player_death": "res://assets/audio/sfx/player_death.wav",
	&"bomb_place": "res://assets/audio/sfx/bomb_place.wav",
	&"bomb_explode": "res://assets/audio/sfx/bomb_explode.wav",
	&"freeze": "res://assets/audio/sfx/freeze.wav",
	&"wave_fire": "res://assets/audio/sfx/wave_fire.wav",
	&"dash_strike": "res://assets/audio/sfx/dash_strike.wav",
	&"tank_pickup": "res://assets/audio/sfx/tank_pickup.wav",
	&"boss_defeated": "res://assets/audio/sfx/boss_defeated.wav",
	&"weapon_switch": "res://assets/audio/sfx/weapon_switch.wav",
	&"dash_launch": "res://assets/audio/sfx/dash_launch.wav",
	&"flux_shield": "res://assets/audio/sfx/flux_shield.wav",
	&"flux_burst": "res://assets/audio/sfx/flux_burst.wav",
	&"echo_scan": "res://assets/audio/sfx/echo_scan.wav",
	&"flux_empty": "res://assets/audio/sfx/flux_empty.wav",
	&"enemy_hit": "res://assets/audio/sfx/enemy_hit.wav",
	&"armor_clink": "res://assets/audio/sfx/armor_clink.wav",
	&"boss_open": "res://assets/audio/sfx/boss_open.wav",
	&"boss_close": "res://assets/audio/sfx/boss_close.wav",
	&"boss_phase": "res://assets/audio/sfx/boss_phase.wav",
	&"boss_telegraph": "res://assets/audio/sfx/boss_telegraph.wav",
	&"ice_shatter": "res://assets/audio/sfx/ice_shatter.wav",
	&"boss_explosion": "res://assets/audio/sfx/boss_explosion.wav",
	# Arsenal (D19).
	&"harpoon_fire": "res://assets/audio/sfx/harpoon_fire.wav",
	&"harpoon_hit": "res://assets/audio/sfx/harpoon_hit.wav",
	&"harpoon_embed": "res://assets/audio/sfx/harpoon_embed.wav",
	&"bubble_fire": "res://assets/audio/sfx/bubble_fire.wav",
	&"bubble_trap": "res://assets/audio/sfx/bubble_trap.wav",
	&"bubble_pop": "res://assets/audio/sfx/bubble_pop.wav",
	&"echo_fire": "res://assets/audio/sfx/echo_fire.wav",
	&"echo_bounce": "res://assets/audio/sfx/echo_bounce.wav",
	&"pulse_charge": "res://assets/audio/sfx/pulse_charge.wav",
	&"pulse_burst": "res://assets/audio/sfx/pulse_burst.wav",
	&"dash": "res://assets/audio/sfx/dash.wav",
	&"dash_hit": "res://assets/audio/sfx/dash_hit.wav",
	&"barrier_break": "res://assets/audio/sfx/barrier_break.wav",
}
const AMBIENT_PATHS: Dictionary[StringName, String] = {
	&"fire_loop": "res://assets/audio/sfx/fire_loop.wav",
	&"lava_loop": "res://assets/audio/sfx/lava_loop.wav",
	&"water_loop": "res://assets/audio/sfx/water_loop.wav",
	&"cold_ambience": "res://assets/audio/sfx/cold_ambience.wav",
	&"depths_pressure": "res://assets/audio/sfx/depths_pressure.wav",
	&"steam_vent": "res://assets/audio/sfx/steam_vent.wav",
}
const AMBIENT_LOOP_ENDS: Dictionary[StringName, int] = {
	&"fire_loop": 264600,
	&"lava_loop": 352800,
	&"water_loop": 352800,
	&"cold_ambience": 352800,
	&"depths_pressure": 352800,
}
const STEP_VARIANT_PATHS: Array[String] = [
	"res://assets/audio/sfx/step.wav",
	"res://assets/audio/sfx/step_2.wav",
	"res://assets/audio/sfx/step_3.wav",
]
const FOOTSTEP_DIR := "res://assets/audio/sfx/footsteps/"
const BUS_LAYOUT_PATH := "res://assets/audio/default_bus_layout.tres"
const MUSIC_PATHS: Dictionary[StringName, String] = {
	&"fringe": "res://assets/audio/music/fringe.ogg",
	&"nexus": "res://assets/audio/music/nexus.ogg",
	&"vaults": "res://assets/audio/music/vaults.ogg",
	&"kiln": "res://assets/audio/music/kiln.ogg",
	&"depths": "res://assets/audio/music/depths.ogg",
	&"boss": "res://assets/audio/music/boss.ogg",
	&"title": "res://assets/audio/music/title.ogg",
	&"ending": "res://assets/audio/music/ending.ogg",
}
# Older callers ask for these names.
const MUSIC_ALIASES: Dictionary[StringName, StringName] = {
	&"cave_theme": &"title",
	&"menu": &"title",
	&"credits": &"ending",
}
const NON_LOOPING_MUSIC: Array[StringName] = [&"ending"]
# Tracks are mastered around -17 LUFS (boss -16, title/ending -18); these trims seat music
# below player cues without touching the Music bus the settings menu owns.
const MUSIC_VOLUME_DB: Dictionary[StringName, float] = {
	&"fringe": -5.0,
	&"nexus": -5.0,
	&"vaults": -5.0,
	&"kiln": -5.5,
	&"depths": -5.0,
	&"boss": -6.0,
	&"title": -4.0,
	&"ending": -4.0,
}
const SFX_VOLUME_DB: Dictionary[StringName, float] = {
	&"jump": -3.0,
	&"weapon_switch": -8.0,
	&"dash_launch": -7.0,
	# Arsenal (D19).
	&"echo_bounce": -6.0,
	&"bubble_fire": -3.0,
	&"dash": -4.0,
}
const AMBIENCE_DIR := "res://assets/audio/ambience/"
const AMBIENCE_BED_DB := 0.0
# Randomized one-shot layers per area: file <area>_<kind>_<n>.ogg with n in 1..count.
# every = seconds between events; db = random volume range.
const AMBIENCE_LAYERS: Dictionary[StringName, Array] = {
	&"fringe":
	[
		{"kind": "drip", "count": 4, "every": Vector2(2.0, 6.5), "db": Vector2(-19, -11)},
		{"kind": "gust", "count": 3, "every": Vector2(11.0, 24.0), "db": Vector2(-17, -10)},
		{"kind": "pebbles", "count": 3, "every": Vector2(18.0, 40.0), "db": Vector2(-21, -14)},
	],
	&"nexus":
	[
		{"kind": "plop", "count": 4, "every": Vector2(1.6, 5.0), "db": Vector2(-18, -11)},
		{"kind": "hum", "count": 3, "every": Vector2(14.0, 30.0), "db": Vector2(-20, -13)},
		{"kind": "ring", "count": 3, "every": Vector2(12.0, 28.0), "db": Vector2(-22, -15)},
	],
	&"vaults":
	[
		{"kind": "creak", "count": 4, "every": Vector2(5.0, 13.0), "db": Vector2(-19, -12)},
		{"kind": "tinkle", "count": 3, "every": Vector2(6.0, 16.0), "db": Vector2(-21, -14)},
		{"kind": "crack", "count": 2, "every": Vector2(25.0, 55.0), "db": Vector2(-18, -12)},
	],
	&"kiln":
	[
		{"kind": "bubble", "count": 4, "every": Vector2(1.8, 5.5), "db": Vector2(-17, -10)},
		{"kind": "steam", "count": 3, "every": Vector2(7.0, 18.0), "db": Vector2(-21, -14)},
		{"kind": "boom", "count": 2, "every": Vector2(20.0, 45.0), "db": Vector2(-16, -10)},
		{"kind": "clank", "count": 3, "every": Vector2(9.0, 22.0), "db": Vector2(-23, -16)},
	],
	&"depths":
	[
		{"kind": "groan", "count": 3, "every": Vector2(16.0, 34.0), "db": Vector2(-15, -9)},
		{"kind": "knock", "count": 3, "every": Vector2(8.0, 20.0), "db": Vector2(-19, -12)},
		{"kind": "bubbles", "count": 3, "every": Vector2(5.0, 14.0), "db": Vector2(-21, -14)},
	],
}
const SFX_POOL_SIZE := 16
const AMBIENCE_POOL_SIZE := 6
const SILENT_DB := -60.0
const MUSIC_FADE := 2.5
const BOSS_FADE := 1.0
const AMBIENCE_FADE := 3.0
const RESUME_WINDOW_MSEC := 150000
const BOSS_POLL := 0.25
const BOSS_RELEASE := 2.5

var _sfx_streams: Dictionary[StringName, AudioStream] = {}
var _ambient_streams: Dictionary[StringName, AudioStreamWAV] = {}
var _music_streams: Dictionary[StringName, AudioStream] = {}
var _ambience_streams: Dictionary[String, AudioStream] = {}
var _step_streams: Array[AudioStream] = []
var _area_steps: Dictionary[StringName, Array] = {}
var _area_lands: Dictionary[StringName, AudioStream] = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _music_players: Array[AudioStreamPlayer] = []
var _bed_players: Array[AudioStreamPlayer] = []
var _ambience_players: Array[AudioStreamPlayer2D] = []
var _tweens: Dictionary[Node, Tween] = {}
var _next_sfx_player := 0
var _last_step_variant := -1
## Active music player (kept for older tooling that inspects it).
var _music_player: AudioStreamPlayer
var _music_active := 0
var _bed_active := 0
var _active_beam_snapshot: StringName = &""
var _current_music_id: StringName = &""
var _current_area: StringName = &""
var _resume: Dictionary[StringName, Vector2] = {}
var _layer_timers: Array[float] = []
var _layer_last: Array[int] = []
var _boss_forced := false
var _boss_active := false
var _boss_poll := 0.0
var _boss_release := 0.0
var _shutting_down := false
var _cleanup_complete := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	tree_exiting.connect(_cleanup)
	_active_beam_snapshot = GameState.active_beam
	if not GameState.state_changed.is_connected(_on_game_state_changed):
		GameState.state_changed.connect(_on_game_state_changed)
	for name in SFX_PATHS:
		var stream: AudioStream = _load_stream(SFX_PATHS[name])
		if stream != null:
			_sfx_streams[name] = stream
	for path in STEP_VARIANT_PATHS:
		var step_stream: AudioStream = _load_stream(path)
		if step_stream != null:
			_step_streams.append(step_stream)
	for area in AREA_IDS:
		var steps: Array[AudioStream] = []
		for variant in range(1, 4):
			var step := _load_stream("%s%s_step_%d.wav" % [FOOTSTEP_DIR, area, variant], false)
			if step != null:
				steps.append(step)
		_area_steps[area] = steps
		var land := _load_stream("%s%s_land.wav" % [FOOTSTEP_DIR, area], false)
		if land != null:
			_area_lands[area] = land
	for name in MUSIC_PATHS:
		var stream: AudioStream = _load_stream(MUSIC_PATHS[name])
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = not NON_LOOPING_MUSIC.has(name)
		if stream != null:
			_music_streams[name] = stream
	for name in AMBIENT_PATHS:
		var stream := _load_stream(AMBIENT_PATHS[name]) as AudioStreamWAV
		if stream != null:
			_ambient_streams[name] = stream

	for index in 2:
		var music := AudioStreamPlayer.new()
		music.name = "Music%d" % index
		music.bus = &"Music"
		add_child(music)
		_music_players.append(music)
		var bed := AudioStreamPlayer.new()
		bed.name = "AmbienceBed%d" % index
		bed.bus = &"Ambience"
		add_child(bed)
		_bed_players.append(bed)
	_music_player = _music_players[0]
	for index in AMBIENCE_POOL_SIZE:
		var one_shot := AudioStreamPlayer2D.new()
		one_shot.name = "AmbienceOneShot%d" % index
		one_shot.bus = &"Ambience"
		one_shot.max_distance = 4000.0
		one_shot.attenuation = 0.5
		add_child(one_shot)
		_ambience_players.append(one_shot)
	for index in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		player.finished.connect(_on_sfx_finished.bind(player))
		add_child(player)
		_sfx_players.append(player)


func _ensure_buses() -> void:
	# project.godot loads the layout via audio/buses/default_bus_layout. This guard is a no-op then;
	# it only matters for isolated harness projects (check_audio_catalog.py) without that key.
	if AudioServer.get_bus_index(&"Ambience") >= 0:
		return
	var layout := load(BUS_LAYOUT_PATH) as AudioBusLayout
	if layout != null:
		AudioServer.set_bus_layout(layout)


func _process(delta: float) -> void:
	if _shutting_down:
		return
	_tick_ambience(delta)
	_boss_poll -= delta
	if _boss_poll <= 0.0:
		_boss_poll = BOSS_POLL
		_update_boss_music()


# --- SFX -------------------------------------------------------------------------------


func play_sfx(name: StringName) -> void:
	if _shutting_down:
		return
	if not _sfx_streams.has(name):
		if SFX_PATHS.has(name):
			push_warning("Audio: unavailable SFX '%s'." % name)
		else:
			push_warning("Audio: unknown SFX '%s'." % name)
		return
	var stream: AudioStream = _sfx_streams[name]
	if name == &"step":
		stream = _pick_step(stream)
	elif name == &"land" and _area_lands.has(_current_area):
		stream = _area_lands[_current_area]
	for existing_player in _sfx_players:
		if existing_player.playing and existing_player.stream == stream:
			return

	var player: AudioStreamPlayer = null
	for offset in SFX_POOL_SIZE:
		var index: int = (_next_sfx_player + offset) % SFX_POOL_SIZE
		if not _sfx_players[index].playing:
			player = _sfx_players[index]
			_next_sfx_player = (index + 1) % SFX_POOL_SIZE
			break
	if player == null:
		return

	player.stream = stream
	player.volume_db = float(SFX_VOLUME_DB.get(name, 0.0))
	player.pitch_scale = randf_range(0.94, 1.06) if name == &"step" else 1.0
	player.play()


func _pick_step(fallback: AudioStream) -> AudioStream:
	var pool: Array = _area_steps.get(_current_area, [])
	if pool.is_empty():
		pool = _step_streams
	if pool.is_empty():
		return fallback
	var variant := randi_range(0, pool.size() - 1)
	if pool.size() > 1 and variant == _last_step_variant:
		variant = (variant + randi_range(1, pool.size() - 1)) % pool.size()
	_last_step_variant = variant
	return pool[variant]


func _on_sfx_finished(player: AudioStreamPlayer) -> void:
	# Pools retain players, not finished stream refs. This also bounds hot-reload lifetime.
	if is_instance_valid(player) and not player.playing:
		player.stream = null


# --- positional emitters -----------------------------------------------------------------


func configure_positional_loop(player: AudioStreamPlayer2D, id: StringName) -> bool:
	clear_positional_player(player)
	if not AMBIENT_LOOP_ENDS.has(id) or not _ambient_streams.has(id):
		return false
	var stream := _ambient_streams[id].duplicate() as AudioStreamWAV
	if stream == null:
		return false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = AMBIENT_LOOP_ENDS[id]
	_configure_positional_player(player, stream, &"Ambience")
	return true


func configure_positional_one_shot(player: AudioStreamPlayer2D, id: StringName) -> bool:
	clear_positional_player(player)
	if id != &"steam_vent" or not _ambient_streams.has(id):
		return false
	var stream := _ambient_streams[id].duplicate() as AudioStreamWAV
	if stream == null:
		return false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_configure_positional_player(player, stream, &"SFX")
	return true


func clear_positional_player(player: AudioStreamPlayer2D) -> void:
	if not is_instance_valid(player):
		return
	player.stop()
	player.stream = null


func _configure_positional_player(
	player: AudioStreamPlayer2D, stream: AudioStreamWAV, bus: StringName
) -> void:
	player.stream = stream
	player.bus = bus
	player.volume_db = 0.0
	player.attenuation = 1.0
	player.max_distance = 1400.0
	player.process_mode = Node.PROCESS_MODE_PAUSABLE


func _on_game_state_changed() -> void:
	var active_beam: StringName = GameState.active_beam
	if _active_beam_snapshot == &"":
		_active_beam_snapshot = active_beam
		return
	var previous_beam := _active_beam_snapshot
	_active_beam_snapshot = active_beam
	if previous_beam == active_beam:
		return
	play_sfx(&"weapon_switch")


# --- music -----------------------------------------------------------------------------


func current_music_id() -> StringName:
	return _current_music_id


func current_area() -> StringName:
	return _current_area


func music_is_playing(name: StringName) -> bool:
	var id := _resolve_music(name)
	var player := _active_music_player()
	return _current_music_id == id and player != null and player.playing


## Switch area music and ambience with a crossfade. The same area again is a no-op
## (except that area music comes back after an automatic boss track has ended).
func play_area(area_id: StringName) -> void:
	if _shutting_down:
		return
	if not AREA_IDS.has(area_id):
		push_warning("Audio: unknown area '%s'." % area_id)
		return
	if area_id != _current_area:
		_current_area = area_id
		_switch_ambience(area_id)
	if not _boss_active and not _boss_forced and _current_music_id != area_id:
		_crossfade_music(area_id, MUSIC_FADE)


## Area ids route through play_area; boss/title/ending (and old aliases) are music-only.
func play_music(name: StringName) -> void:
	if _shutting_down:
		return
	var id := _resolve_music(name)
	if AREA_IDS.has(id):
		play_area(id)
		return
	if not _music_streams.has(id):
		if MUSIC_PATHS.has(id):
			push_warning("Audio: unavailable music '%s'." % id)
		else:
			push_warning("Audio: unknown music '%s'." % name)
		return
	if id == &"boss":
		_boss_forced = true
	else:
		# Menus and the ending leave the world: drop the area bed.
		_boss_forced = false
		_boss_active = false
		_current_area = &""
		_switch_ambience(&"")
	_crossfade_music(id, BOSS_FADE if id == &"boss" else MUSIC_FADE)


## Explicit boss music control for encounters that don't use the "bosses" group.
func set_boss_music(active: bool) -> void:
	if _shutting_down:
		return
	_boss_forced = active
	if active:
		_crossfade_music(&"boss", BOSS_FADE)
	elif not _boss_active and _current_area != &"":
		_crossfade_music(_current_area, MUSIC_FADE)


func stop_music() -> void:
	_current_music_id = &""
	_boss_forced = false
	_boss_active = false
	for player in _music_players:
		if is_instance_valid(player):
			_kill_tween(player)
			player.stop()
			player.stream = null


func _resolve_music(name: StringName) -> StringName:
	return MUSIC_ALIASES.get(name, name)


func _active_music_player() -> AudioStreamPlayer:
	if _music_players.is_empty():
		return null
	return _music_players[_music_active]


func _crossfade_music(id: StringName, fade: float) -> void:
	if not _music_streams.has(id) or _music_players.size() < 2:
		return
	var outgoing := _music_players[_music_active]
	if _current_music_id == id and outgoing.playing:
		return
	_remember_position(_current_music_id, outgoing)
	_music_active = 1 - _music_active
	var incoming := _music_players[_music_active]
	_music_player = incoming
	_kill_tween(incoming)
	incoming.stop()
	incoming.stream = _music_streams[id]
	incoming.volume_db = SILENT_DB
	incoming.play(_resume_position(id))
	_current_music_id = id
	_fade(incoming, float(MUSIC_VOLUME_DB.get(id, 0.0)), fade, false)
	if outgoing.playing:
		_fade(outgoing, SILENT_DB, fade, true)


func _remember_position(id: StringName, player: AudioStreamPlayer) -> void:
	if id == &"" or not player.playing or NON_LOOPING_MUSIC.has(id):
		return
	_resume[id] = Vector2(player.get_playback_position(), Time.get_ticks_msec())


func _resume_position(id: StringName) -> float:
	# Returning to an area soon after leaving it continues its piece instead of
	# restarting the intro, so back-and-forth travel doesn't repeat the same bars.
	if not _resume.has(id):
		return 0.0
	var saved: Vector2 = _resume[id]
	if Time.get_ticks_msec() - saved.y > RESUME_WINDOW_MSEC:
		return 0.0
	var length := _music_streams[id].get_length()
	return fmod(saved.x + 1.0, length) if length > 0.0 else 0.0


func _update_boss_music() -> void:
	if _boss_forced or _current_area == &"":
		return
	if _any_boss_engaged():
		_boss_release = BOSS_RELEASE
		if not _boss_active:
			_boss_active = true
			_crossfade_music(&"boss", BOSS_FADE)
	elif _boss_active:
		_boss_release -= BOSS_POLL
		if _boss_release <= 0.0:
			_boss_active = false
			_crossfade_music(_current_area, MUSIC_FADE)


func _any_boss_engaged() -> bool:
	if not is_inside_tree():
		return false
	for boss in get_tree().get_nodes_in_group(&"bosses"):
		if (
			not is_instance_valid(boss)
			or boss.is_queued_for_deletion()
			or not boss.is_inside_tree()
		):
			continue
		var bounds: Variant = boss.get("arena_bounds")
		if not bounds is Rect2 or (bounds as Rect2).size == Vector2.ZERO:
			continue
		if boss.get("_player_engaged") == true and boss.get("_dying") != true:
			return true
	return false


# --- ambience --------------------------------------------------------------------------


func _switch_ambience(area_id: StringName) -> void:
	_layer_timers.clear()
	_layer_last.clear()
	if _bed_players.size() < 2:
		return
	var outgoing := _bed_players[_bed_active]
	if outgoing.playing:
		_fade(outgoing, SILENT_DB, AMBIENCE_FADE, true)
	if area_id == &"":
		return
	for layer in AMBIENCE_LAYERS.get(area_id, []):
		var every: Vector2 = layer["every"]
		_layer_timers.append(randf_range(every.x * 0.3, every.y * 0.6))
		_layer_last.append(-1)
	var stream := _ambience_stream("%s%s_bed.ogg" % [AMBIENCE_DIR, area_id])
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_bed_active = 1 - _bed_active
	var incoming := _bed_players[_bed_active]
	_kill_tween(incoming)
	incoming.stop()
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play(randf_range(0.0, maxf(stream.get_length() - 1.0, 0.0)))
	_fade(incoming, AMBIENCE_BED_DB, AMBIENCE_FADE, false)


func _tick_ambience(delta: float) -> void:
	if _current_area == &"" or _layer_timers.is_empty():
		return
	var layers: Array = AMBIENCE_LAYERS.get(_current_area, [])
	for index in mini(layers.size(), _layer_timers.size()):
		_layer_timers[index] -= delta
		if _layer_timers[index] > 0.0:
			continue
		var layer: Dictionary = layers[index]
		var every: Vector2 = layer["every"]
		_layer_timers[index] = randf_range(every.x, every.y)
		_fire_ambience(layer, index)


func _fire_ambience(layer: Dictionary, index: int) -> void:
	var count: int = layer["count"]
	var variant := randi_range(1, count)
	if count > 1 and variant == _layer_last[index]:
		variant = variant % count + 1
	_layer_last[index] = variant
	var path := "%s%s_%s_%d.ogg" % [AMBIENCE_DIR, _current_area, layer["kind"], variant]
	var stream := _ambience_stream(path)
	if stream == null:
		return
	var player: AudioStreamPlayer2D = null
	for candidate in _ambience_players:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		return
	var db: Vector2 = layer["db"]
	var offset := Vector2(randf_range(-900.0, 900.0), randf_range(-300.0, 200.0))
	player.stream = stream
	player.volume_db = randf_range(db.x, db.y)
	player.pitch_scale = randf_range(0.88, 1.12)
	player.global_position = _listener_centre() + offset
	player.play()


func _listener_centre() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var camera := viewport.get_camera_2d()
	if camera != null:
		return camera.get_screen_center_position()
	var half_size := viewport.get_visible_rect().size * 0.5
	return viewport.get_canvas_transform().affine_inverse() * half_size


func _ambience_stream(path: String) -> AudioStream:
	if _ambience_streams.has(path):
		return _ambience_streams[path]
	var stream := _load_stream(path)
	if stream != null:
		_ambience_streams[path] = stream
	return stream


# --- shared ----------------------------------------------------------------------------


func _fade(player: AudioStreamPlayer, target_db: float, seconds: float, stop_after: bool) -> void:
	_kill_tween(player)
	if seconds <= 0.0 or not is_inside_tree():
		player.volume_db = target_db
		if stop_after:
			player.stop()
			player.stream = null
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var from_linear := db_to_linear(player.volume_db)
	var to_linear := db_to_linear(target_db)
	tween.tween_method(_set_player_linear.bind(player), from_linear, to_linear, seconds)
	if stop_after:
		tween.tween_callback(_stop_player.bind(player))
	_tweens[player] = tween


func _set_player_linear(value: float, player: AudioStreamPlayer) -> void:
	if is_instance_valid(player):
		player.volume_db = linear_to_db(maxf(value, 0.00001))


func _stop_player(player: AudioStreamPlayer) -> void:
	if is_instance_valid(player):
		player.stop()
		player.stream = null
	_tweens.erase(player)


func _kill_tween(player: Node) -> void:
	if _tweens.has(player):
		var tween: Tween = _tweens[player]
		if tween != null and tween.is_valid():
			tween.kill()
		_tweens.erase(player)


func shutdown():
	# Mixer release is asynchronous. Drop every strong ref, then yield several frames.
	_cleanup()
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.08, true, false, true).timeout


func _exit_tree() -> void:
	_cleanup()


func _cleanup() -> void:
	if _cleanup_complete:
		return
	_shutting_down = true
	_cleanup_complete = true
	if GameState.state_changed.is_connected(_on_game_state_changed):
		GameState.state_changed.disconnect(_on_game_state_changed)
	for tween in _tweens.values():
		if tween != null and tween.is_valid():
			tween.kill()
	_tweens.clear()
	var owned: Array[Node] = []
	owned.append_array(_music_players)
	owned.append_array(_bed_players)
	owned.append_array(_ambience_players)
	owned.append_array(_sfx_players)
	for node in owned:
		if not is_instance_valid(node):
			continue
		node.call("stop")
		node.set("stream", null)
		node.free()
	_music_players.clear()
	_bed_players.clear()
	_ambience_players.clear()
	_sfx_players.clear()
	_music_player = null
	_sfx_streams.clear()
	_ambient_streams.clear()
	_ambience_streams.clear()
	_step_streams.clear()
	_area_steps.clear()
	_area_lands.clear()
	_music_streams.clear()
	_layer_timers.clear()
	_layer_last.clear()
	_active_beam_snapshot = &""
	_current_music_id = &""
	_current_area = &""


func _load_stream(path: String, warn_missing: bool = true) -> AudioStream:
	if not ResourceLoader.exists(path):
		if warn_missing:
			push_warning("Audio: missing audio file '%s'." % path)
		return null
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		push_warning("Audio: failed to load audio stream '%s'." % path)
	return stream
