class_name WorldFxTestbed
extends RefCounted
## Builds a throwaway campaign-style room (real tiles, area visuals, player) from an ASCII grid
## for the living-environment checks and captures. '#' is rock, anything else is air.

const TILE := 64.0
const TILESET := preload("res://scenes/campaign/cave_tileset.tres")
const VISUALS_SCRIPT := preload("res://scripts/world/cave_visuals.gd")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")


static func build_room(
	host: Node, area: StringName, grid: Array, room_id := "worldfx_test"
) -> CampaignRoom:
	var room := CampaignRoom.new()
	room.name = room_id
	room.room_id = room_id
	room.area_id = area
	room.room_size = Vector2i(String(grid[0]).length(), grid.size())
	var backdrop := Polygon2D.new()
	backdrop.name = "Backdrop"
	backdrop.z_index = -20
	backdrop.color = Color(0.043, 0.055, 0.078)
	var size := Vector2(room.room_size) * TILE
	backdrop.polygon = PackedVector2Array(
		[Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]
	)
	room.add_child(backdrop)
	var tiles := TileMapLayer.new()
	tiles.name = "CaveTiles"
	tiles.tile_set = TILESET
	for y in grid.size():
		var row := String(grid[y])
		for x in row.length():
			if row[x] == "#":
				tiles.set_cell(Vector2i(x, y), 0, Vector2i((x + y) % 4, (x * 7 + y) % 3))
	room.add_child(tiles)
	var visuals := Node2D.new()
	visuals.name = "CaveVisuals"
	visuals.z_index = -5
	visuals.set_script(VISUALS_SCRIPT)
	room.add_child(visuals)
	var entities := Node2D.new()
	entities.name = "Entities"
	room.add_child(entities)
	host.add_child(room)
	return room


static func spawn_player(host: Node, room: CampaignRoom, feet_cell: Vector2i) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	host.add_child(player)
	player.reset_for_spawn(feet(room, feet_cell))
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.limit_left = int(room.global_position.x)
		camera.limit_top = int(room.global_position.y)
		camera.limit_right = int(room.global_position.x + room.size_px().x)
		camera.limit_bottom = int(room.global_position.y + room.size_px().y)
		camera.reset_smoothing()
	return player


## Global feet position standing in `cell` (on the floor below it).
static func feet(room: CampaignRoom, cell: Vector2i) -> Vector2:
	return room.global_position + Vector2(cell.x * TILE + TILE * 0.5, (cell.y + 1) * TILE)


static func cell_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE


static func entities(room: CampaignRoom) -> Node2D:
	return room.get_node("Entities") as Node2D
