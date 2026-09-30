extends RefCounted
## Stub: tollwing is a planned mini-boss (docs/features/mini-bosses.md). Fill TIMING, CHARGES, MOVE_SPEEDS
## and ROTATIONS (and the optional plan/emissions hooks) in its own work package; until ROTATIONS is
## non-empty the registry treats it as not fightable.

const ID := &"tollwing"
const MAX_HEALTH := 130
const CONTACT_DAMAGE := 16
const ACCENT := Color(1.0, 0.76, 0.24, 1.0)
const CHARGE_SPEED := 600.0
const TIMING := {}
const CHARGES: Array[StringName] = []
const MOVE_SPEEDS: Array[float] = []
const ROTATIONS := []
