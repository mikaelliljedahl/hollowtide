extends RefCounted
## Stub: lanternjaw is a planned mini-boss (docs/features/mini-bosses.md). Fill TIMING, CHARGES, MOVE_SPEEDS
## and ROTATIONS (and the optional plan/emissions hooks) in its own work package; until ROTATIONS is
## non-empty the registry treats it as not fightable.

const ID := &"lanternjaw"
const MAX_HEALTH := 190
const CONTACT_DAMAGE := 22
const ACCENT := Color(1.0, 0.76, 0.24, 1.0)
const CHARGE_SPEED := 600.0
const TIMING := {}
const CHARGES: Array[StringName] = []
const MOVE_SPEEDS: Array[float] = []
const ROTATIONS := []
