extends RefCounted
class_name StateMachineRuntime

enum ValueLayer {
	DEFAULT,
	BASE,
	OVERRIDE,
}

const Console = preload("state_console.gd")

const LogLevel = preload("state_log_level.gd")
const StateMachineScopeAddress = preload("state_machine_scope_address.gd")
const StateVariable = preload("state_variable.gd")
const StateVariableCaseDef = preload("state_variable_case_def.gd")
const StateVariableDatabase = preload("state_variable_database.gd")
const StateVariableDef = preload("state_variable_def.gd")

const _STATE_CHANGE_LOG_CHANNEL := "State/Changes"
const _STATE_WARNING_LOG_CHANNEL := "State"

signal batch_committed(
	changed_paths: PackedStringArray,
	membership_changed_paths: PackedStringArray,
	override_membership_changed_paths: PackedStringArray,
	changed_transition_ids: PackedInt32Array
)
## Emitted only when this runtime substitutes the StateVariable object at a path.
## Resolved value changes continue to use StateVariable.resolved_value_changed.
signal variable_instance_replaced(
	variable_path: StringName,
	previous_variable: StateVariable,
	replacement_variable: StateVariable
)
signal torn_down(scope_key: StringName)

var database: StateVariableDatabase = null
var scope_address: StateMachineScopeAddress = null
var persistence_enabled := false
var console_exposure_enabled := false
var transition_evaluation_count := 0

var _variables_by_path: Dictionary = {}
var _emitted_claims_by_source: Dictionary = {}
var _blocked_emitter_paths: Dictionary = {}
var _invalid_targets_by_source: Dictionary = {}
var _case_emitter_source_paths: Dictionary = {}
var _transition_ids_by_condition_path: Dictionary = {}
var _transition_defs_by_id: Dictionary = {}
var _transition_claim_entries_by_id: Dictionary = {}
var _transition_active_by_id: Dictionary = {}
var _batch_changed_transition_ids: Dictionary = {}
var _batch_transition_evaluation_count := 0
var _batch_transition_evaluation_limit := 0
var _batch_transition_limit_hit := false
var _batch_depth := 0
var _batch_processing := false
var _batch_flushing := false
var _batch_variables: Dictionary = {}
var _batch_dirty_resolved_paths: Dictionary = {}
var _batch_changed_paths: Dictionary = {}
var _batch_membership_changed_paths: Dictionary = {}
var _batch_override_membership_changed_paths: Dictionary = {}
var _batch_change_sources_by_path: Dictionary = {}
var _post_flush_mutations: Array[Callable] = []
var _suppressed_value_log_paths: Dictionary = {}
var _scope_bindings: Dictionary = {}
var _externally_managed_transition_ids: Dictionary = {}
var _torn_down := false


func configure(
	runtime_database: StateVariableDatabase,
	runtime_scope_address: StateMachineScopeAddress,
	enable_persistence: bool = false,
	enable_console_exposure: bool = false
) -> bool:
	if database != null or runtime_database == null or runtime_scope_address == null:
		return false
	if not runtime_scope_address.is_valid():
		return false
	database = runtime_database
	scope_address = runtime_scope_address
	persistence_enabled = enable_persistence and runtime_scope_address.is_global()
	console_exposure_enabled = enable_console_exposure and runtime_scope_address.is_global()
	database.ensure_valid_configuration()
	_build_variables()
	_validate_outgoing_change_graph()
	_rebuild_transition_dependency_indexes()
	batch_changes(func(): refresh_derived_state())
	return true


func get_scope_key() -> StringName:
	return scope_address.qualified_key if scope_address != null else &""


func is_torn_down() -> bool:
	return _torn_down


func suppress_value_log_path(path: String) -> void:
	var normalized_path := _normalize_path(path)
	if not normalized_path.is_empty():
		_suppressed_value_log_paths[normalized_path] = true


func set_scope_bindings(bindings: Dictionary) -> void:
	_scope_bindings.clear()
	for binding_key_variant in bindings.keys():
		var binding_key := StringName(
			String(binding_key_variant).strip_edges().to_lower().trim_prefix("/").trim_suffix("/")
		)
		var target_variant: Variant = bindings[binding_key_variant]
		var target_scope_key := &""
		if target_variant is StateMachineScopeAddress:
			target_scope_key = (target_variant as StateMachineScopeAddress).qualified_key
		else:
			target_scope_key = StringName(String(target_variant).strip_edges().to_lower())
		if binding_key != &"" and target_scope_key != &"":
			_scope_bindings[binding_key] = target_scope_key


func get_bound_scope_key(binding_key: StringName) -> StringName:
	var normalized_key := StringName(
		String(binding_key).strip_edges().to_lower().trim_prefix("/").trim_suffix("/")
	)
	return StringName(_scope_bindings.get(normalized_key, &""))


func get_variable(path: String) -> StateVariable:
	if _torn_down:
		return null
	return _variables_by_path.get(_normalize_path(path))


func get_variables(pattern: String = "*") -> Array[StateVariable]:
	var matches: Array[StateVariable] = []
	if _torn_down:
		return matches
	var normalized_pattern := _normalize_path(pattern)
	for key in _variables_by_path.keys():
		var path := String(key)
		if _glob_matches(normalized_pattern, path):
			matches.append(_variables_by_path[key] as StateVariable)
	matches.sort_custom(
		func(a: StateVariable, b: StateVariable):
			return String(a.get_path()) < String(b.get_path())
	)
	return matches


func get_value(path: String, fallback: Variant = null) -> Variant:
	var variable := get_variable(path)
	return variable.resolved_value if variable != null else fallback


func get_variable_map() -> Dictionary:
	return _variables_by_path


## Replaces one runtime StateVariable without treating an ordinary resolved-value
## transition as a registry change. Consumers holding the previous instance must
## rebind through variable_instance_replaced.
func replace_variable_instance(path: String, replacement_variable: StateVariable) -> bool:
	if _torn_down or replacement_variable == null:
		return false
	var normalized_path := _normalize_path(path)
	if normalized_path.is_empty() or String(replacement_variable.get_path()) != normalized_path:
		return false
	var previous_variable := _variables_by_path.get(normalized_path) as StateVariable
	if previous_variable == null or previous_variable == replacement_variable:
		return false
	if previous_variable.resolved_value_changed.is_connected(_on_variable_resolved_value_changed):
		previous_variable.resolved_value_changed.disconnect(_on_variable_resolved_value_changed)
	_variables_by_path[normalized_path] = replacement_variable
	if not replacement_variable.resolved_value_changed.is_connected(_on_variable_resolved_value_changed):
		replacement_variable.resolved_value_changed.connect(_on_variable_resolved_value_changed)
	variable_instance_replaced.emit(StringName(normalized_path), previous_variable, replacement_variable)
	return true


func get_transition_definitions_by_id() -> Dictionary:
	return _transition_defs_by_id


func get_transition_active_map() -> Dictionary:
	return _transition_active_by_id


func get_transition_dependency_index() -> Dictionary:
	return _transition_ids_by_condition_path


func get_transition_definition(transition_id: int):
	return _transition_defs_by_id.get(transition_id)


func set_externally_managed_transition_ids(transition_ids: Array[int]) -> void:
	var next_ids: Dictionary = {}
	for transition_id in transition_ids:
		if transition_id > 0 and _transition_defs_by_id.has(transition_id):
			next_ids[transition_id] = true
	for transition_id_variant in next_ids.keys():
		var transition_id := int(transition_id_variant)
		if not _externally_managed_transition_ids.has(transition_id):
			_clear_transition_claim_entries(transition_id)
	_externally_managed_transition_ids = next_ids


func record_external_transition_evaluation(transition_id: int, active: bool) -> void:
	if not _externally_managed_transition_ids.has(transition_id):
		return
	transition_evaluation_count += 1
	_transition_active_by_id[transition_id] = active


func perform_variable_mutation(
	variable: StateVariable,
	operation: Callable,
	source: String = "unknown"
) -> Variant:
	if _torn_down or variable == null or not operation.is_valid():
		return false
	if _batch_flushing:
		_post_flush_mutations.append(
			func(): perform_variable_mutation(variable, operation, source)
		)
		return true
	var implicit_batch := _batch_depth == 0 and not _batch_processing
	if implicit_batch:
		_batch_depth = 1
	_touch_batch_variable(variable)
	var old_resolved: Variant = _duplicate_state_value(variable.resolved_value)
	var result: Variant = operation.call()
	if not variable.definition.values_equal(old_resolved, variable.resolved_value):
		var path := String(variable.get_path())
		_batch_dirty_resolved_paths[path] = true
		_batch_change_sources_by_path[path] = source
	if implicit_batch:
		_batch_depth = 0
		_commit_change_batch()
	return result


func batch_changes(callback: Callable) -> bool:
	if _torn_down or not callback.is_valid():
		_try_log_warning(func() -> String:
			return "State machine '%s': invalid batch callback." % String(get_scope_key())
		)
		return false
	# A change handler firing mid-flush can open a batch of its own. Committing it
	# here would re-enter _commit_change_batch and clear _batch_variables while the
	# outer flush is still walking it, so the callback just rides the flush: its
	# mutations already defer themselves through _post_flush_mutations.
	if _batch_flushing:
		callback.call()
		return true
	_batch_depth += 1
	callback.call()
	_batch_depth -= 1
	if _batch_depth == 0:
		_commit_change_batch()
	return true


func set_claim(path: String, code_key: StringName, value: Variant) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_log_unknown_variable("set_claim", path)
		return false
	return bool(perform_variable_mutation(
		variable,
		func(): return variable.set_claim(code_key, value),
		"set_claim:%s" % String(code_key)
	))


func clear_claim(path: String, code_key: StringName) -> bool:
	var variable := get_variable(path)
	if variable == null:
		return false
	return bool(perform_variable_mutation(
		variable,
		func(): return variable.clear_claim(code_key),
		"clear_claim:%s" % String(code_key)
	))


func add_claim(path: String, value: Variant) -> int:
	var variable := get_variable(path)
	if variable == null:
		_log_unknown_variable("add_claim", path)
		return -1
	return int(perform_variable_mutation(
		variable,
		func(): return variable.add_claim(value),
		"add_claim"
	))


func remove_claim(path: String, claim_id: int) -> bool:
	var variable := get_variable(path)
	return variable != null and bool(perform_variable_mutation(
		variable,
		func(): return variable.remove_claim(claim_id),
		"remove_claim:%d" % claim_id
	))


func reset_variable(path: String) -> void:
	var variable := get_variable(path)
	if variable != null:
		perform_variable_mutation(variable, func(): return variable.reset(), "reset_variable")


func reset_matching(pattern: String) -> void:
	batch_changes(func():
		for variable in get_variables(pattern):
			perform_variable_mutation(
				variable,
				func(): return variable.reset(),
				"reset_matching:%s" % pattern
			)
	)


func set_layer_value(path: String, value: Variant, layer: ValueLayer) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_log_unknown_variable("set_layer_value", path)
		return false
	match layer:
		ValueLayer.DEFAULT:
			return bool(perform_variable_mutation(variable, func(): return variable.set_default_value(value), "set_layer_value:default"))
		ValueLayer.BASE:
			return bool(perform_variable_mutation(variable, func(): return variable.set_base_value(value), "set_layer_value:base"))
		ValueLayer.OVERRIDE:
			return bool(perform_variable_mutation(variable, func(): return variable.set_override(value), "set_layer_value:override"))
		_:
			return false


func set_enum_toggle_option_enabled(
	path: String,
	option: Variant,
	enabled: bool,
	layer: ValueLayer
) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_log_unknown_variable("set_enum_toggle_option_enabled", path)
		return false
	if variable.definition.value_type != StateVariableDef.ValueType.ENUM_TOGGLE:
		return false
	var current_value: Variant = _get_layer_value(variable, layer)
	var next_value: Array = variable.definition.enum_toggle_set_option_enabled(
		current_value,
		option,
		enabled
	)
	return set_layer_value(path, next_value, layer)


func toggle_enum_toggle_root(path: String, layer: ValueLayer) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_log_unknown_variable("toggle_enum_toggle_root", path)
		return false
	if variable.definition.value_type != StateVariableDef.ValueType.ENUM_TOGGLE:
		return false
	var current_value: Array = variable.definition.coerce_value(
		_get_layer_value(variable, layer)
	)
	var next_value: Array = []
	if variable.definition.enum_toggle_count(current_value) == 0:
		next_value = variable.get_last_non_empty_enum_toggle_value()
		if next_value.is_empty():
			next_value = variable.definition.coerce_value(variable.get_default_value())
	return set_layer_value(path, next_value, layer)


func add_list_item(path: String, owner_key: StringName, value: Variant) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_log_unknown_variable("add_list_item", path)
		return false
	return bool(perform_variable_mutation(
		variable,
		func(): return variable.add_list_item(owner_key, value),
		"add_list_item"
	))


func remove_list_item(path: String, owner_key: StringName, value_or_key: Variant) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_log_unknown_variable("remove_list_item", path)
		return false
	return bool(perform_variable_mutation(
		variable,
		func(): return variable.remove_list_item(owner_key, value_or_key),
		"remove_list_item"
	))


func clear_list_items(path: String, owner_key: StringName) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_log_unknown_variable("clear_list_items", path)
		return false
	return bool(perform_variable_mutation(
		variable,
		func(): return variable.clear_list_items(owner_key),
		"clear_list_items"
	))


func set_override(path: String, value: Variant) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_log_unknown_variable("set_override", path)
		return false
	return bool(perform_variable_mutation(
		variable,
		func(): return variable.set_override(value),
		"set_override"
	))


func _get_layer_value(variable: StateVariable, layer: ValueLayer) -> Variant:
	match layer:
		ValueLayer.DEFAULT:
			return variable.get_default_value()
		ValueLayer.BASE:
			return variable.get_effective_bottom_value()
		ValueLayer.OVERRIDE:
			return variable.get_override_value() if variable.has_override() else variable.resolved_value
		_:
			return null


func clear_override(path: String) -> bool:
	var variable := get_variable(path)
	return variable != null and bool(perform_variable_mutation(
		variable,
		func(): return variable.clear_override(),
		"clear_override"
	))


func clear_all_overrides() -> int:
	var cleared := [0]
	batch_changes(func():
		for variable_variant in _variables_by_path.values():
			var variable := variable_variant as StateVariable
			if variable != null and bool(perform_variable_mutation(
				variable,
				func(): return variable.clear_override(),
				"clear_all_overrides"
			)):
				cleared[0] = int(cleared[0]) + 1
	)
	return int(cleared[0])


func get_overridden_variables(pattern: String = "*") -> Array[StateVariable]:
	var matches: Array[StateVariable] = []
	var normalized_pattern := _normalize_path(pattern)
	for key in _variables_by_path.keys():
		var path := String(key)
		var variable := _variables_by_path[key] as StateVariable
		if _glob_matches(normalized_pattern, path) and variable != null and variable.has_override():
			matches.append(variable)
	matches.sort_custom(
		func(a: StateVariable, b: StateVariable):
			return String(a.get_path()) < String(b.get_path())
	)
	return matches


func refresh_derived_state() -> void:
	if _torn_down:
		return
	_refresh_all_emitted_claims()
	_refresh_all_transition_claims()


func get_state_graph_snapshot() -> Dictionary:
	var states: Array[Dictionary] = []
	for path_variant in _variables_by_path.keys():
		var variable := _variables_by_path[path_variant] as StateVariable
		if variable == null:
			continue
		states.append(_build_state_snapshot(variable))
	states.sort_custom(
		func(a: Dictionary, b: Dictionary):
			return str(a.get("path", "")) < str(b.get("path", ""))
	)
	var transitions: Array[Dictionary] = []
	for transition_id_variant in _transition_defs_by_id.keys():
		transitions.append(_build_transition_snapshot(int(transition_id_variant)))
	transitions.sort_custom(
		func(a: Dictionary, b: Dictionary):
			return int(a.get("transition_id", 0)) < int(b.get("transition_id", 0))
	)
	return {
		"scope": String(get_scope_key()),
		"states": states,
		"transitions": transitions,
	}


func teardown() -> void:
	if _torn_down:
		return
	var old_scope_key := get_scope_key()
	for variable_variant in _variables_by_path.values():
		var variable := variable_variant as StateVariable
		if variable == null:
			continue
		if variable.resolved_value_changed.is_connected(_on_variable_resolved_value_changed):
			variable.resolved_value_changed.disconnect(_on_variable_resolved_value_changed)
	_variables_by_path.clear()
	_emitted_claims_by_source.clear()
	_blocked_emitter_paths.clear()
	_invalid_targets_by_source.clear()
	_case_emitter_source_paths.clear()
	_transition_ids_by_condition_path.clear()
	_transition_defs_by_id.clear()
	_transition_claim_entries_by_id.clear()
	_transition_active_by_id.clear()
	_scope_bindings.clear()
	_externally_managed_transition_ids.clear()
	_batch_changed_transition_ids.clear()
	_batch_variables.clear()
	_batch_dirty_resolved_paths.clear()
	_post_flush_mutations.clear()
	_torn_down = true
	torn_down.emit(old_scope_key)


func _build_variables() -> void:
	_variables_by_path.clear()
	for definition in database.get_definitions():
		if definition == null:
			continue
		var path := definition.get_normalized_path()
		if path == &"":
			continue
		var variable := StateVariable.new(definition)
		variable.resolved_value_changed.connect(_on_variable_resolved_value_changed)
		_variables_by_path[path] = variable


func _touch_batch_variable(variable: StateVariable) -> void:
	var path := String(variable.get_path())
	if _batch_variables.has(path):
		return
	_batch_variables[path] = variable
	variable.begin_change_batch()


func _commit_change_batch() -> void:
	if _batch_variables.is_empty() or _batch_processing:
		return
	_batch_processing = true
	_batch_depth = 1
	var propagation_rounds := 0
	var max_rounds := maxi(1, _transition_defs_by_id.size() * 8)
	_batch_transition_evaluation_count = 0
	_batch_transition_evaluation_limit = maxi(1, _transition_defs_by_id.size() * 8)
	_batch_transition_limit_hit = false
	while (
		not _batch_dirty_resolved_paths.is_empty()
		and propagation_rounds < max_rounds
		and _batch_transition_evaluation_count < _batch_transition_evaluation_limit
	):
		propagation_rounds += 1
		var dirty_paths: Array[String] = []
		for path_variant in _batch_dirty_resolved_paths.keys():
			dirty_paths.append(String(path_variant))
		dirty_paths.sort()
		_batch_dirty_resolved_paths.clear()
		var dirty_transition_ids: Dictionary = {}
		for path in dirty_paths:
			if _case_emitter_source_paths.has(path) or _emitted_claims_by_source.has(path):
				_refresh_emitted_claims_for_source(path)
			for transition_id_variant in _transition_ids_by_condition_path.get(path, []):
				dirty_transition_ids[int(transition_id_variant)] = true
		if not dirty_transition_ids.is_empty():
			_refresh_transition_ids(dirty_transition_ids.keys())
	if _batch_transition_limit_hit or not _batch_dirty_resolved_paths.is_empty():
		_try_log_warning(func() -> String:
			return (
				"State machine '%s': atomic change batch exceeded stabilization limit."
					% String(get_scope_key())
			)
		)
		_batch_dirty_resolved_paths.clear()
	_batch_depth = 0
	_batch_processing = false

	var sorted_paths: Array[String] = []
	for path_variant in _batch_variables.keys():
		sorted_paths.append(String(path_variant))
	sorted_paths.sort()
	for path in sorted_paths:
		var variable := _batch_variables[path] as StateVariable
		var summary := variable.get_pending_change_summary()
		if bool(summary.get("changed", false)):
			_batch_changed_paths[path] = true
		if (
			bool(summary.get("claim_membership_changed", false))
			or bool(summary.get("override_membership_changed", false))
		):
			_batch_membership_changed_paths[path] = true
		if bool(summary.get("override_membership_changed", false)):
			_batch_override_membership_changed_paths[path] = true
		if bool(summary.get("resolved_changed", false)):
			_log_state_value_changed(
				path,
				summary.get("old_resolved"),
				summary.get("new_resolved"),
				str(_batch_change_sources_by_path.get(path, "unknown"))
			)

	_batch_flushing = true
	for path in sorted_paths:
		(_batch_variables[path] as StateVariable).end_change_batch()
	_batch_flushing = false
	_batch_variables.clear()

	var committed_paths := _sorted_string_keys(_batch_changed_paths)
	var membership_paths := _sorted_string_keys(_batch_membership_changed_paths)
	var override_membership_paths := _sorted_string_keys(
		_batch_override_membership_changed_paths
	)
	var changed_transition_ids := PackedInt32Array()
	for transition_id_variant in _batch_changed_transition_ids.keys():
		changed_transition_ids.append(int(transition_id_variant))
	changed_transition_ids.sort()
	if not committed_paths.is_empty() or not changed_transition_ids.is_empty():
		batch_committed.emit(
			committed_paths,
			membership_paths,
			override_membership_paths,
			changed_transition_ids
		)
	_batch_changed_paths.clear()
	_batch_membership_changed_paths.clear()
	_batch_override_membership_changed_paths.clear()
	_batch_change_sources_by_path.clear()
	_batch_changed_transition_ids.clear()
	if not _post_flush_mutations.is_empty():
		var pending_mutations := _post_flush_mutations.duplicate()
		_post_flush_mutations.clear()
		batch_changes(func():
			for mutation in pending_mutations:
				mutation.call()
		)


func _refresh_all_emitted_claims() -> void:
	for source_path in _emitted_claims_by_source.keys():
		_clear_emitted_claims_for_source(String(source_path))
	for variable_variant in _variables_by_path.values():
		var variable := variable_variant as StateVariable
		if variable != null:
			_refresh_emitted_claims_for_source(String(variable.get_path()))


func _refresh_emitted_claims_for_source(source_path: String) -> void:
	source_path = _normalize_path(source_path)
	if _blocked_emitter_paths.has(source_path):
		_clear_emitted_claims_for_source(source_path)
		return
	var source_variable := get_variable(source_path)
	if source_variable == null:
		_clear_emitted_claims_for_source(source_path)
		return
	var case_def: StateVariableCaseDef = source_variable.definition.find_matching_case(
		source_variable.resolved_value
	)
	var desired: Dictionary = {}
	var invalid_targets: Dictionary = _invalid_targets_by_source.get(source_path, {})
	if case_def != null:
		for change_index in range(case_def.outgoing_changes.size()):
			var change = case_def.outgoing_changes[change_index]
			if change == null:
				continue
			var target_path := String(change.get_normalized_target_path())
			if target_path.is_empty() or invalid_targets.has(target_path):
				continue
			var target_variable := get_variable(target_path)
			if target_variable == null:
				continue
			var code_key := StringName("case/%s/%d" % [source_path, change_index])
			var entry_key := "%s|%s" % [target_path, String(code_key)]
			desired[entry_key] = {
				"target_path": target_path,
				"code_key": code_key,
				"value": change.get_target_value(target_variable.definition),
			}
	var existing: Array = _emitted_claims_by_source.get(source_path, [])
	for entry_variant in existing:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		var entry_key := "%s|%s" % [
			str(entry.get("target_path", "")),
			str(entry.get("code_key", "")),
		]
		if not desired.has(entry_key):
			clear_claim(
				str(entry.get("target_path", "")),
				StringName(str(entry.get("code_key", "")))
			)
	var emitted: Array[Dictionary] = []
	for entry_variant in desired.values():
		var entry := entry_variant as Dictionary
		set_claim(
			str(entry.get("target_path", "")),
			StringName(str(entry.get("code_key", ""))),
			entry.get("value")
		)
		emitted.append({
			"target_path": str(entry.get("target_path", "")),
			"code_key": String(entry.get("code_key", &"")),
		})
	if emitted.is_empty():
		_emitted_claims_by_source.erase(source_path)
	else:
		_emitted_claims_by_source[source_path] = emitted


func _clear_emitted_claims_for_source(source_path: String) -> void:
	source_path = _normalize_path(source_path)
	var emitted: Array = _emitted_claims_by_source.get(source_path, [])
	_emitted_claims_by_source.erase(source_path)
	for entry_variant in emitted:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		clear_claim(
			String(entry.get("target_path", "")),
			StringName(str(entry.get("code_key", "")))
		)


func _refresh_all_transition_claims() -> void:
	_refresh_transition_ids(_transition_defs_by_id.keys())


func _refresh_transition_ids(transition_ids: Array) -> void:
	var sorted_ids: Array[int] = []
	for transition_id_variant in transition_ids:
		var transition_id := int(transition_id_variant)
		if transition_id > 0 and _transition_defs_by_id.has(transition_id):
			sorted_ids.append(transition_id)
	sorted_ids.sort()
	for transition_id in sorted_ids:
		_refresh_transition(transition_id)


func _refresh_transition(transition_id: int) -> void:
	var transition_def = _transition_defs_by_id.get(transition_id)
	if transition_def == null:
		return
	if _externally_managed_transition_ids.has(transition_id):
		return
	if _batch_processing:
		if _batch_transition_evaluation_count >= _batch_transition_evaluation_limit:
			_batch_transition_limit_hit = true
			return
		_batch_transition_evaluation_count += 1
	transition_evaluation_count += 1
	_batch_changed_transition_ids[transition_id] = true
	var active := _is_transition_active(transition_def)
	_transition_active_by_id[transition_id] = active
	var desired: Dictionary = {}
	if active:
		for output_index in range(transition_def.outputs.size()):
			var output_def = transition_def.outputs[output_index]
			if output_def == null or int(output_def.operation) != 0:
				continue
			var target_path := String(output_def.get_normalized_target_state_path())
			var target_variable := get_variable(target_path)
			if target_variable == null:
				continue
			var code_key := String(
				_build_transition_claim_code_key(
					transition_def,
					output_def,
					output_index
				)
			)
			desired[_transition_claim_key(target_path, code_key)] = {
				"target_path": target_path,
				"code_key": code_key,
				"value": output_def.get_target_value(target_variable.definition),
			}
	var existing: Array = _transition_claim_entries_by_id.get(transition_id, [])
	for entry_variant in existing:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		var target_path := str(entry.get("target_path", ""))
		var code_key := str(entry.get("code_key", ""))
		if not desired.has(_transition_claim_key(target_path, code_key)):
			clear_claim(target_path, StringName(code_key))
	var next_entries: Array[Dictionary] = []
	for entry_variant in desired.values():
		var entry := entry_variant as Dictionary
		var target_path := str(entry.get("target_path", ""))
		var code_key := str(entry.get("code_key", ""))
		set_claim(target_path, StringName(code_key), entry.get("value"))
		next_entries.append({"target_path": target_path, "code_key": code_key})
	if next_entries.is_empty():
		_transition_claim_entries_by_id.erase(transition_id)
	else:
		_transition_claim_entries_by_id[transition_id] = next_entries


func _clear_transition_claim_entries(transition_id: int) -> void:
	var existing: Array = _transition_claim_entries_by_id.get(transition_id, [])
	_transition_claim_entries_by_id.erase(transition_id)
	for entry_variant in existing:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		clear_claim(
			str(entry.get("target_path", "")),
			StringName(str(entry.get("code_key", "")))
		)
	_transition_active_by_id[transition_id] = false


func _is_transition_active(transition_def) -> bool:
	for condition_variant in transition_def.conditions:
		var condition: Variant = condition_variant
		if condition == null:
			continue
		var target_variable := get_variable(
			String(condition.get_normalized_target_state_path())
		)
		if (
			target_variable == null
			or not bool(condition.matches(
				target_variable.definition,
				target_variable.resolved_value
			))
		):
			return false
	return true


func _build_transition_claim_code_key(
	transition_def,
	output_def,
	output_index: int
) -> StringName:
	var suffix := String(output_def.get_normalized_target_claim_slot_id())
	if suffix.is_empty():
		suffix = "output_%d" % output_index
	return StringName(
		"transition/%d/%s"
			% [int(transition_def.get_normalized_transition_id()), suffix]
	)


func _transition_claim_key(target_path: String, code_key: String) -> String:
	return "%s|%s" % [
		_normalize_path(target_path),
		str(code_key).strip_edges().to_lower(),
	]


func _validate_outgoing_change_graph() -> void:
	_blocked_emitter_paths.clear()
	_invalid_targets_by_source.clear()
	_case_emitter_source_paths.clear()
	var graph: Dictionary = {}
	for definition in database.get_definitions():
		if definition == null:
			continue
		var source_path := String(definition.get_normalized_path())
		var unique_targets: Dictionary = {}
		for case_def in definition.get_case_definitions():
			if case_def == null:
				continue
			for change in case_def.outgoing_changes:
				if change == null:
					continue
				var target_path := String(change.get_normalized_target_path())
				if target_path == source_path:
					_mark_invalid_target(source_path, target_path, "self-reference")
				elif not _variables_by_path.has(target_path):
					_mark_invalid_target(source_path, target_path, "unknown target")
				elif not target_path.is_empty():
					unique_targets[target_path] = true
					_case_emitter_source_paths[source_path] = true
		graph[source_path] = unique_targets.keys()
	var visit_state: Dictionary = {}
	var stack: Array[String] = []
	for source_path in graph.keys():
		if int(visit_state.get(source_path, 0)) == 0:
			_validate_graph_node(String(source_path), graph, visit_state, stack)


func _validate_graph_node(
	node: String,
	graph: Dictionary,
	visit_state: Dictionary,
	stack: Array[String]
) -> void:
	visit_state[node] = 1
	stack.append(node)
	for neighbor_variant in graph.get(node, []):
		var neighbor := String(neighbor_variant)
		var state := int(visit_state.get(neighbor, 0))
		if state == 0:
			_validate_graph_node(neighbor, graph, visit_state, stack)
		elif state == 1:
			var cycle_start := stack.find(neighbor)
			for index in range(cycle_start, stack.size()):
				var cycle_node := stack[index]
				_blocked_emitter_paths[cycle_node] = true
				_try_log_warning(func() -> String:
					return (
						"State machine '%s': outgoing changes for '%s' were rejected because they participate in a cycle."
							% [String(get_scope_key()), cycle_node]
					)
				)
	stack.pop_back()
	visit_state[node] = 2


func _rebuild_transition_dependency_indexes() -> void:
	_transition_ids_by_condition_path.clear()
	_transition_defs_by_id.clear()
	_transition_active_by_id.clear()
	for transition_def in database.get_transition_definitions():
		if transition_def == null:
			continue
		var transition_id := int(transition_def.get_normalized_transition_id())
		if transition_id <= 0:
			continue
		_transition_defs_by_id[transition_id] = transition_def
		for condition in transition_def.conditions:
			if condition == null:
				continue
			var source_path := _normalize_path(
				String(condition.get_normalized_target_state_path())
			)
			if source_path.is_empty():
				continue
			if not _transition_ids_by_condition_path.has(source_path):
				_transition_ids_by_condition_path[source_path] = []
			var ids: Array = _transition_ids_by_condition_path[source_path]
			if not ids.has(transition_id):
				ids.append(transition_id)


func _mark_invalid_target(
	source_path: String,
	target_path: String,
	reason: String
) -> void:
	if not _invalid_targets_by_source.has(source_path):
		_invalid_targets_by_source[source_path] = {}
	_invalid_targets_by_source[source_path][target_path] = true
	_try_log_warning(func() -> String:
		return (
			"State machine '%s': outgoing change from '%s' to '%s' was rejected (%s)."
				% [String(get_scope_key()), source_path, target_path, reason]
		)
	)


func _on_variable_resolved_value_changed(
	variable_path: StringName,
	_old_value: Variant,
	_new_value: Variant
) -> void:
	if _batch_flushing:
		return
	var source_path := _normalize_path(String(variable_path))
	if _case_emitter_source_paths.has(source_path) or _emitted_claims_by_source.has(source_path):
		_refresh_emitted_claims_for_source(source_path)
	var transition_ids: Array = _transition_ids_by_condition_path.get(source_path, [])
	if not transition_ids.is_empty():
		_refresh_transition_ids(transition_ids)


func _build_state_snapshot(variable: StateVariable) -> Dictionary:
	var definition := variable.definition
	return {
		"path": String(variable.get_path()),
		"group": definition.get_group_name(),
		"name": definition.get_leaf_name(),
		"value_type": int(definition.value_type),
		"value_type_name": definition.get_value_type_name(),
		"resolver": int(definition.resolver),
		"resolver_name": definition.get_resolver_name(),
		"resolved_value": serialize_value(definition, variable.resolved_value),
		"default_value": serialize_value(definition, variable.get_default_value()),
		"override_enabled": variable.has_override(),
		"override_value": serialize_value(definition, variable.get_override_value()),
		"base_enabled": variable.has_base_value(),
		"base_value": serialize_value(definition, variable.get_base_value()),
		"possible_values": definition.possible_values.duplicate(),
		"graph_position": definition.graph_position,
		"claim_slots": variable.get_claim_snapshots(),
	}


func _build_transition_snapshot(transition_id: int) -> Dictionary:
	var transition_def = _transition_defs_by_id.get(transition_id)
	if transition_def == null:
		return {}
	var conditions: Array[Dictionary] = []
	for condition in transition_def.conditions:
		if condition == null:
			continue
		var target_path := String(condition.get_normalized_target_state_path())
		var target_variable := get_variable(target_path) if int(condition.target_scope) == 0 else null
		conditions.append({
			"target_state_path": target_path,
			"target_scope": int(condition.target_scope),
			"binding_key": String(condition.get_normalized_binding_key()),
			"target_scope_key": _reference_scope_key(condition),
			"operator": int(condition.operator),
			"expected_value": condition.get_expected_value(
				target_variable.definition if target_variable != null else null
			),
			"active": bool(_transition_active_by_id.get(transition_id, false)),
		})
	var outputs: Array[Dictionary] = []
	for output_def in transition_def.outputs:
		if output_def == null:
			continue
		var target_path := String(output_def.get_normalized_target_state_path())
		var target_variable := get_variable(target_path) if int(output_def.target_scope) == 0 else null
		outputs.append({
			"target_state_path": target_path,
			"target_scope": int(output_def.target_scope),
			"binding_key": String(output_def.get_normalized_binding_key()),
			"target_scope_key": _reference_scope_key(output_def),
			"target_claim_slot_id": String(output_def.get_normalized_target_claim_slot_id()),
			"operation": int(output_def.operation),
			"value": output_def.get_target_value(
				target_variable.definition if target_variable != null else null
			),
			"active": bool(_transition_active_by_id.get(transition_id, false)),
		})
	return {
		"transition_id": transition_id,
		"display_name": transition_def.get_display_name(),
		"active": bool(_transition_active_by_id.get(transition_id, false)),
		"graph_position": transition_def.graph_position,
		"invalid_reason": "",
		"conditions": conditions,
		"outputs": outputs,
	}


func _reference_scope_key(reference) -> String:
	match int(reference.target_scope):
		0:
			return String(get_scope_key())
		1:
			return String(StateMachineScopeAddress.GLOBAL_KEY)
		2:
			return String(get_bound_scope_key(reference.get_normalized_binding_key()))
		_:
			return ""


func serialize_value(definition: StateVariableDef, value: Variant) -> Variant:
	match definition.value_type:
		StateVariableDef.ValueType.ENUM_TOGGLE:
			return definition.enum_toggle_values(value)
		StateVariableDef.ValueType.LIST:
			return definition.list_keys(value)
		StateVariableDef.ValueType.VECTOR2:
			if value == null:
				return null
			var vector := value as Vector2
			return [vector.x, vector.y]
		StateVariableDef.ValueType.VECTOR3:
			if value == null:
				return null
			var vector3 := value as Vector3
			return [vector3.x, vector3.y, vector3.z]
		_:
			return value


func _duplicate_state_value(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value


func _sorted_string_keys(values: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for key_variant in values.keys():
		result.append(String(key_variant))
	result.sort()
	return result


func _log_state_value_changed(
	path: String,
	old_value: Variant,
	new_value: Variant,
	source: String
) -> void:
	if _suppressed_value_log_paths.has(_normalize_path(path)):
		return
	if Console == null or not Console.supports("try_log"):
		return
	if Console.supports("can_log") and not Console.can_log(LogLevel.DEBUG, _STATE_CHANGE_LOG_CHANNEL):
		return
	Console.try_log(
		func() -> Array:
			return [
				"state changed scope=%s path=%s source=%s old=%s new=%s"
					% [
						String(get_scope_key()),
						path,
						source,
						_state_debug_value_to_string(old_value),
						_state_debug_value_to_string(new_value),
					]
			],
		LogLevel.DEBUG,
		_STATE_CHANGE_LOG_CHANNEL
	)


func _log_unknown_variable(operation: String, path: String) -> void:
	_try_log_warning(func() -> String:
		return (
			"State machine '%s'.%s: unknown variable '%s'."
				% [String(get_scope_key()), operation, path]
		)
	)


func _try_log_warning(message_factory: Callable) -> void:
	if (
		not message_factory.is_valid()
		or Console == null
		or not Console.supports("try_log")
	):
		return
	Console.try_log(
		func() -> Array: return [message_factory.call()],
		LogLevel.WARN,
		_STATE_WARNING_LOG_CHANNEL
	)


func _state_debug_value_to_string(value: Variant) -> String:
	var text := var_to_str(value).replace("\n", "\\n")
	if text.length() > 240:
		return "%s..." % text.substr(0, 237)
	return text


func _normalize_path(path: String) -> String:
	return path.strip_edges().to_lower()


func _glob_matches(pattern: String, text: String) -> bool:
	var regex := RegEx.new()
	var escaped := ""
	for character in pattern:
		if character == "*":
			escaped += ".*"
		elif character in ["\\", ".", "^", "$", "|", "(", ")", "[", "]", "{", "}", "+", "?", "-"]:
			escaped += "\\%s" % character
		else:
			escaped += character
	return regex.compile("^%s$" % escaped) == OK and regex.search(text) != null
