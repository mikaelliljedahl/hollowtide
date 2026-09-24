extends Node

## Campaign glue for Tide Glyphs (docs/features/tide-modules.md), added by CampaignRoot:
## - the socket menu, opened from the shared shrine menu (CampaignRoot.open_shrine); a changed
##   loadout is saved at that shrine when the menu closes;
## - the HUD strip of socketed glyphs;
## - Ebb Mend's heal on ambush clear (AmbushArena.cleared).

const TideModules = preload("res://scripts/progression/tide_modules.gd")
const MenuScript = preload("res://scripts/ui/tide_menu.gd")
const BadgeScript = preload("res://scripts/ui/tide_badge.gd")

var menu: CanvasLayer
var _save_position := Vector2.ZERO


func _ready() -> void:
	name = "TideHook"
	menu = MenuScript.new()
	menu.name = "TideMenu"
	add_child(menu)
	menu.closed.connect(_on_menu_closed)
	var badge := BadgeScript.new()
	badge.name = "TideBadge"
	add_child(badge)
	get_tree().node_added.connect(_on_node_added)
	for arena in get_tree().get_nodes_in_group(&"worldfx_ambush"):
		_on_node_added(arena)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## Opens the socket menu for the save shrine whose feet anchor (room-local px) is
## `save_position`; false while it is already open.
func open_at(save_position: Vector2) -> bool:
	if menu.call("is_open"):
		return false
	_save_position = save_position
	menu.call("open")
	return true


func _on_menu_closed(changed: bool) -> void:
	if not changed:
		return
	var root := get_tree().get_first_node_in_group(&"campaign_root")
	if root != null and root.has_method("save_at"):
		root.call("save_at", _save_position)


func _on_node_added(node: Node) -> void:
	var arena := node as AmbushArena
	if arena != null and not arena.cleared.is_connected(_on_ambush_cleared):
		arena.cleared.connect(_on_ambush_cleared)


func _on_ambush_cleared() -> void:
	var heal := _tide().add(&"ambush_heal_add")
	if heal > 0 and GameState.health > 0:
		GameState.heal(heal)


func _tide() -> TideModules:
	return GameState.tide
