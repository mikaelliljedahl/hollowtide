extends Node

const Catalog = preload("res://scripts/progression/content_catalog.gd")

const SAVE_FILE := "slot_01.json"
const BACKUP_FILE := "slot_01.json.bak"
const TEMP_FILE := "slot_01.json.tmp"

var domain: StringName:
	get:
		return _active_domain

var _active_domain: StringName = &"campaign"
var _domain_chosen := false
var _root_override := ""
var _forced_domain: StringName = &""
var _state = null


func _ready() -> void:
	_initialize_domain()


func save_game() -> Error:
	_initialize_domain()
	var snapshot: Dictionary = _state_snapshot()
	if snapshot.is_empty() or not _state_validate(snapshot):
		return ERR_INVALID_DATA

	var directory := _domain_directory()
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK:
		return directory_error
	var target := _path(SAVE_FILE)
	var backup := _path(BACKUP_FILE)
	var temporary := _path(TEMP_FILE)

	if FileAccess.file_exists(target):
		var existing := _read_save(target)
		if existing["status"] != OK:
			return existing["status"]
		if existing["domain"] != domain:
			return ERR_INVALID_DATA

	var wrapper := {
		"schema_version": Catalog.SCHEMA_VERSION,
		"domain": String(domain),
		"snapshot": snapshot,
	}
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(wrapper))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return write_error

	if FileAccess.file_exists(target):
		var move_backup_error := DirAccess.rename_absolute(target, backup)
		if move_backup_error != OK:
			DirAccess.remove_absolute(temporary)
			return move_backup_error
		var replace_error := DirAccess.rename_absolute(temporary, target)
		if replace_error != OK:
			DirAccess.rename_absolute(backup, target)
			DirAccess.remove_absolute(temporary)
			return replace_error
	else:
		var create_error := DirAccess.rename_absolute(temporary, target)
		if create_error != OK:
			DirAccess.remove_absolute(temporary)
			return create_error
	return OK


func load_game() -> Error:
	_initialize_domain()
	var target := _path(SAVE_FILE)
	if not FileAccess.file_exists(target):
		var backup_only := _read_save(_path(BACKUP_FILE))
		if backup_only["status"] == OK:
			var recovery := _recover_primary()
			return _restore(backup_only["snapshot"]) if recovery == OK else recovery
		return ERR_FILE_NOT_FOUND

	var primary := _read_save(target)
	if primary["status"] == OK:
		return _restore(primary["snapshot"])
	if primary["status"] == ERR_FILE_CORRUPT:
		var backup := _read_save(_path(BACKUP_FILE))
		if backup["status"] == OK:
			var recovery := _recover_primary()
			return _restore(backup["snapshot"]) if recovery == OK else recovery
		return ERR_FILE_CORRUPT
	return primary["status"]


func _recover_primary() -> Error:
	# Preserve corrupt evidence and the validated backup; future saves must work again.
	var temporary := _path(TEMP_FILE)
	var copy_error := DirAccess.copy_absolute(_path(BACKUP_FILE), temporary)
	if copy_error != OK:
		return copy_error
	var validation := _read_save(temporary)
	if validation["status"] != OK:
		DirAccess.remove_absolute(temporary)
		return validation["status"]
	var target := _path(SAVE_FILE)
	var archived := _path(
		"slot_01.corrupt.%d.%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	var had_primary := FileAccess.file_exists(target)
	if had_primary:
		var archive_error := DirAccess.rename_absolute(target, archived)
		if archive_error != OK:
			DirAccess.remove_absolute(temporary)
			return archive_error
	var recovery_error := DirAccess.rename_absolute(temporary, target)
	if recovery_error != OK and had_primary:
		DirAccess.rename_absolute(archived, target)
	return recovery_error


func has_save() -> bool:
	_initialize_domain()
	var target := _read_save(_path(SAVE_FILE))
	if target["status"] == OK:
		return true
	var backup := _read_save(_path(BACKUP_FILE))
	return backup["status"] == OK


func configure_test_environment(save_root: String, test_domain: StringName = &"dev") -> bool:
	if not _is_test_context() or _domain_chosen:
		return false
	if save_root.is_empty() or (test_domain != &"dev" and test_domain != &"campaign"):
		return false
	_root_override = save_root
	_forced_domain = test_domain
	_initialize_domain()
	return true


func set_test_state(state: Node) -> bool:
	if not _is_test_context() or state == null:
		return false
	_state = state
	return true


func _initialize_domain() -> void:
	if _domain_chosen:
		return
	if OS.is_debug_build() and _has_argument("--test-mode") and _root_override.is_empty():
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--test-save-root="):
				var requested := argument.trim_prefix("--test-save-root=")
				if requested.is_absolute_path():
					_root_override = requested
		if _root_override.is_empty():
			_root_override = OS.get_cache_dir().path_join(
				"hollowtide-tests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
			)
	if _forced_domain != &"":
		_active_domain = _forced_domain
	elif OS.is_debug_build() and _has_argument("--dev-mode"):
		_active_domain = &"dev"
	else:
		_active_domain = &"campaign"
	_domain_chosen = true


func _domain_directory() -> String:
	var root := _root_override if not _root_override.is_empty() else "user://saves"
	return root.path_join(String(domain))


func _path(file_name: String) -> String:
	return _domain_directory().path_join(file_name)


func _state_snapshot() -> Dictionary:
	var state := _state_node()
	if state == null:
		return {}
	var result: Variant = state.call("snapshot")
	return result if result is Dictionary else {}


func _state_validate(snapshot: Dictionary) -> bool:
	var state := _state_node()
	return state != null and bool(state.call("validate_snapshot", snapshot))


func _restore(snapshot: Dictionary) -> Error:
	if not _state_validate(snapshot):
		return ERR_INVALID_DATA
	var state := _state_node()
	var restored: bool = state.call("restore_snapshot", snapshot)
	return OK if restored else ERR_INVALID_DATA


func _state_node() -> Node:
	if _state != null:
		return _state
	return get_node_or_null("/root/GameState")


func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": ERR_FILE_NOT_FOUND}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"status": FileAccess.get_open_error()}
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK or text.is_empty():
		return {"status": ERR_FILE_CORRUPT}
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {"status": ERR_FILE_CORRUPT}
	var wrapper: Dictionary = parser.data
	if not _has_exact_wrapper_keys(wrapper):
		return {"status": ERR_FILE_CORRUPT}
	var schema_value: Variant = wrapper["schema_version"]
	if (
		(not schema_value is int and not schema_value is float)
		or not is_finite(float(schema_value))
		or floorf(float(schema_value)) != float(schema_value)
	):
		return {"status": ERR_FILE_CORRUPT}
	var schema := int(schema_value)
	if schema != Catalog.LEGACY_SCHEMA_VERSION and schema != Catalog.SCHEMA_VERSION:
		return {"status": ERR_FILE_UNRECOGNIZED}
	if wrapper["domain"] != String(domain):
		return {"status": ERR_INVALID_DATA, "domain": wrapper["domain"]}
	var snapshot: Variant = wrapper["snapshot"]
	if not snapshot is Dictionary:
		return {"status": ERR_FILE_CORRUPT}
	var snapshot_version: Variant = snapshot.get("version", null)
	if (
		(not snapshot_version is int and not snapshot_version is float)
		or int(snapshot_version) != schema
		or not _state_validate(snapshot)
	):
		return {"status": ERR_FILE_CORRUPT}
	return {"status": OK, "domain": domain, "snapshot": snapshot}


func _has_exact_wrapper_keys(wrapper: Dictionary) -> bool:
	if (
		wrapper.size() != 3
		or not wrapper.has("schema_version")
		or not wrapper.has("domain")
		or not wrapper.has("snapshot")
	):
		return false
	for key in wrapper:
		if not key is String or key not in ["schema_version", "domain", "snapshot"]:
			return false
	return true


func _is_test_context() -> bool:
	if not OS.is_debug_build():
		return false
	return (
		Engine.is_editor_hint() or _has_argument("--test-mode") or _has_argument("--test-save-root")
	)


func _has_argument(argument: String) -> bool:
	return OS.get_cmdline_args().has(argument) or OS.get_cmdline_user_args().has(argument)
