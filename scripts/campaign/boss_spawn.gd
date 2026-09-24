extends Marker2D

## Spawns a boss unless its persistent flag is set. Victory sets `boss:<id>` (and `regional:<id>`
## for the two branch bosses), moves the safe return point into the arena and autosaves atomically.

const WAVE_GRATE_SCRIPT = preload("res://scripts/world/wave_grate.gd")
const REGIONAL_BOSSES: Array[StringName] = [&"stone_guardian", &"furnace_mother"]

@export var boss_id: StringName = &"stone_guardian"
## Local-pixel arena rectangle; the boss only fights while the player is inside.
@export var arena := Rect2()
## Local feet position used as the checkpoint after victory.
@export var return_point := Vector2.ZERO

var boss: Node2D
var _grate: Node2D


func _ready() -> void:
	if GameState.has_world_flag(flag_id()):
		return
	call_deferred("_spawn")


func flag_id() -> String:
	return "boss:" + String(boss_id)


func _spawn() -> void:
	boss = EnemyFactory.create(boss_id)
	if boss == null:
		push_warning("Campaign: could not create boss %s" % boss_id)
		return
	var room := _room()
	var origin := room.global_position if room != null else Vector2.ZERO
	boss.position = position
	get_parent().add_child(boss)
	if boss.has_method("configure_arena"):
		boss.call("configure_arena", Rect2(origin + arena.position, arena.size))
	boss.add_to_group(&"campaign_boss")
	if boss.has_signal("defeated"):
		boss.connect("defeated", _on_defeated)
	if boss_id == &"tidal_heart":
		_grate = WAVE_GRATE_SCRIPT.new()
		_grate.set("grate_size", Vector2(36, 192))
		_grate.position = position - Vector2(150, 0)
		get_parent().add_child(_grate)
		_grate.call("set_relay", boss)
		_anchor_grate(room)


func _on_defeated(_id: StringName) -> void:
	if is_instance_valid(_grate):
		_grate.queue_free()
	var root := get_tree().get_first_node_in_group(&"campaign_root")
	var room := _room()
	var room_name: String = room.get("room_id") if room != null else ""
	var before := GameState.snapshot()
	GameState.set_world_flag(flag_id())
	if boss_id in REGIONAL_BOSSES:
		GameState.set_world_flag("regional:" + String(boss_id))
	if not room_name.is_empty():
		GameState.set_checkpoint(room_name, return_point)
	if root != null and root.has_method("on_boss_defeated"):
		if not bool(root.call("on_boss_defeated", boss_id)):
			GameState.restore_snapshot(before)


## The grate hangs in the arena: a rock column from the ceiling holds it so it never floats.
func _anchor_grate(room: Node2D) -> void:
	var tiles := room.get_node_or_null("CaveTiles") as TileMapLayer if room != null else null
	if tiles == null:
		return
	var frame_top := _grate.position.y - 96.0 - 80.0
	var cell := Vector2i(floori(_grate.position.x / 64.0), floori(frame_top / 64.0))
	while cell.y > 0 and tiles.get_cell_source_id(cell) < 0:
		cell.y -= 1
	if tiles.get_cell_source_id(cell) < 0:
		return
	var ceiling := float(cell.y + 1) * 64.0
	var kit := EnvironmentKit.load_for(StringName(room.get("area_id")))
	var column := GrateColumn.new()
	column.name = "GrateColumn"
	column.texture = kit.texture(&"fill")
	column.tint = Color(kit.tint.r, kit.tint.g, kit.tint.b).lightened(0.15)
	column.rect = Rect2(_grate.position.x - 26.0, ceiling - 24.0, 52.0, frame_top - ceiling + 110.0)
	get_parent().add_child(column)
	_grate.tree_exited.connect(column.queue_free)


class GrateColumn:
	extends Node2D
	var texture: Texture2D
	var tint := Color.WHITE
	var rect := Rect2()

	func _ready() -> void:
		z_index = -1
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	func _draw() -> void:
		if texture != null:
			draw_texture_rect_region(texture, rect, rect, tint)
		else:
			draw_rect(rect, tint)
		# Rounded shading: darker flanks, a thin lit edge on the left.
		draw_rect(Rect2(rect.position, Vector2(10, rect.size.y)), Color(0, 0, 0.02, 0.45))
		draw_rect(Rect2(rect.end.x - 14, rect.position.y, 14, rect.size.y), Color(0, 0, 0.02, 0.55))
		draw_rect(
			Rect2(rect.position + Vector2(10, 0), Vector2(3, rect.size.y)), Color(1, 1, 1, 0.08)
		)


func _room() -> Node2D:
	return get_parent().get_parent() as Node2D
