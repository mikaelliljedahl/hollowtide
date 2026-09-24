class_name CampaignRoom
extends Node2D

## Root of one generated campaign room (scenes/campaign/rooms/<room_id>.tscn).
## Coordinates inside the room are local pixels; world_origin is the room's map position in tiles.

const TILE := 64

@export var room_id := ""
@export var area_id: StringName = &"fringe"
@export var display_name := ""
@export var room_size := Vector2i(30, 17)
@export var world_origin := Vector2i.ZERO


func _ready() -> void:
	add_to_group(&"campaign_room")
	_remove_collected_pickups()
	_configure_visuals()


func size_px() -> Vector2:
	return Vector2(room_size * TILE)


func local_rect() -> Rect2:
	return Rect2(Vector2.ZERO, size_px())


func start_position() -> Vector2:
	var marker := get_node_or_null("Entities/Start") as Node2D
	return marker.position if marker != null else Vector2(size_px().x * 0.5, size_px().y - 128.0)


func tiles() -> TileMapLayer:
	return get_node_or_null("CaveTiles") as TileMapLayer


func is_solid_cell(cell: Vector2i) -> bool:
	var layer := tiles()
	return layer != null and layer.get_cell_source_id(cell) >= 0


func _remove_collected_pickups() -> void:
	var entities := get_node_or_null("Entities")
	if entities == null:
		return
	for child in entities.get_children():
		if child is ProgressionPickup:
			var pickup_id := String(child.get("instance_id"))
			if GameState.collected_pickup_ids.has(pickup_id):
				entities.remove_child(child)
				child.free()


func _configure_visuals() -> void:
	var visuals := get_node_or_null("CaveVisuals")
	var layer := tiles()
	if visuals == null or layer == null:
		return
	if visuals.has_method("set_fixed_area"):
		visuals.call("set_fixed_area", area_id)
	if visuals.has_method("configure"):
		visuals.call("configure", layer)
