extends RefCounted
class_name LegacyPersistentStateMigrationV1

const StateVariable = preload("../../state_variable.gd")
const StateVariableDef = preload("../../state_variable_def.gd")
const Manifest = preload("legacy_persistent_path_manifest.gd")

const SCHEMA_SECTION := "state_store"
const SCHEMA_KEY := "schema_version"
const MODERN_SCHEMA_VERSION := 2
const BASES_SECTION := "bases"
const OVERRIDES_SECTION := "overrides"
const LEGACY_CLAIMS_SECTION := "persistent_claims"
const LEGACY_DEFAULTS_SECTION := "persistent_defaults"
const BACKUP_SUFFIX := ".legacy-v1.bak"
const TEMP_SUFFIX := ".legacy-v1.tmp"


static func migrate_if_needed(
	save_path: String,
	variables_by_path: Dictionary,
	faults: Dictionary = {}
) -> Dictionary:
	var config := ConfigFile.new()
	var load_error := config.load(save_path)
	if load_error != OK:
		if not FileAccess.file_exists(ProjectSettings.globalize_path(save_path)):
			return _result(false, true, {}, {}, [], "missing")
		return _result(false, false, {}, {}, ["Legacy state file could not be parsed (error %d)." % load_error], "load_failed")
	var schema_version := int(config.get_value(SCHEMA_SECTION, SCHEMA_KEY, 0))
	if schema_version >= MODERN_SCHEMA_VERSION:
		return _result(false, true, {}, {}, [], "modern")

	if Manifest.get_paths().is_empty() and (config.has_section(LEGACY_CLAIMS_SECTION) or config.has_section(LEGACY_DEFAULTS_SECTION)):
		return _result(false, false, {}, {}, ["Legacy migration requires a host-provided path manifest; the original file was preserved."], "manifest_required")

	var warnings: Array[String] = []
	var bases := _read_section(config, BASES_SECTION, variables_by_path, warnings)
	var overrides := _read_section(config, OVERRIDES_SECTION, variables_by_path, warnings)
	for path in Manifest.get_paths():
		var target_path := Manifest.get_migration_target(path)
		if bases.has(target_path):
			continue
		var section := ""
		if config.has_section_key(LEGACY_CLAIMS_SECTION, path):
			section = LEGACY_CLAIMS_SECTION
		elif config.has_section_key(LEGACY_DEFAULTS_SECTION, path):
			section = LEGACY_DEFAULTS_SECTION
		if section.is_empty():
			continue
		var variable := variables_by_path.get(target_path) as StateVariable
		if variable == null:
			warnings.append("Legacy state path '%s' has no registered migration target '%s'; skipped." % [path, target_path])
			continue
		if variable.definition.get_value_type_name().to_upper() != Manifest.get_type_name(path):
			warnings.append("Legacy state path '%s' no longer matches its pinned value type; skipped." % path)
			continue
		var decoded := _decode_value(variable, config.get_value(section, path, null))
		if not bool(decoded.get("ok", false)):
			warnings.append("Legacy state path '%s' contains an invalid value; skipped." % path)
			continue
		var value: Variant = decoded.get("value")
		if not variable.definition.values_equal(value, variable.get_default_value()):
			bases[target_path] = value

	var candidate := ConfigFile.new()
	candidate.set_value(SCHEMA_SECTION, SCHEMA_KEY, MODERN_SCHEMA_VERSION)
	_write_section(candidate, BASES_SECTION, bases, variables_by_path)
	_write_section(candidate, OVERRIDES_SECTION, overrides, variables_by_path)
	var temp_path := save_path + TEMP_SUFFIX
	_remove_file_if_present(temp_path)
	if bool(faults.get("force_write_failure", false)):
		return _result(true, false, bases, overrides, warnings, "write_failed")
	var save_error := candidate.save(temp_path)
	if save_error != OK:
		_remove_file_if_present(temp_path)
		warnings.append("Legacy migration candidate could not be written (error %d)." % save_error)
		return _result(true, false, bases, overrides, warnings, "write_failed")
	var validated := ConfigFile.new()
	var validate_error := validated.load(temp_path)
	if validate_error != OK or int(validated.get_value(SCHEMA_SECTION, SCHEMA_KEY, 0)) != MODERN_SCHEMA_VERSION:
		_remove_file_if_present(temp_path)
		warnings.append("Legacy migration candidate failed validation.")
		return _result(true, false, bases, overrides, warnings, "validation_failed")

	var absolute_save := ProjectSettings.globalize_path(save_path)
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var backup_path := save_path + BACKUP_SUFFIX
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	if not FileAccess.file_exists(absolute_backup):
		if bool(faults.get("force_backup_failure", false)):
			_remove_file_if_present(temp_path)
			return _result(true, false, bases, overrides, warnings, "backup_failed")
		var backup_error := DirAccess.copy_absolute(absolute_save, absolute_backup)
		if backup_error != OK:
			_remove_file_if_present(temp_path)
			warnings.append("Legacy state backup could not be created (error %d)." % backup_error)
			return _result(true, false, bases, overrides, warnings, "backup_failed")
	if bool(faults.get("force_replace_failure", false)):
		_remove_file_if_present(temp_path)
		return _result(true, false, bases, overrides, warnings, "replace_failed")
	var replace_error := DirAccess.rename_absolute(absolute_temp, absolute_save)
	if replace_error != OK:
		_remove_file_if_present(temp_path)
		warnings.append("Legacy state file could not be atomically replaced (error %d)." % replace_error)
		return _result(true, false, bases, overrides, warnings, "replace_failed")
	return _result(true, true, bases, overrides, warnings, "migrated")


static func _read_section(
	config: ConfigFile,
	section: String,
	variables_by_path: Dictionary,
	warnings: Array[String]
) -> Dictionary:
	var values: Dictionary = {}
	if not config.has_section(section):
		return values
	var direct_paths: Array[String] = []
	var aliased_paths: Array[String] = []
	for raw_path_variant in config.get_section_keys(section):
		var raw_path := String(raw_path_variant).strip_edges().to_lower()
		if Manifest.get_migration_target(raw_path) == raw_path:
			direct_paths.append(raw_path)
		else:
			aliased_paths.append(raw_path)
	direct_paths.sort()
	aliased_paths.sort()
	for raw_path in direct_paths + aliased_paths:
		var path := Manifest.get_migration_target(raw_path)
		if values.has(path):
			continue
		var variable := variables_by_path.get(path) as StateVariable
		if variable == null:
			warnings.append("State path '%s' in [%s] is unknown; skipped." % [raw_path, section])
			continue
		var decoded := _decode_value(variable, config.get_value(section, raw_path, null))
		if not bool(decoded.get("ok", false)):
			warnings.append("State path '%s' in [%s] contains an invalid value; skipped." % [raw_path, section])
			continue
		var value: Variant = decoded.get("value")
		if section != BASES_SECTION or not variable.definition.values_equal(value, variable.get_default_value()):
			values[path] = value
	return values


static func _decode_value(variable: StateVariable, raw_value: Variant) -> Dictionary:
	var definition := variable.definition
	var valid := false
	match definition.value_type:
		StateVariableDef.ValueType.BOOL:
			valid = raw_value is bool
		StateVariableDef.ValueType.INT:
			valid = raw_value is int
		StateVariableDef.ValueType.FLOAT:
			valid = raw_value is float or raw_value is int
		StateVariableDef.ValueType.ENUM, StateVariableDef.ValueType.STRING:
			valid = raw_value is String or raw_value is StringName
		StateVariableDef.ValueType.ENUM_TOGGLE, StateVariableDef.ValueType.LIST:
			valid = raw_value is Array
		StateVariableDef.ValueType.VECTOR2:
			valid = raw_value is Vector2 or (
				raw_value is Array
				and raw_value.size() >= 2
				and (raw_value[0] is float or raw_value[0] is int)
				and (raw_value[1] is float or raw_value[1] is int)
			)
	if not valid:
		return {"ok": false}
	return {"ok": true, "value": definition.coerce_value(raw_value)}


static func _write_section(
	config: ConfigFile,
	section: String,
	values: Dictionary,
	variables_by_path: Dictionary
) -> void:
	var paths: Array[String] = []
	for path_variant in values.keys():
		paths.append(String(path_variant))
	paths.sort()
	for path in paths:
		var variable := variables_by_path.get(path) as StateVariable
		if variable != null:
			config.set_value(section, path, _serialize_value(variable, values[path]))


static func _serialize_value(variable: StateVariable, value: Variant) -> Variant:
	match variable.definition.value_type:
		StateVariableDef.ValueType.ENUM_TOGGLE:
			return variable.definition.enum_toggle_values(value)
		StateVariableDef.ValueType.LIST:
			return variable.definition.list_keys(value)
		StateVariableDef.ValueType.VECTOR2:
			var vector_value := value as Vector2
			return [vector_value.x, vector_value.y]
		_:
			return value


static func _remove_file_if_present(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)


static func _result(
	needed: bool,
	durable: bool,
	bases: Dictionary,
	overrides: Dictionary,
	warnings: Array[String],
	reason: String
) -> Dictionary:
	return {
		"needed": needed,
		"durable": durable,
		"bases": bases,
		"overrides": overrides,
		"warnings": warnings,
		"reason": reason,
	}
