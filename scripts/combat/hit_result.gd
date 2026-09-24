class_name HitResult
extends RefCounted

enum Reaction { DAMAGE, BLOCKED, FREEZE, TRIGGERED, PASS }


static func projectile_reaction(result: Reaction) -> StringName:
	match result:
		Reaction.DAMAGE:
			return &"vulnerable"
		Reaction.BLOCKED:
			return &"immune"
		Reaction.FREEZE:
			return &"freeze"
		Reaction.TRIGGERED:
			return &"triggered"
		_:
			return &"pass"
