class_name WorldFx
extends RefCounted
## Shared helpers for the living-environment mechanics (D21): area lookup, per-area palette,
## rock-material drawing that matches the terrain kits, one-shot dust and positional sound.

const TILE := 64.0
const SFX_DIR := "res://assets/audio/sfx/"
const PLAYER_LAYER := 2
const TERRAIN_LAYER := 1
## Per-area look for dynamic props. `rock` tints fill textures, `accent` is the glow/seam colour,
## `spike` and `spike_edge` colour stalactites, `dust` colours debris.
const PALETTE := {
	&"fringe":
	{
		"rock": Color(0.62, 0.68, 0.74),
		"accent": Color(0.55, 0.78, 0.95),
		"spike": Color(0.36, 0.41, 0.47),
		"spike_edge": Color(0.66, 0.74, 0.82),
		"dust": Color(0.62, 0.66, 0.7, 0.85),
	},
	&"nexus":
	{
		"rock": Color(0.58, 0.66, 0.68),
		"accent": Color(0.35, 0.95, 0.85),
		"spike": Color(0.2, 0.46, 0.5),
		"spike_edge": Color(0.55, 0.98, 0.9),
		"dust": Color(0.55, 0.7, 0.7, 0.85),
	},
	&"vaults":
	{
		"rock": Color(0.72, 0.76, 0.8),
		"accent": Color(0.72, 0.92, 1.0),
		"spike": Color(0.62, 0.8, 0.92),
		"spike_edge": Color(0.93, 0.98, 1.0),
		"dust": Color(0.85, 0.92, 1.0, 0.85),
	},
	&"kiln":
	{
		"rock": Color(0.6, 0.48, 0.44),
		"accent": Color(1.0, 0.45, 0.12),
		"spike": Color(0.17, 0.13, 0.12),
		"spike_edge": Color(1.0, 0.5, 0.16),
		"dust": Color(0.45, 0.36, 0.32, 0.85),
	},
	&"depths":
	{
		"rock": Color(0.5, 0.52, 0.66),
		"accent": Color(0.66, 0.46, 1.0),
		"spike": Color(0.2, 0.18, 0.3),
		"spike_edge": Color(0.72, 0.55, 1.0),
		"dust": Color(0.45, 0.45, 0.6, 0.85),
	},
}

const ART_DIR := "res://assets/worldfx/"
const AREA_ORDER: Array[StringName] = [&"fringe", &"nexus", &"vaults", &"kiln", &"depths"]

## Caches live on a node under the tree root (not in static vars) so every texture and stream is
## released with the tree at exit instead of being reported as leaked.
static var _cache_ref: WeakRef


## Area of the campaign room that contains `node`; `override` wins when set.
static func area_for(node: Node, override: StringName = &"") -> StringName:
	if override != &"":
		return override
	var current := node
	while current != null:
		if current is CampaignRoom:
			return (current as CampaignRoom).area_id
		current = current.get_parent()
	return &"fringe"


## Persistent flag id: `<room_id>.<kind>.<local_id>`; an explicit id is used unchanged.
static func flag_for(node: Node, kind: String, local_id: String, explicit := "") -> String:
	if not explicit.is_empty():
		return explicit
	var current := node
	while current != null:
		if current is CampaignRoom:
			return "%s.%s.%s" % [(current as CampaignRoom).room_id, kind, local_id]
		current = current.get_parent()
	return ""


static func _cache(bucket: String) -> Dictionary:
	var holder: Node = _cache_ref.get_ref() if _cache_ref != null else null
	if holder == null:
		holder = Node.new()
		holder.name = "WorldFxCache"
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.root.add_child.call_deferred(holder)
		_cache_ref = weakref(holder)
	if not holder.has_meta(bucket):
		holder.set_meta(bucket, {})
	return holder.get_meta(bucket)


static func palette(area: StringName) -> Dictionary:
	return PALETTE.get(area, PALETTE[&"fringe"])


static func kit(area: StringName) -> EnvironmentKit:
	var kits := _cache("kits")
	if not kits.has(area):
		kits[area] = EnvironmentKit.load_for(area)
	return kits[area]


static func player_of(node: Node) -> Node2D:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(&"player") as Node2D


static func is_player(body: Node) -> bool:
	return body != null and body.is_in_group(&"player")


## Player collision rectangle in global coordinates (feet origin, 56x176 standing, 56 ball).
static func player_rect(player: Node2D) -> Rect2:
	var height := 176.0
	if player.get("is_ball") == true:
		height = 56.0
	elif player.get("is_crouching") == true:
		height = 104.0
	return Rect2(player.global_position + Vector2(-28.0, -height), Vector2(56.0, height))


## Plays `assets/audio/sfx/<id>.wav` at a world position on the SFX bus. Missing files are silent.
static func play(node: Node, id: StringName, at: Vector2, volume_db := 0.0, pitch := 1.0) -> void:
	if node == null or not node.is_inside_tree():
		return
	var stream := _stream(id)
	if stream == null:
		return
	var voice := AudioStreamPlayer2D.new()
	voice.stream = stream
	voice.bus = &"SFX"
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.max_distance = 2600.0
	voice.attenuation = 1.4
	# Parent to the root so the sound outlives a shattering/freed source node.
	node.get_tree().root.add_child(voice)
	voice.global_position = at
	voice.finished.connect(voice.queue_free)
	# Stop before teardown so the audio server releases the playback (no leak at exit).
	voice.tree_exiting.connect(voice.stop)
	voice.play()


static func _stream(id: StringName) -> AudioStream:
	var streams := _cache("streams")
	if streams.has(id):
		return streams[id]
	var path := SFX_DIR + String(id) + ".wav"
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	streams[id] = stream
	return stream


static func shake(node: Node, strength: float, duration := 0.25) -> void:
	GameJuice.shake(node, strength, duration)


## One-shot debris burst. `extents` is the emission half-size; particles fall under gravity.
static func dust(
	parent: Node, at: Vector2, extents: Vector2, color: Color, amount := 28, upward := 160.0
) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var burst := CPUParticles2D.new()
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.amount = amount
	burst.lifetime = 0.9
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	burst.emission_rect_extents = extents
	burst.direction = Vector2.UP
	burst.spread = 70.0
	burst.initial_velocity_min = upward * 0.35
	burst.initial_velocity_max = upward
	burst.gravity = Vector2(0, 900)
	burst.damping_min = 20.0
	burst.damping_max = 60.0
	burst.texture = _dust_texture()
	burst.scale_amount_min = 0.35
	burst.scale_amount_max = 0.9
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color.r, color.g, color.b, 0.0))
	burst.color_ramp = fade
	burst.z_index = 6
	parent.add_child(burst)
	burst.global_position = at
	burst.emitting = true
	burst.finished.connect(burst.queue_free)


static func _dust_texture() -> Texture2D:
	var textures := _cache("textures")
	if not textures.has("dust"):
		textures["dust"] = puff_texture(24)
	return textures["dust"]


## Draws a rock mass with the area's fill texture (world-aligned when `world_uv`) so blocks read
## as the same stone as the terrain. `top_face` adds the kit's surface strip (moss, frost, crust)
## along the top edge; `seams` adds glowing accent grooves (doors and machinery).
static func draw_rock(
	canvas: CanvasItem,
	rect: Rect2,
	area: StringName,
	world_uv := false,
	seams := 0.0,
	top_face := false,
	bottom_face := false
) -> void:
	var area_kit := kit(area)
	var colors := palette(area)
	var fill := area_kit.texture(&"fill")
	var tint: Color = area_kit.tint if fill != null else colors["rock"]
	tint = tint.lightened(0.18)
	if fill != null:
		var source := rect
		if world_uv:
			source.position = canvas.get_global_transform() * rect.position
		canvas.draw_texture_rect_region(fill, rect, source, Color(tint.r, tint.g, tint.b, 1.0))
	else:
		canvas.draw_rect(rect, Color(tint.r * 0.35, tint.g * 0.35, tint.b * 0.35), true)
	# Soft vertical light falloff (lit from above) and darker side edges.
	var shade := PackedVector2Array(
		[
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y)
		]
	)
	canvas.draw_polygon(
		shade,
		PackedColorArray(
			[Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.06), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0.3)]
		)
	)
	canvas.draw_rect(Rect2(rect.position, Vector2(4.0, rect.size.y)), Color(0, 0, 0, 0.22), true)
	canvas.draw_rect(
		Rect2(rect.position + Vector2(rect.size.x - 4.0, 0), Vector2(4.0, rect.size.y)),
		Color(0, 0, 0, 0.22),
		true
	)
	if seams > 0.0:
		var accent: Color = colors["accent"]
		accent.a = seams
		var step := 64.0
		var y := rect.position.y + step * 0.5
		while y < rect.end.y - 8.0:
			canvas.draw_line(
				Vector2(rect.position.x + 10.0, y),
				Vector2(rect.end.x - 10.0, y),
				Color(0, 0, 0, 0.5),
				5.0
			)
			canvas.draw_line(
				Vector2(rect.position.x + 12.0, y), Vector2(rect.end.x - 12.0, y), accent, 2.0
			)
			y += step
	var bottom := area_kit.texture(&"bottom")
	if bottom_face and bottom != null:
		var b_line := area_kit.strip_value("bottom_line", 48.0)
		var b_height := area_kit.strip_value("bottom_height", 160.0)
		var b_origin := canvas.get_global_transform() * rect.position
		var b_x := fposmod(b_origin.x, float(bottom.get_width()))
		# Only the part hanging below the surface line (drips, icicles, roots).
		var hang := b_height - b_line + 10.0
		canvas.draw_texture_rect_region(
			bottom,
			Rect2(rect.position.x, rect.end.y - 10.0, rect.size.x, hang),
			Rect2(b_x, b_line - 10.0, rect.size.x, hang)
		)
	var top := area_kit.texture(&"top")
	if top_face and top != null:
		var line := area_kit.strip_value("top_line", 32.0)
		var height := area_kit.strip_value("top_height", 128.0)
		var origin := canvas.get_global_transform() * rect.position
		var src_x := fposmod(origin.x, float(top.get_width()))
		# Only the upper part of the strip (the lip itself), not its fade into the rock.
		var lip_height := minf(height, line + minf(rect.size.y, 40.0))
		canvas.draw_texture_rect_region(
			top,
			Rect2(rect.position.x, rect.position.y - line, rect.size.x, lip_height),
			Rect2(src_x, 0.0, rect.size.x, lip_height)
		)
	else:
		canvas.draw_rect(
			Rect2(rect.position, Vector2(rect.size.x, 3.0)), Color(1, 1, 1, 0.16), true
		)


## Repeat for procedural fill drawing, none when the area's art sheet is delivered.
static func repeat_mode(sheet: String, area: StringName) -> CanvasItem.TextureRepeat:
	if sheet_region(sheet, area).is_empty():
		return CanvasItem.TEXTURE_REPEAT_ENABLED
	return CanvasItem.TEXTURE_REPEAT_DISABLED


## Draws the area's object from a delivered art sheet into `dest`; false when no art exists.
static func draw_sheet(
	canvas: CanvasItem, sheet: String, area: StringName, dest: Rect2, modulate := Color.WHITE
) -> bool:
	var art := sheet_region(sheet, area)
	if art.is_empty() or art["texture"] == null:
		return false
	canvas.draw_texture_rect_region(art["texture"], dest, art["region"], modulate)
	return true


## Small procedural streak texture used by currents (soft horizontal line, white).
static func streak_texture(length := 48, thickness := 6) -> Texture2D:
	var image := Image.create(length, thickness, false, Image.FORMAT_RGBA8)
	for x in length:
		var along := sin(PI * float(x) / float(length - 1))
		for y in thickness:
			var across := 1.0 - absf((float(y) + 0.5) / float(thickness) * 2.0 - 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, clampf(along * across * 1.2, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)


## Soft round puff texture for steam/bubbles.
static func puff_texture(size := 32, ring := false) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	for x in size:
		for y in size:
			var d := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(center) / (size * 0.5)
			var alpha := clampf(1.0 - d, 0.0, 1.0)
			if ring:
				alpha = clampf(1.0 - absf(d - 0.8) * 6.0, 0.0, 1.0) * 0.9
			image.set_pixel(x, y, Color(1, 1, 1, alpha * alpha if not ring else alpha))
	return ImageTexture.create_from_image(image)


## Region of the area's object on a one-row art sheet (`assets/worldfx/<sheet>.png`, objects in
## AREA_ORDER separated by transparent columns). Returns {} when the sheet is not delivered.
static func sheet_region(sheet: String, area: StringName) -> Dictionary:
	var path := ART_DIR + sheet + ".png"
	var slices := _cache("slices")
	if not slices.has(path):
		var texture: Texture2D = null
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
		slices[path] = {"texture": texture, "regions": _slice_sheet(texture)}
	var entry: Dictionary = slices[path]
	var regions: Array = entry["regions"]
	var index := AREA_ORDER.find(area)
	if index < 0 or index >= regions.size():
		return {}
	return {"texture": entry["texture"], "region": regions[index]}


## Loads art and kit textures ahead of drawing: a texture first loaded inside a draw callback
## renders as a white box, so every dynamic prop warms its art in _ready.
static func warm(sheet: String, area: StringName) -> void:
	kit(area)
	if not sheet.is_empty():
		sheet_region(sheet, area)


static func _slice_sheet(texture: Texture2D) -> Array:
	if texture == null:
		return []
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	var width := image.get_width()
	var height := image.get_height()
	var used := PackedByteArray()
	used.resize(width)
	for x in width:
		for y in range(0, height, 2):
			if image.get_pixel(x, y).a > 0.1:
				used[x] = 1
				break
	var regions: Array = []
	var start := -1
	for x in width + 1:
		var on := x < width and used[x] == 1
		if on and start < 0:
			start = x
		elif not on and start >= 0:
			if x - start > 12:
				regions.append(_trim_rows(image, start, x))
			start = -1
	return regions


static func _trim_rows(image: Image, left: int, right: int) -> Rect2:
	var top := image.get_height()
	var bottom := 0
	for y in image.get_height():
		for x in range(left, right, 2):
			if image.get_pixel(x, y).a > 0.1:
				top = mini(top, y)
				bottom = maxi(bottom, y)
				break
	return Rect2(left, top, right - left, bottom - top + 1)


## Draws a heavy gate slab whose full extent is `full`, showing only `shown` (the part inside its
## opening). Uses assets/worldfx/slabs.png when delivered, else a carved procedural slab.
static func draw_gate(
	canvas: CanvasItem, full: Rect2, shown: Rect2, area: StringName, glow := 0.4
) -> void:
	if shown.size.x < 1.0 or shown.size.y < 1.0:
		return
	var art := sheet_region("slabs", area)
	if not art.is_empty() and art["texture"] != null:
		_draw_gate_art(canvas, art["texture"], art["region"], full, shown)
		return
	draw_rock(canvas, shown, area, false, 0.0)
	var accent: Color = palette(area)["accent"]
	# Raised stone bands every 96 px of the full slab.
	var y := full.position.y + 40.0
	while y < full.end.y - 30.0:
		if y > shown.position.y + 4.0 and y < shown.end.y - 8.0:
			canvas.draw_rect(
				Rect2(shown.position.x + 3.0, y, shown.size.x - 6.0, 10.0),
				Color(0, 0, 0, 0.32),
				true
			)
			canvas.draw_rect(
				Rect2(shown.position.x + 3.0, y, shown.size.x - 6.0, 3.0),
				Color(1, 1, 1, 0.14),
				true
			)
		y += 96.0
	# Carved glowing sigil at the slab centre.
	var center := full.get_center()
	var radius := minf(full.size.x, full.size.y) * 0.28
	if (
		shown.size.x > 8.0
		and shown.size.y > 8.0
		and shown.grow(-4.0).has_point(center + Vector2(0, radius))
		and shown.has_point(center - Vector2(0, radius))
	):
		var ring := accent
		ring.a = 0.25 + 0.6 * glow
		canvas.draw_circle(center, radius + 4.0, Color(0, 0, 0, 0.35))
		canvas.draw_arc(center, radius, 0.0, TAU, 32, ring, 3.0)
		canvas.draw_colored_polygon(
			PackedVector2Array(
				[
					center + Vector2(0, -radius * 0.6),
					center + Vector2(radius * 0.4, 0),
					center + Vector2(0, radius * 0.6),
					center + Vector2(-radius * 0.4, 0)
				]
			),
			ring
		)
	# Blunt teeth along the leading (bottom) edge.
	if full.end.y <= shown.end.y + 1.0:
		var teeth := maxi(int(full.size.x / 32.0), 2)
		var tooth := full.size.x / teeth
		for index in teeth:
			var left := full.position.x + index * tooth
			canvas.draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(left + 3.0, full.end.y - 14.0),
						Vector2(left + tooth - 3.0, full.end.y - 14.0),
						Vector2(left + tooth * 0.5, full.end.y)
					]
				),
				Color(0.05, 0.05, 0.06, 0.9)
			)
	canvas.draw_rect(shown, Color(0, 0, 0, 0.6), false, 2.0)


## Slab art is portrait with its teeth at the bottom. Vertical gates map it directly; horizontal
## gates (sliding in from the right) rotate it a quarter turn so the teeth lead.
static func _draw_gate_art(
	canvas: CanvasItem, texture: Texture2D, region: Rect2, full: Rect2, shown: Rect2
) -> void:
	if full.size.y >= full.size.x:
		var scale := region.size / full.size
		var source := Rect2(
			region.position + (shown.position - full.position) * scale, shown.size * scale
		)
		canvas.draw_texture_rect_region(texture, shown, source)
		return
	var origin := Vector2(full.end.x, full.position.y)
	var v0 := origin.x - shown.end.x
	var v1 := origin.x - shown.position.x
	var along := region.size.y / full.size.x
	canvas.draw_set_transform(origin, PI * 0.5)
	canvas.draw_texture_rect_region(
		texture,
		Rect2(0.0, v0, full.size.y, v1 - v0),
		Rect2(region.position.x, region.position.y + v0 * along, region.size.x, (v1 - v0) * along)
	)
	canvas.draw_set_transform(Vector2.ZERO)
