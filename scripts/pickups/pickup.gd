extends Area2D
class_name ProgressionPickup

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const EFFECT_DURATION := 0.6
const ICON_SCALE := Vector2(0.78, 0.78)

@export var instance_id: String = ""
@export var kind: StringName = &""
@export var pickup_sound: StringName = &"weapon_pickup"
@export var icon_texture: Texture2D

var _claimed := false
@onready var _collision: CollisionShape2D = get_node_or_null("CollisionShape2D")
@onready var _sprite: CanvasItem = get_node_or_null("Icon")
@onready var _particles: CPUParticles2D = get_node_or_null("PickupBurst")
@onready var _light: PointLight2D = get_node_or_null("PickupLight")


func _ready() -> void:
	if _sprite == null:
		_sprite = get_node_or_null("AnimatedSprite2D") as CanvasItem
	if not Catalog.is_pickup_kind(kind):
		if _sprite != null:
			_sprite.hide()
			return
	var catalog_texture := Catalog.pickup_texture(kind)
	var icon := get_node_or_null("Icon") as Sprite2D
	if icon == null and catalog_texture != null:
		icon = Sprite2D.new()
		icon.name = "CatalogIcon"
		add_child(icon)
		if _sprite != null:
			_sprite.hide()
	if icon != null:
		icon.texture = catalog_texture if catalog_texture != null else icon_texture
		icon.hframes = 1
		icon.vframes = 1
		icon.frame = 0
		icon.region_enabled = false
		icon.scale = ICON_SCALE
		_sprite = icon
	var catalog_sound := Catalog.pickup_sound_for_kind(kind)
	if catalog_sound != &"":
		pickup_sound = catalog_sound
	body_entered.connect(_on_body_entered)
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _claimed or not _is_player(body):
		return
	if instance_id.is_empty() or not Catalog.is_pickup_kind(kind):
		return
	var state := get_node_or_null("/root/GameState")
	if state == null or not bool(state.call("collect_pickup", instance_id, kind)):
		return

	_claimed = true
	var audio := get_node_or_null("/root/Audio")
	if pickup_sound != &"" and audio != null:
		audio.call("play_sfx", pickup_sound)
	if _collision != null:
		_collision.set_deferred("disabled", true)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	if _sprite != null:
		_sprite.hide()
	if _particles != null:
		_particles.emitting = true
	if _light == null:
		queue_free()
		return

	var fade := create_tween()
	fade.set_parallel()
	fade.tween_property(_light, "energy", 0.0, EFFECT_DURATION)
	fade.tween_property(_light, "scale", Vector2(1.8, 1.8), EFFECT_DURATION)
	await get_tree().create_timer(EFFECT_DURATION).timeout
	queue_free()


func _is_player(body: Node2D) -> bool:
	if body.is_in_group("player"):
		return true
	var collision_body := body as CollisionObject2D
	return collision_body != null and collision_body.get_collision_layer_value(2)


func _draw() -> void:
	# Pickup identity is rendered by catalog-resolved RGBA art. Keep draw hook for scene compatibility.
	pass
