class_name TrialRecords
extends RefCounted
## Best Trials results kept in the campaign save as the optional snapshot key `trial_bests`:
## `{"<mode>": {"time_ms": int, "hits": int}}`. Pure rules; GameState only stores the dictionary.

const SNAPSHOT_KEY := "trial_bests"
## Upper bounds reject nonsense values from a damaged save (one day, and a generous hit count).
const MAX_TIME_MS := 86400000
const MAX_HITS := 100000


## A clean copy of `value`, or null when it is not a valid records dictionary.
static func validated(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var result := {}
	for key in value:
		if not key is String or not TrialCatalog.is_mode(StringName(key)):
			return null
		var entry: Variant = value[key]
		if not entry is Dictionary or entry.size() != 2:
			return null
		var time_value: Variant = entry.get("time_ms", null)
		var hits_value: Variant = entry.get("hits", null)
		if not _valid_int(time_value, 1, MAX_TIME_MS) or not _valid_int(hits_value, 0, MAX_HITS):
			return null
		result[key] = {"time_ms": int(time_value), "hits": int(hits_value)}
	return result


static func best(records: Dictionary, mode: StringName) -> Dictionary:
	var entry: Variant = records.get(String(mode), {})
	return entry if entry is Dictionary else {}


## A result replaces the stored best only with a strictly shorter clear time.
static func is_better(records: Dictionary, mode: StringName, time_ms: int) -> bool:
	var current := best(records, mode)
	return current.is_empty() or time_ms < int(current["time_ms"])


static func with_result(
	records: Dictionary, mode: StringName, time_ms: int, hits: int
) -> Dictionary:
	var next := records.duplicate(true)
	if TrialCatalog.is_mode(mode) and is_better(records, mode, time_ms):
		next[String(mode)] = {
			"time_ms": clampi(time_ms, 1, MAX_TIME_MS), "hits": clampi(hits, 0, MAX_HITS)
		}
	return next


## Clear time as m:ss.cc.
static func format_time(time_ms: int) -> String:
	var centis := maxi(time_ms, 0) / 10
	return "%d:%02d.%02d" % [centis / 6000, (centis / 100) % 60, centis % 100]


static func _valid_int(value: Variant, minimum: int, maximum: int) -> bool:
	if value is int:
		return value >= minimum and value <= maximum
	if value is float:
		return is_finite(value) and floorf(value) == value and value >= minimum and value <= maximum
	return false
