extends RefCounted
## Playtest agent run report (docs/features/playtest-agent.md, "Reports"): derives findings from a
## run record and writes `report.json` and `report.md` into the run's output directory.

const STUCK_REPORT_SECONDS := 3.0
const MAX_FINDINGS := 12


## Plain-language findings, most severe first. `record` is the full run record (meta + telemetry).
static func findings(record: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var data: Dictionary = record["telemetry"]
	result.append_array(_boss_findings(data["bosses"]))
	var disengaged: Dictionary = data["boss_damage_while_disengaged"]
	for boss in disengaged:
		(
			result
			. append(
				(
					"%s took %d damage while the player was outside its arena, where it does not fight back."
					% [boss, disengaged[boss]]
				)
			)
		)
	result.append_array(_ambush_findings(data["ambushes"]))
	result.append_array(_death_findings(data["deaths"]))
	var damage: Dictionary = data["damage_by_source"]
	if not damage.is_empty():
		var top := _top(damage)
		var total := _sum(damage.values())
		result.append(
			(
				"Most damage came from %s: %d of %d (%d%%)."
				% [top, damage[top], total, roundi(100.0 * damage[top] / maxf(total, 1))]
			)
		)
	for episode in data["stuck"]:
		if float(episode["seconds"]) >= STUCK_REPORT_SECONDS:
			result.append(
				(
					"Agent stuck %.1f s in %s at cell (%d, %d) from t=%.1f s."
					% [
						episode["seconds"],
						episode["room"],
						episode["cell"][0],
						episode["cell"][1],
						episode["t"]
					]
				)
			)
	var deflect: Dictionary = data["deflect"]
	if int(deflect["attempts"]) > 0 or int(deflect["successes"]) > 0:
		result.append(
			(
				"Dash deflect: %d turned shots from %d deliberate dash attempts."
				% [deflect["successes"], deflect["attempts"]]
			)
		)
	for id in data["sequence_break_attempts"]:
		result.append(
			(
				"Sequence break %s: %d attempts near its start."
				% [id, data["sequence_break_attempts"][id]]
			)
		)
	for policy in data["decisions"]:
		var fallbacks: Dictionary = data["decisions"][policy]["fallbacks"]
		for reason in fallbacks:
			result.append(
				"Policy %s fell back %d times (%s)." % [policy, fallbacks[reason], reason]
			)
	if result.is_empty():
		result.append("No deaths, stalls or failed fights recorded.")
	return result.slice(0, MAX_FINDINGS)


static func write(record: Dictionary, directory: String) -> Error:
	var absolute := ProjectSettings.globalize_path(directory)
	var made := DirAccess.make_dir_recursive_absolute(absolute)
	if made != OK:
		return made
	record["findings"] = findings(record)
	var json := FileAccess.open(absolute.path_join("report.json"), FileAccess.WRITE)
	if json == null:
		return FileAccess.get_open_error()
	json.store_string(JSON.stringify(record, "  ", false) + "\n")
	json.close()
	var markdown := FileAccess.open(absolute.path_join("report.md"), FileAccess.WRITE)
	if markdown == null:
		return FileAccess.get_open_error()
	markdown.store_string(to_markdown(record))
	markdown.close()
	return OK


static func to_markdown(record: Dictionary) -> String:
	var meta: Dictionary = record["meta"]
	var data: Dictionary = record["telemetry"]
	var lines: Array[String] = [
		"# Playtest run %s" % meta["run_id"],
		"",
		"| Room | Kit | Policy | Seed | Game seconds | End |",
		"|---|---|---|---|---|---|",
		(
			"| %s | %s | %s | %d | %.1f | %s |"
			% [
				meta["room"],
				", ".join(meta["kit"]),
				meta["policy"],
				meta["seed"],
				data["seconds"],
				meta["end_reason"]
			]
		),
		"",
		"## Findings",
		"",
	]
	for finding in record.get("findings", findings(record)):
		lines.append("- " + finding)
	lines.append_array(["", "## Deaths", ""])
	lines.append_array(
		_table(["t (s)", "Room", "Cell", "Killer"], data["deaths"], _death_row, "No deaths.")
	)
	lines.append_array(["", "## Damage by source", ""])
	var sources: Array = []
	for source in data["damage_by_source"]:
		sources.append({"source": source, "amount": data["damage_by_source"][source]})
	sources.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["amount"] > b["amount"]
	)
	lines.append_array(
		_table(
			["Source", "Damage"],
			sources,
			func(row: Dictionary) -> Array: return [row["source"], row["amount"]],
			"No damage taken."
		)
	)
	lines.append_array(["", "## Boss attempts", ""])
	lines.append_array(
		_table(
			["Boss", "Outcome", "Seconds", "Stage reached", "Stage seconds", "Boss HP left"],
			data["bosses"],
			func(row: Dictionary) -> Array:
				return [
					row["id"],
					row["outcome"],
					row["seconds"],
					row["stage_reached"],
					JSON.stringify(row["stage_seconds"]),
					row["boss_health_left"]
				],
			"No boss fight."
		)
	)
	lines.append_array(["", "## Ambush fights", ""])
	lines.append_array(
		_table(
			["Arena", "Outcome", "Seconds", "Wave", "Damage taken"],
			data["ambushes"],
			func(row: Dictionary) -> Array:
				return [
					row["id"],
					row["outcome"],
					row["seconds"],
					"%d/%d" % [row["wave_reached"], row["waves"]],
					row["damage_taken"]
				],
			"No ambush fight."
		)
	)
	lines.append_array(["", "## Time per room", ""])
	var rooms: Array = []
	for id in data["room_seconds"]:
		rooms.append({"room": id, "seconds": data["room_seconds"][id]})
	lines.append_array(
		_table(
			["Room", "Seconds"],
			rooms,
			func(row: Dictionary) -> Array: return [row["room"], row["seconds"]],
			"No room time."
		)
	)
	lines.append_array(["", "## Decisions", ""])
	var policies: Array = []
	for policy in data["decisions"]:
		var entry: Dictionary = data["decisions"][policy].duplicate()
		entry["policy"] = policy
		policies.append(entry)
	lines.append_array(
		_table(
			["Policy", "Decisions", "Mean ms", "Max ms", "Fallbacks"],
			policies,
			func(row: Dictionary) -> Array:
				return [
					row["policy"],
					row["count"],
					row["latency_ms_mean"],
					row["latency_ms_max"],
					JSON.stringify(row["fallbacks"])
				],
			"No decisions."
		)
	)
	lines.append_array(
		[
			"",
			"Enemies killed: `%s`" % JSON.stringify(data["kills"]),
			"",
			"Actions chosen: `%s`" % JSON.stringify(data["actions"]),
			""
		]
	)
	return "\n".join(lines)


static func _boss_findings(attempts: Array) -> Array[String]:
	var result: Array[String] = []
	var by_boss := {}
	for attempt in attempts:
		by_boss.get_or_add(attempt["id"], []).append(attempt)
	for boss in by_boss:
		var list: Array = by_boss[boss]
		var wins := list.filter(func(a: Dictionary) -> bool: return a["outcome"] == "defeated")
		var losses := list.filter(func(a: Dictionary) -> bool: return a["outcome"] == "died")
		var line := (
			"%s: %d attempts, %d defeated, %d deaths"
			% [boss, list.size(), wins.size(), losses.size()]
		)
		if not losses.is_empty():
			var stages := {}
			for attempt in losses:
				var key := "stage %d" % attempt["stage_reached"]
				stages[key] = int(stages.get(key, 0)) + 1
			var worst := _top(stages)
			line += "; %s killed the agent %d/%d times" % [worst, stages[worst], list.size()]
		var damage := {}
		for attempt in list:
			for source in attempt["damage_by_source"]:
				damage[source] = (
					int(damage.get(source, 0)) + int(attempt["damage_by_source"][source])
				)
		if not damage.is_empty():
			var top := _top(damage)
			line += ", most damage from %s (%d)" % [top, damage[top]]
		result.append(line + ".")
	return result


static func _ambush_findings(fights: Array) -> Array[String]:
	var result: Array[String] = []
	for fight in fights:
		result.append(
			(
				"Ambush %s: %s after %.1f s at wave %d/%d, %d damage taken."
				% [
					fight["id"],
					fight["outcome"],
					fight["seconds"],
					fight["wave_reached"],
					fight["waves"],
					fight["damage_taken"]
				]
			)
		)
	return result


static func _death_findings(deaths: Array) -> Array[String]:
	var result: Array[String] = []
	var killers := {}
	for death in deaths:
		var key := "%s in %s" % [death["killer"], death["room"]]
		killers[key] = int(killers.get(key, 0)) + 1
	for key in killers:
		result.append("Killed %d times by %s." % [killers[key], key])
	return result


static func _death_row(row: Dictionary) -> Array:
	return [row["t"], row["room"], "(%d, %d)" % [row["cell"][0], row["cell"][1]], row["killer"]]


static func _table(header: Array, rows: Array, cells: Callable, empty: String) -> Array[String]:
	if rows.is_empty():
		return [empty]
	var lines: Array[String] = ["| %s |" % " | ".join(header), "|%s" % "---|".repeat(header.size())]
	for row in rows:
		var values: Array = cells.call(row)
		lines.append("| %s |" % " | ".join(values.map(func(value) -> String: return str(value))))
	return lines


## Key with the largest value; ties go to the alphabetically first key so output is stable.
static func _top(counts: Dictionary) -> String:
	var keys: Array = counts.keys()
	keys.sort()
	var best: String = keys[0]
	for key in keys:
		if counts[key] > counts[best]:
			best = key
	return best


static func _sum(values: Array) -> int:
	var total := 0
	for value in values:
		total += int(value)
	return total
