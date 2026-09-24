extends RefCounted
class_name DevRuntimeRoom

const AREA_BY_ROOM: Dictionary[StringName, StringName] = {
	&"S0": &"fringe",
	&"S1": &"fringe",
	&"S2": &"nexus",
	&"S3": &"nexus",
	&"S4": &"vaults",
	&"S5": &"vaults",
	&"S6": &"kiln",
	&"S7": &"kiln",
	&"S8": &"depths",
	&"S9": &"depths",
	&"S10": &"depths",
}

var _host: Node
var _last_area: StringName = &""
var route_count := 0


func configure(host: Node) -> void:
	_host = host


func area_for_room(room_id: String) -> StringName:
	return AREA_BY_ROOM.get(StringName(room_id), &"fringe")


func route_room(room_id: String) -> StringName:
	var area := area_for_room(room_id)
	if area == _last_area:
		return area
	_last_area = area
	route_count += 1
	if _host == null:
		return area
	var audio := _host.get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("play_music"):
		audio.call("play_music", area)
	return area


func reset_route() -> void:
	_last_area = &""


func current_area() -> StringName:
	return _last_area
