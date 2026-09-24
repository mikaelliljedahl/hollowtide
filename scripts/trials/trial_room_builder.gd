class_name TrialRoomBuilder
extends RefCounted
## Builds a closed Trials room from an ASCII grid with the real cave tiles and the area's terrain
## kit, the same way the campaign rooms are rendered. '#' is rock, anything else is air.

const TILESET := preload("res://scenes/campaign/cave_tileset.tres")
const VISUALS_SCRIPT := preload("res://scripts/world/cave_visuals.gd")
const BACKDROP_COLOR := Color(0.043, 0.055, 0.078)


static func build(host: Node, area: StringName, grid: Array, room_id: String) -> CampaignRoom:
	var room := CampaignRoom.new()
	room.name = room_id
	room.room_id = room_id
	room.area_id = area
	room.room_size = Vector2i(String(grid[0]).length(), grid.size())
	var backdrop := Polygon2D.new()
	backdrop.name = "Backdrop"
	backdrop.z_index = -20
	backdrop.color = BACKDROP_COLOR
	var size := Vector2(room.room_size) * TrialCatalog.TILE
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


## Global feet position standing in `cell` (on the floor below it).
static func feet(room: CampaignRoom, cell: Vector2i) -> Vector2:
	var tile := TrialCatalog.TILE
	return room.global_position + Vector2(cell.x * tile + tile * 0.5, (cell.y + 1) * tile)


static func entities(room: CampaignRoom) -> Node2D:
	return room.get_node("Entities") as Node2D
