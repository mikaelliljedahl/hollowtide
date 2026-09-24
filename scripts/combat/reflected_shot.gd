class_name ReflectedShot
extends ProjectileBase
## An enemy shot turned by the Undertow Dash deflect window (DashDeflect). Player-owned: layer 16,
## world + enemies mask, damage kind `beam`, so the reaction matrix and every boss phase guard
## apply exactly as for a Seed Bolt. Drawn as the original shot wrapped in the dash's undertow
## current.

const DAMAGE := 30
## Faster than DASH_SPEED so the returned shot leads the dash instead of riding with her.
const SPEED := 1800.0
const RANGE := 960.0
const SHEATH := Color(0.45, 0.95, 1.0, 0.85)

var style: StringName = &"orb"
var size_scale := 1.0
var _age_visual := 0.0


func _ready() -> void:
	speed = SPEED
	lifetime = RANGE / SPEED
	damage_amount = DAMAGE
	damage_kind = &"beam"
	super._ready()
	add_to_group(&"reflected_shot")
	z_index = 2


func _process(delta: float) -> void:
	_age_visual += delta
	queue_redraw()


func _impact(position: Vector2, reaction: StringName, _normal: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	ArsenalFx.spawn_rings(parent, position, 46.0 * size_scale, SHEATH, 0.3, 2)
	if reaction == &"vulnerable":
		GameJuice.play_sfx(&"dash_hit")


func _draw() -> void:
	var colors: Array = EnemyProjectile.STYLE_COLORS.get(
		style, EnemyProjectile.STYLE_COLORS[&"orb"]
	)
	var main: Color = colors[0]
	var core: Color = colors[1]
	var radius := 7.0 * size_scale
	# Current streaks trailing behind (node is rotated toward travel, so behind is -x).
	for index in 3:
		var lane := (float(index) - 1.0) * radius * 0.9
		var length := radius * (5.5 - absf(float(index) - 1.0) * 1.8)
		var wobble := sin(_age_visual * 24.0 + float(index) * 2.1) * radius * 0.25
		var head := Vector2(-radius * 0.6, lane)
		var tail := Vector2(-length, lane + wobble)
		var normal := Vector2(0.0, radius * 0.22)
		draw_colored_polygon(
			PackedVector2Array([head - normal, head + normal, tail]), Color(SHEATH, 0.5)
		)
	draw_circle(Vector2.ZERO, radius * 2.1, Color(SHEATH, 0.16))
	draw_circle(Vector2.ZERO, radius, main)
	draw_circle(Vector2.ZERO, radius * 0.55, core)
	# Two arcs of water spinning around the shot.
	var spin := _age_visual * 18.0
	for index in 2:
		var start := spin + PI * float(index)
		draw_arc(Vector2.ZERO, radius * 1.55, start, start + 1.9, 12, SHEATH, 2.2, true)
