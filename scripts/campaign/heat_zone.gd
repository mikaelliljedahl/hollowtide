extends Area2D

## Superheated air. Without Pressure Seal it drains health steadily (never an instant kill); Pressure Seal makes
## it harmless. A warm screen tint and rising embers make the rule readable without text.

const Assist = preload("res://scripts/progression/assist.gd")

const DAMAGE_PER_TICK := 4
const TICK_SECONDS := 0.5

@export var zone_size := Vector2(512, 512)

var _player: Node2D
var _timer := 0.0
var _embers: CPUParticles2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	add_to_group(&"campaign_heat")
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = zone_size
	shape.shape = rectangle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_embers = CPUParticles2D.new()
	_embers.amount = int(clampf(zone_size.x * zone_size.y / 9000.0, 24, 160))
	_embers.lifetime = 3.2
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.emission_rect_extents = zone_size * 0.5
	_embers.direction = Vector2.UP
	_embers.spread = 25.0
	_embers.gravity = Vector2(0, -30)
	_embers.initial_velocity_min = 20.0
	_embers.initial_velocity_max = 70.0
	_embers.scale_amount_min = 1.5
	_embers.scale_amount_max = 3.5
	_embers.color = Color(1.0, 0.55, 0.2, 0.75)
	_embers.z_index = 4
	add_child(_embers)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-zone_size * 0.5, zone_size), Color(1.0, 0.35, 0.08, 0.035), true)


func player_inside() -> bool:
	return is_instance_valid(_player)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	if GameState.has_ability(&"pressure_seal") or GameState.health <= 0:
		_timer = 0.0
		return
	_timer += delta
	if _timer < TICK_SECONDS:
		return
	_timer = 0.0
	# Direct drain bypasses knockback/invulnerability: heat is ambient, not a hit.
	GameState.apply_damage(Assist.scale_damage(DAMAGE_PER_TICK))


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		_player = body
		_timer = 0.0


func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player = null
