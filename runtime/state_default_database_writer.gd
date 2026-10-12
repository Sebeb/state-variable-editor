extends RefCounted
class_name StateDefaultDatabaseWriter

const LogLevel := preload("state_log_level.gd")
const StateVariableDatabase := preload("state_variable_database.gd")

const _TEMP_SUFFIX := ".state-default.tmp.tres"


func failure_log_level(is_editor_hint: bool, is_debug_build: bool) -> int:
	return LogLevel.ERROR if is_editor_hint or is_debug_build else LogLevel.WARN


func write_default(database_path: String, variable: StateVariable, value: Variant) -> Dictionary:
	if variable == null:
		return _failure("missing_variable", "The live state variable is unavailable.")
	var coerced: Variant = variable.definition.coerce_value(value)
	if variable.definition.values_equal(variable.get_default_value(), coerced):
		return {"ok": true, "changed": false}
	var global_path := ProjectSettings.globalize_path(database_path)
	if not FileAccess.file_exists(global_path) or DirAccess.dir_exists_absolute(global_path):
		return _failure("missing_or_unwritable", "The state database is missing or is not a writable file.")
	var source := FileAccess.get_file_as_string(database_path)
	if source.is_empty():
		return _failure("unreadable", "The state database could not be read.")
	var candidate_result := _replace_definition_default(
		source,
		String(variable.get_path()),
		var_to_str(coerced)
	)
	if not bool(candidate_result.get("ok", false)):
		return candidate_result
	var candidate_text := str(candidate_result.get("text", ""))
	var temp_path := database_path + _TEMP_SUFFIX
	var temp_global_path := ProjectSettings.globalize_path(temp_path)
	_remove_file(temp_global_path)
	var temp_file := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp_file == null:
		return _failure("unwritable", "A sibling temporary state database could not be created.")
	temp_file.store_string(candidate_text)
	temp_file.flush()
	temp_file = null
	var candidate_database := ResourceLoader.load(
		temp_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as StateVariableDatabase
	if candidate_database == null:
		_remove_file(temp_global_path)
		return _failure("invalid_candidate", "The candidate state database did not validate as a StateVariableDatabase.")
	var candidate_definition := candidate_database.get_definition_by_path(String(variable.get_path()))
	if candidate_definition == null or not candidate_definition.values_equal(candidate_definition.default_value, coerced):
		_remove_file(temp_global_path)
		return _failure("invalid_candidate", "The candidate state database did not contain the requested DEFAULT value.")
	var replace_error := DirAccess.rename_absolute(temp_global_path, global_path)
	if replace_error != OK:
		_remove_file(temp_global_path)
		return _failure("replace_failed", "The candidate state database could not atomically replace the project file.")
	var runtime_changed := variable.set_default_value(coerced)
	return {
		"ok": runtime_changed,
		"changed": runtime_changed,
		"reason": "" if runtime_changed else "runtime_update_failed",
	}


func _replace_definition_default(source: String, path: String, serialized_value: String) -> Dictionary:
	var lines := source.split("\n", true)
	var path_line := 'path = &"%s"' % path
	var target_index := -1
	for index in range(lines.size()):
		if lines[index].strip_edges() == path_line:
			target_index = index
			break
	if target_index < 0:
		return _failure("missing_target", "The state database does not contain the target definition.")
	var block_end := lines.size()
	for index in range(target_index + 1, lines.size()):
		if lines[index].begins_with("["):
			block_end = index
			break
	var default_index := -1
	for index in range(target_index + 1, block_end):
		if lines[index].strip_edges().begins_with("default_value ="):
			default_index = index
			break
	if default_index < 0:
		return _failure("missing_default_row", "The target definition has no authored default row.")
	lines[default_index] = "default_value = %s" % serialized_value
	return {"ok": true, "text": "\n".join(lines)}


func _failure(reason: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"changed": false,
		"reason": reason,
		"message": message,
		"log_level": failure_log_level(Engine.is_editor_hint(), OS.is_debug_build()),
	}


func _remove_file(global_path: String) -> void:
	if FileAccess.file_exists(global_path):
		DirAccess.remove_absolute(global_path)
