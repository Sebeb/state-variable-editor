extends RefCounted
class_name StateMachineCoordinator

const Console = preload("state_console.gd")

const LogLevel = preload("state_log_level.gd")
const StateMachineRuntime = preload("state_machine_runtime.gd")
const StateMachineScopeAddress = preload("state_machine_scope_address.gd")
const StateTransitionScope = preload("state_transition_scope.gd")
const StateVariableDatabase = preload("state_variable_database.gd")

const _STATE_WARNING_LOG_CHANNEL := "State"

signal runtime_registered(scope_key: StringName, runtime: StateMachineRuntime)
signal runtime_unregistered(scope_key: StringName)

var global_runtime: StateMachineRuntime = null
var transition_evaluation_count := 0
var last_evaluation_limit_hit := false

var _runtimes_by_scope: Dictionary = {}
var _handles_by_dependency_key: Dictionary = {}
var _handles_by_owner_scope: Dictionary = {}
var _bridge_claims_by_handle: Dictionary = {}
var _dirty_dependency_keys: Dictionary = {}
var _reported_invalid_references: Dictionary = {}
var _processing_queue := false
var _evaluation_count_in_transaction := 0
var _evaluation_limit_in_transaction := 0


func configure_global(database: StateVariableDatabase) -> StateMachineRuntime:
	if global_runtime != null:
		return global_runtime
	var runtime := StateMachineRuntime.new()
	if not runtime.configure(
		database,
		StateMachineScopeAddress.global_scope(),
		true,
		true
	):
		return null
	global_runtime = runtime
	_runtimes_by_scope[StateMachineScopeAddress.GLOBAL_KEY] = runtime
	_connect_runtime(runtime)
	_rebuild_indexes()
	return runtime


func register_runtime(runtime: StateMachineRuntime) -> bool:
	if runtime == null or runtime.is_torn_down():
		return false
	var scope_key := runtime.get_scope_key()
	if scope_key == &"" or scope_key == StateMachineScopeAddress.GLOBAL_KEY:
		return false
	if _runtimes_by_scope.has(scope_key):
		return false
	_runtimes_by_scope[scope_key] = runtime
	_connect_runtime(runtime)
	_rebuild_indexes()
	_evaluate_all_coordinator_transitions()
	runtime_registered.emit(scope_key, runtime)
	return true


func unregister_runtime(scope_key: StringName) -> bool:
	var normalized_key := _normalize_scope_key(scope_key)
	if normalized_key == &"" or normalized_key == StateMachineScopeAddress.GLOBAL_KEY:
		return false
	var runtime := _runtimes_by_scope.get(normalized_key) as StateMachineRuntime
	if runtime == null:
		return false
	_clear_owner_scope_bridges(normalized_key)
	_disconnect_runtime(runtime)
	_runtimes_by_scope.erase(normalized_key)
	runtime.teardown()
	_rebuild_indexes()
	_evaluate_all_coordinator_transitions()
	runtime_unregistered.emit(normalized_key)
	return true


func get_runtime(scope_key: StringName) -> StateMachineRuntime:
	return _runtimes_by_scope.get(_normalize_scope_key(scope_key))


func get_registered_scope_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for key_variant in _runtimes_by_scope.keys():
		keys.append(StringName(key_variant))
	keys.sort_custom(func(a: StringName, b: StringName): return String(a) < String(b))
	return keys


func get_dependency_key(scope_key: StringName, path: String) -> String:
	return "%s|%s" % [String(_normalize_scope_key(scope_key)), _normalize_path(path)]


func teardown() -> void:
	var scope_keys := get_registered_scope_keys()
	for scope_key in scope_keys:
		if scope_key == StateMachineScopeAddress.GLOBAL_KEY:
			continue
		unregister_runtime(scope_key)
	if global_runtime != null:
		_disconnect_runtime(global_runtime)
		global_runtime.teardown()
	global_runtime = null
	_runtimes_by_scope.clear()
	_handles_by_dependency_key.clear()
	_handles_by_owner_scope.clear()
	_bridge_claims_by_handle.clear()
	_dirty_dependency_keys.clear()
	_reported_invalid_references.clear()


func _connect_runtime(runtime: StateMachineRuntime) -> void:
	if not runtime.batch_committed.is_connected(_on_runtime_batch_committed.bind(runtime)):
		runtime.batch_committed.connect(_on_runtime_batch_committed.bind(runtime))


func _disconnect_runtime(runtime: StateMachineRuntime) -> void:
	var callback := _on_runtime_batch_committed.bind(runtime)
	if runtime.batch_committed.is_connected(callback):
		runtime.batch_committed.disconnect(callback)


func _index_runtime(runtime: StateMachineRuntime) -> void:
	var owner_scope := runtime.get_scope_key()
	var external_ids: Array[int] = []
	var handles: Array[Dictionary] = []
	for transition_id_variant in runtime.get_transition_definitions_by_id().keys():
		var transition_id := int(transition_id_variant)
		var transition_def = runtime.get_transition_definition(transition_id)
		if transition_def == null or not _transition_requires_coordinator(transition_def):
			continue
		external_ids.append(transition_id)
		var handle := {
			"owner_scope": owner_scope,
			"transition_id": transition_id,
		}
		handles.append(handle)
		for condition in transition_def.conditions:
			if condition == null:
				continue
			var target_runtime := _resolve_target_runtime(runtime, condition)
			if target_runtime == null:
				continue
			var dependency_key := get_dependency_key(
				target_runtime.get_scope_key(),
				String(condition.get_normalized_target_state_path())
			)
			if not _handles_by_dependency_key.has(dependency_key):
				_handles_by_dependency_key[dependency_key] = []
			(_handles_by_dependency_key[dependency_key] as Array).append(handle)
	_handles_by_owner_scope[owner_scope] = handles
	runtime.set_externally_managed_transition_ids(external_ids)
	_sort_dependency_handles()


func _rebuild_indexes() -> void:
	_handles_by_dependency_key.clear()
	_handles_by_owner_scope.clear()
	for scope_key in get_registered_scope_keys():
		var runtime := get_runtime(scope_key)
		if runtime != null:
			_index_runtime(runtime)


func _unindex_owner_scope(owner_scope: StringName) -> void:
	var handles: Array = _handles_by_owner_scope.get(owner_scope, [])
	_handles_by_owner_scope.erase(owner_scope)
	for dependency_key_variant in _handles_by_dependency_key.keys():
		var dependency_key := String(dependency_key_variant)
		var retained: Array = []
		for handle_variant in _handles_by_dependency_key[dependency_key]:
			var handle := handle_variant as Dictionary
			if StringName(handle.get("owner_scope", &"")) != owner_scope:
				retained.append(handle)
		if retained.is_empty():
			_handles_by_dependency_key.erase(dependency_key)
		else:
			_handles_by_dependency_key[dependency_key] = retained
	for handle_variant in handles:
		var handle := handle_variant as Dictionary
		_bridge_claims_by_handle.erase(_handle_key(
			StringName(handle.get("owner_scope", &"")),
			int(handle.get("transition_id", 0))
		))


func _sort_dependency_handles() -> void:
	for dependency_key_variant in _handles_by_dependency_key.keys():
		(_handles_by_dependency_key[dependency_key_variant] as Array).sort_custom(
			func(a: Dictionary, b: Dictionary):
				var a_scope := String(a.get("owner_scope", &""))
				var b_scope := String(b.get("owner_scope", &""))
				if a_scope != b_scope:
					return a_scope < b_scope
				return int(a.get("transition_id", 0)) < int(b.get("transition_id", 0))
		)


func _transition_requires_coordinator(transition_def) -> bool:
	for condition in transition_def.conditions:
		if condition != null and int(condition.target_scope) != StateTransitionScope.Scope.CURRENT:
			return true
	for output_def in transition_def.outputs:
		if output_def != null and int(output_def.target_scope) != StateTransitionScope.Scope.CURRENT:
			return true
	return false


func _on_runtime_batch_committed(
	changed_paths: PackedStringArray,
	_membership_changed_paths: PackedStringArray,
	_override_membership_changed_paths: PackedStringArray,
	_changed_transition_ids: PackedInt32Array,
	runtime: StateMachineRuntime
) -> void:
	if runtime == null or runtime.is_torn_down():
		return
	for path in changed_paths:
		_dirty_dependency_keys[get_dependency_key(runtime.get_scope_key(), path)] = true
	_process_fixed_point_queue()


func _evaluate_owner_scope(owner_scope: StringName) -> void:
	var handles: Array = _handles_by_owner_scope.get(owner_scope, [])
	for handle_variant in handles:
		var handle := handle_variant as Dictionary
		_dirty_dependency_keys[
			"register|%s|%d" % [
				String(owner_scope),
				int(handle.get("transition_id", 0)),
			]
		] = handle
	_process_fixed_point_queue()


func _evaluate_all_coordinator_transitions() -> void:
	for owner_scope in get_registered_scope_keys():
		_evaluate_owner_scope(owner_scope)


func _process_fixed_point_queue() -> void:
	if _processing_queue or _dirty_dependency_keys.is_empty():
		return
	_processing_queue = true
	last_evaluation_limit_hit = false
	_evaluation_count_in_transaction = 0
	_evaluation_limit_in_transaction = maxi(1, _coordinator_transition_count() * 8)
	while not _dirty_dependency_keys.is_empty():
		var dirty_keys: Array[String] = []
		for key_variant in _dirty_dependency_keys.keys():
			dirty_keys.append(String(key_variant))
		dirty_keys.sort()
		var pending := _dirty_dependency_keys.duplicate()
		_dirty_dependency_keys.clear()
		var handles_by_key: Dictionary = {}
		for dirty_key in dirty_keys:
			var registration_handle: Variant = pending.get(dirty_key)
			if registration_handle is Dictionary:
				var handle := registration_handle as Dictionary
				handles_by_key[_handle_key(
					StringName(handle.get("owner_scope", &"")),
					int(handle.get("transition_id", 0))
				)] = handle
				continue
			for handle_variant in _handles_by_dependency_key.get(dirty_key, []):
				var handle := handle_variant as Dictionary
				handles_by_key[_handle_key(
					StringName(handle.get("owner_scope", &"")),
					int(handle.get("transition_id", 0))
				)] = handle
		var handles: Array[Dictionary] = []
		for handle_variant in handles_by_key.values():
			handles.append(handle_variant as Dictionary)
		handles.sort_custom(
			func(a: Dictionary, b: Dictionary):
				var a_scope := String(a.get("owner_scope", &""))
				var b_scope := String(b.get("owner_scope", &""))
				if a_scope != b_scope:
					return a_scope < b_scope
				return int(a.get("transition_id", 0)) < int(b.get("transition_id", 0))
		)
		for handle in handles:
			if _evaluation_count_in_transaction >= _evaluation_limit_in_transaction:
				last_evaluation_limit_hit = true
				_dirty_dependency_keys.clear()
				_log_evaluation_limit()
				break
			_evaluate_handle(handle)
		if last_evaluation_limit_hit:
			break
	_processing_queue = false


func _evaluate_handle(handle: Dictionary) -> void:
	var owner_scope := StringName(handle.get("owner_scope", &""))
	var transition_id := int(handle.get("transition_id", 0))
	var owner_runtime := get_runtime(owner_scope)
	if owner_runtime == null:
		return
	var transition_def = owner_runtime.get_transition_definition(transition_id)
	if transition_def == null:
		return
	_evaluation_count_in_transaction += 1
	transition_evaluation_count += 1
	var active := true
	for condition in transition_def.conditions:
		if condition == null:
			continue
		var target_runtime := _resolve_target_runtime(owner_runtime, condition)
		var target_variable = (
			target_runtime.get_variable(String(condition.get_normalized_target_state_path()))
			if target_runtime != null
			else null
		)
		if target_runtime != null and target_variable == null:
			_log_invalid_reference(
				owner_runtime,
				condition,
				"unknown target path"
			)
		if (
			target_variable == null
			or not bool(condition.matches(
				target_variable.definition,
				target_variable.resolved_value
			))
		):
			active = false
			break
	owner_runtime.record_external_transition_evaluation(transition_id, active)
	_apply_transition_outputs(owner_runtime, transition_def, active)


func _apply_transition_outputs(owner_runtime: StateMachineRuntime, transition_def, active: bool) -> void:
	var owner_scope := owner_runtime.get_scope_key()
	var transition_id := int(transition_def.get_normalized_transition_id())
	var handle_key := _handle_key(owner_scope, transition_id)
	var desired: Dictionary = {}
	if active:
		for output_index in range(transition_def.outputs.size()):
			var output_def = transition_def.outputs[output_index]
			if output_def == null or int(output_def.operation) != 0:
				continue
			var target_runtime := _resolve_target_runtime(owner_runtime, output_def)
			if target_runtime == null:
				continue
			var target_path := String(output_def.get_normalized_target_state_path())
			var target_variable = target_runtime.get_variable(target_path)
			if target_variable == null:
				_log_invalid_reference(
					owner_runtime,
					output_def,
					"unknown target path"
				)
				continue
			var slot := String(output_def.get_normalized_target_claim_slot_id())
			if slot.is_empty():
				slot = "output_%d" % output_index
			var code_key := StringName(
				"transition/%s/%d/%s" % [String(owner_scope), transition_id, slot]
			)
			var entry_key := "%s|%s|%s" % [
				String(target_runtime.get_scope_key()),
				target_path,
				String(code_key),
			]
			desired[entry_key] = {
				"target_scope": target_runtime.get_scope_key(),
				"target_path": target_path,
				"code_key": code_key,
				"value": output_def.get_target_value(target_variable.definition),
			}
	var existing: Dictionary = _bridge_claims_by_handle.get(handle_key, {})
	for entry_key_variant in existing.keys():
		var entry_key := String(entry_key_variant)
		if desired.has(entry_key):
			continue
		_clear_bridge_entry(existing[entry_key] as Dictionary)
	for entry_key_variant in desired.keys():
		var entry := desired[entry_key_variant] as Dictionary
		var target_runtime := get_runtime(StringName(entry.get("target_scope", &"")))
		if target_runtime != null:
			target_runtime.set_claim(
				String(entry.get("target_path", "")),
				StringName(entry.get("code_key", &"")),
				entry.get("value")
			)
	if desired.is_empty():
		_bridge_claims_by_handle.erase(handle_key)
	else:
		_bridge_claims_by_handle[handle_key] = desired


func _clear_owner_scope_bridges(owner_scope: StringName) -> void:
	for handle_key_variant in _bridge_claims_by_handle.keys():
		var handle_key := String(handle_key_variant)
		if not handle_key.begins_with("%s|" % String(owner_scope)):
			continue
		var entries := (
			_bridge_claims_by_handle.get(handle_key, {}) as Dictionary
		).duplicate()
		_bridge_claims_by_handle.erase(handle_key)
		for entry_variant in entries.values():
			_clear_bridge_entry(entry_variant as Dictionary)


func _clear_bridge_entry(entry: Dictionary) -> void:
	var target_runtime := get_runtime(StringName(entry.get("target_scope", &"")))
	if target_runtime != null:
		target_runtime.clear_claim(
			String(entry.get("target_path", "")),
			StringName(entry.get("code_key", &""))
		)


func _resolve_target_runtime(owner_runtime: StateMachineRuntime, reference) -> StateMachineRuntime:
	if owner_runtime == null or reference == null:
		return null
	match int(reference.target_scope):
		StateTransitionScope.Scope.CURRENT:
			return owner_runtime
		StateTransitionScope.Scope.GLOBAL:
			if global_runtime == null:
				_log_invalid_reference(owner_runtime, reference, "global scope is unavailable")
			return global_runtime
		StateTransitionScope.Scope.BOUND:
			var binding_key: StringName = reference.get_normalized_binding_key()
			if binding_key == &"":
				_log_invalid_reference(owner_runtime, reference, "binding key is empty")
				return null
			var target_scope_key := owner_runtime.get_bound_scope_key(binding_key)
			if target_scope_key == &"":
				_log_invalid_reference(owner_runtime, reference, "binding is not allowlisted")
				return null
			var target_runtime := get_runtime(target_scope_key)
			if target_runtime == null:
				_log_invalid_reference(owner_runtime, reference, "bound scope is not registered")
			return target_runtime
		_:
			_log_invalid_reference(owner_runtime, reference, "scope qualifier is invalid")
			return null


func _coordinator_transition_count() -> int:
	var count := 0
	for handles_variant in _handles_by_owner_scope.values():
		count += (handles_variant as Array).size()
	return count


func _handle_key(owner_scope: StringName, transition_id: int) -> String:
	return "%s|%010d" % [String(owner_scope), transition_id]


func _normalize_scope_key(scope_key: StringName) -> StringName:
	return StringName(String(scope_key).strip_edges().to_lower())


func _normalize_path(path: String) -> String:
	return path.strip_edges().to_lower()


func _log_evaluation_limit() -> void:
	if Console == null or not Console.supports("try_log"):
		return
	Console.try_log(
		func() -> Array:
			return [
				"State-machine coordinator exceeded its deterministic evaluation cap (%d)."
					% _evaluation_limit_in_transaction
			],
		LogLevel.WARN,
		_STATE_WARNING_LOG_CHANNEL
	)


func _log_invalid_reference(
	owner_runtime: StateMachineRuntime,
	reference,
	reason: String
) -> void:
	if owner_runtime == null or reference == null:
		return
	var diagnostic_key := "%s|%d|%s|%s|%s" % [
		String(owner_runtime.get_scope_key()),
		int(reference.target_scope),
		String(reference.get_normalized_binding_key()),
		String(reference.get_normalized_target_state_path()),
		reason,
	]
	if _reported_invalid_references.has(diagnostic_key):
		return
	_reported_invalid_references[diagnostic_key] = true
	if Console == null or not Console.supports("try_log"):
		return
	Console.try_log(
		func() -> Array:
			return [
				"State scope reference failed owner=%s scope=%d binding=%s path=%s reason=%s"
					% [
						String(owner_runtime.get_scope_key()),
						int(reference.target_scope),
						String(reference.get_normalized_binding_key()),
						String(reference.get_normalized_target_state_path()),
						reason,
					]
			],
		LogLevel.WARN,
		_STATE_WARNING_LOG_CHANNEL
	)
