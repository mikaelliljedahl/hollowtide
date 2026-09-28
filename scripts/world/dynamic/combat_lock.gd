class_name CombatLock
extends RefCounted
## A fight the player cannot step out of for free: an ambush arena that is sealing, fighting or
## between waves, or a living boss with the player inside its arena. Fast travel is refused
## during one (docs/features/fast-travel.md, T5), and so is every refill that restores health or
## saves (docs/features/ambush-arenas.md, section 3). Ammo-only sources stay open: each
## missile-requiring boss arena guarantees a recurring Harpoon refill (docs/content-catalog.md).

const AMBUSH := &"ambush"
const BOSS := &"boss"


## Why a fight is on right now (AMBUSH or BOSS), or &"" when none is.
static func reason(tree: SceneTree, player: Node2D) -> StringName:
	for node in tree.get_nodes_in_group(&"worldfx_ambush"):
		var arena := node as AmbushArena
		if (
			arena != null
			and arena.state not in [AmbushArena.State.ARMED, AmbushArena.State.CLEARED]
		):
			return AMBUSH
	if player == null:
		return &""
	for node in tree.get_nodes_in_group(&"bosses"):
		var boss := node as CombatBoss
		if boss != null and boss.health > 0 and boss._in_arena(player.global_position):
			return BOSS
	return &""


static func active(tree: SceneTree) -> bool:
	return reason(tree, tree.get_first_node_in_group(&"player") as Node2D) != &""
