extends RefCounted

## Travel mode of the campaign map: which activated shrine the player is choosing, and its
## markers. The map screen owns input and labels; the campaign root performs the trip
## (docs/features/fast-travel.md).

const Painter = preload("res://scripts/campaign/campaign_map_painter.gd")
const FastTravel = preload("res://scripts/campaign/fast_travel.gd")

## Map tiles from a shrine's feet to its icon centre (matches the painter's save icon).
const ICON_OFFSET := Vector2(0, 0.9)

var from_id := ""
var targets: Array[Dictionary] = []
var index := 0


## Targets arrive ordered west to east, so stepping moves across the map; the first selection
## is the target nearest the player's shrine.
func _init(from: String, choices: Array[Dictionary]) -> void:
	from_id = from
	targets = choices
	var origin := FastTravel.station(from)
	if origin.is_empty():
		return
	var best := INF
	for position in targets.size():
		var distance: float = (targets[position]["tile"] as Vector2).distance_to(origin["tile"])
		if distance < best:
			best = distance
			index = position


func selected() -> Dictionary:
	return targets[index] if not targets.is_empty() else {}


func step(amount: int) -> void:
	if not targets.is_empty():
		index = posmod(index + amount, targets.size())


## Map tile the view should centre on for the current selection.
func focus_tile() -> Vector2:
	var target := selected()
	return (target["tile"] as Vector2) - ICON_OFFSET if not target.is_empty() else Vector2.ZERO


func draw(canvas: CanvasItem, view: Painter.View) -> void:
	var origin := FastTravel.station(from_id)
	var target := selected()
	if not origin.is_empty() and not target.is_empty():
		var a := view.point((origin["tile"] as Vector2) - ICON_OFFSET)
		var b := view.point((target["tile"] as Vector2) - ICON_OFFSET)
		canvas.draw_dashed_line(a, b, Color(Painter.INK, 0.8), 5.0, 12.0)
		canvas.draw_dashed_line(a, b, Color(Painter.SAVE_COLOR, 0.7), 2.0, 12.0)
	for position in targets.size():
		var tile: Vector2 = targets[position]["tile"]
		Painter.draw_travel_target(canvas, view.point(tile - ICON_OFFSET), view, position == index)
