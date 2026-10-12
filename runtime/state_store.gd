extends Node

const LogLevel = preload("state_log_level.gd")
const StateGraphOverlayScript = preload("state_graph_debug_overlay.gd")
const StoreAccess = preload("state_store_access.gd")
const StateConsole = preload("state_console.gd")
var Console: Object = null
const StatePathAliases = preload("state_path_aliases.gd")
const StateVariable = preload("state_variable.gd")
const StateVariableCaseDef = preload("state_variable_case_def.gd")
const StateVariableDatabase = preload("state_variable_database.gd")
const StateVariableDef = preload("state_variable_def.gd")
const StateDefaultDatabaseWriter = preload("state_default_database_writer.gd")
const StateVariableGenerator = preload("state_variable_generator.gd")
const StateVariableBaker = preload("state_variable_baker.gd")
const LegacyPersistentStateMigrationV1 = preload("migrations/legacy_persistent_state_v1/legacy_persistent_state_v1.gd")
const StateConsoleNotifier = preload("state_console_notifier.gd")
const StateMachineCoordinator = preload("state_machine_coordinator.gd")
const StateMachineRuntime = preload("state_machine_runtime.gd")
const StateMachineScopeAddress = preload("state_machine_scope_address.gd")
const _MUTED_CLAIM_ICON = preload("assets/muted-claim.svg")

const _DATABASE_PATH := "res://data/state/state_variable_database.tres"
const _SAVE_PATH := "user://state_variables.cfg"
const _OVERRIDE_SETS_SAVE_PATH := "user://state_override_sets.cfg"
const _OVERRIDE_SET_METADATA_KEY := "__saved_override_set__"
const _CONSOLE_ROOT := ""
const _CONSOLE_OVERRIDES_PATH := "state_overrides"
const _CONSOLE_GROUP_NAME := "state"
const _CONSOLE_GROUP_PRIORITY := -50
const _CONSOLE_OVERRIDE_GROUP_NAME := "override"
const _CONSOLE_OVERRIDE_GROUP_PRIORITY := 30
const _CONSOLE_SET_GROUP_NAME := "set"
const _CONSOLE_SET_GROUP_PRIORITY := 10
const _CONSOLE_DEFAULT_COLOR := Color("9ca3af")
const _CONSOLE_BASE_COLOR := Color("a16207")
const _CONSOLE_FOLDER_CLAIM_COLOR := Color("3b82f6")
const _CONSOLE_FOLDER_OVERRIDE_COLOR := Color("8b5cf6")
const _CONSOLE_FOLDER_BASE_COLOR := Color("a16207")
const _CONSOLE_CLAIMS_GROUP_PRIORITY := 20
const _CONSOLE_BASE_GROUP_PRIORITY := 0
const _CONSOLE_DEFAULT_GROUP_PRIORITY := -10
const _CONSOLE_NO_OVERRIDE_LABEL := "no override"
const _CONSOLE_NO_OVERRIDE_MARKER_KEY := "__state_store_clear_override__"
const _PERSISTENCE_SCHEMA_SECTION := "state_store"
const _PERSISTENCE_SCHEMA_KEY := "schema_version"
const _PERSISTENCE_SCHEMA_VERSION := 2
const _PERSISTENCE_BASES_SECTION := "bases"
const _PERSISTENCE_OVERRIDES_SECTION := "overrides"
const _PERSISTENCE_SAVE_DEBOUNCE_SEC := 0.25
const _STATE_GRAPH_TOGGLE_ACTION := &"toggle_state_graph_debug"
const _STATE_CHANGE_PROBE_ACTION := &"debug_state_change_probe"
const _STATE_CHANGE_PROBE_PATH := "debug/performance/state_change_probe"
const _CPU_ALLOCATION_GROUP_PATH := "project/state_updates"
const _CPU_ALLOCATION_SIGNATURE_PREFIXES := [
	"res://systems/autoload/state_store.gd::",
	"state_machine_runtime.gd::",
	"state_machine_coordinator.gd::",
	"state_variable.gd::",
	"state_value_resolution.gd::",
]
## Keeps the in-game state editor above PostFX and every other runtime overlay.
const STATE_GRAPH_OVERLAY_CANVAS_LAYER := 16384
const _STATE_GRAPH_SCHEMA_VERSION := 2
const _STATE_CHANGE_LOG_CHANNEL := "State/Changes"
const _STATE_CHANGE_LOG_LEVEL := LogLevel.DEBUG
const _STATE_WARNING_LOG_CHANNEL := "State"
const _STATE_WARNING_LOG_LEVEL := LogLevel.WARN

enum ValueLayer {
	DEFAULT,
	BASE,
	OVERRIDE,
}

signal state_graph_debug_mode_changed(mode: StringName)
signal batch_committed(changed_paths: PackedStringArray)
signal claim_snapshots_changed(variable_path: StringName, changed_stable_keys: PackedStringArray)
## Identifies a runtime registry substitution, not an ordinary claim or value
## transition. Consumers that cache StateVariable instances use this to rebind.
signal variable_instance_replaced(
	variable_path: StringName,
	previous_variable: StateVariable,
	replacement_variable: StateVariable
)
signal state_graph_delta_ready(delta: Dictionary)
signal state_graph_scope_registry_changed(event: Dictionary)

var database: StateVariableDatabase = null
var coordinator: StateMachineCoordinator = null
var global_runtime: StateMachineRuntime = null

var _variables_by_path: Dictionary = {}
var _registered_console_commands: Array[String] = []
var _registered_console_display_variables: Array[String] = []
var _registered_override_menu_dynamic_commands: Dictionary = {}
var _registered_override_menu_dynamic_display_variables: Dictionary = {}
var _registered_override_set_commands: Array[String] = []
var _registered_variable_remove_override_commands: Dictionary = {}
var _registered_layered_dynamic_commands: Dictionary = {}
var _registered_layered_dynamic_display_variables: Dictionary = {}
var _registered_layered_claim_commands: Dictionary = {}
var _registered_layered_claim_display_variables: Dictionary = {}
var _registered_layered_folder_commands: Dictionary = {}
var _muted_claim_icon: Texture2D = null
var _persistence_dirty := false
var _persistence_save_pending := false
var _loading_persistent_values := false
var _legacy_migration_retry_required := false
# Runtime-owned maps retained as aliases for the existing graph/debug facade.
var _emitted_claims_by_source: Dictionary = {}
var _blocked_emitter_paths: Dictionary = {}
var _invalid_targets_by_source: Dictionary = {}
var _case_emitter_source_paths: Dictionary = {}
var _transition_ids_by_condition_path: Dictionary = {}
var _transition_defs_by_id: Dictionary = {}
var _transition_claim_entries_by_id: Dictionary = {}
var _transition_active_by_id: Dictionary = {}
var _batch_changed_transition_ids: Dictionary = {}
var _transition_evaluation_count := 0
var _batch_transition_evaluation_count := 0
var _batch_transition_evaluation_limit := 0
var _batch_transition_limit_hit := false
var _batch_processing := false
var _batch_flushing := false
var _state_graph_topology_version := 1
var _state_graph_debug_subscribers: Dictionary = {}
var _state_graph_snapshot_build_count := 0
var _state_graph_delta_emit_count := 0
var _state_graph_debug_mode: StringName = &"hidden"
var _state_graph_selected_scope_key: StringName = &"global"
var _state_graph_overlay: CanvasLayer = null
var _console_notifiers_by_address: Dictionary = {}
var _claim_snapshot_state_by_path: Dictionary = {}
var _pending_claim_snapshot_keys_by_path: Dictionary = {}
var _deferred_claim_console_paths: Dictionary = {}
## Normalized paths of the baked code-declared variables merged into the runtime
## database, so a DEFAULT-layer write can tell whose file owns the default.
var _generated_paths: Dictionary = {}


func _enter_tree() -> void:
	StoreAccess.bind(self)
	StateConsole.service = Console


func _ready() -> void:
	# State transition traces are developer diagnostics. Keeping their channel
	# opt-in avoids synchronous Logot presentation inside gameplay callbacks.
	if Console != null and Console.has_method("set_channel_visibility"):
		Console.set_channel_visibility(_STATE_CHANGE_LOG_CHANNEL, 2)
	if Console != null and Console.has_signal("console_opened") and not Console.console_opened.is_connected(flush_pending_console_updates):
		Console.console_opened.connect(flush_pending_console_updates)
	if Console != null and Console.has_method("register_performance_script_source_group"):
		Console.register_performance_script_source_group(
			_CPU_ALLOCATION_GROUP_PATH,
			"State Updates",
			PackedStringArray(_CPU_ALLOCATION_SIGNATURE_PREFIXES)
		)
	_ensure_state_graph_toggle_action()
	_ensure_state_change_probe_action()
	_load_database()
	coordinator = StateMachineCoordinator.new()
	global_runtime = coordinator.configure_global(database)
	if global_runtime == null:
		_try_log_state_warning(func() -> Array:
			return ["StateStore: Failed to configure the global state-machine runtime."]
		)
		return
	_adopt_global_runtime()
	StoreAccess.bind(self)
	coordinator.runtime_registered.connect(_on_state_machine_runtime_registered)
	coordinator.runtime_unregistered.connect(_on_state_machine_runtime_unregistered)
	batch_changes(func():
		_initialize_host_defaults()
		_load_persistent_values()
		global_runtime.refresh_derived_state()
		if get_variable(_STATE_CHANGE_PROBE_PATH) != null:
			clear_override(_STATE_CHANGE_PROBE_PATH)
			set_claim(_STATE_CHANGE_PROBE_PATH, &"state_store_probe", false)
	)
	_register_console_commands()
	_register_debugger_capture()
	set_process_unhandled_input(true)


func _exit_tree() -> void:
	StoreAccess.unbind(self)
	if Console != null and Console.has_signal("console_opened") and Console.console_opened.is_connected(flush_pending_console_updates):
		Console.console_opened.disconnect(flush_pending_console_updates)
	if Console != null and Console.has_method("unregister_performance_script_source_group"):
		Console.unregister_performance_script_source_group(_CPU_ALLOCATION_GROUP_PATH)
	_set_logot_pinned_overlay_suppressed(false)
	_unregister_console_commands()
	_persistence_save_pending = false
	save_persistent_values()
	if coordinator != null:
		coordinator.teardown()
	coordinator = null
	global_runtime = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_persistence_save_pending = false
		save_persistent_values()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(_STATE_GRAPH_TOGGLE_ACTION):
		cycle_state_graph_debug_mode()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(_STATE_CHANGE_PROBE_ACTION):
		if event is InputEventKey and (event as InputEventKey).echo:
			return
		set_claim(
			_STATE_CHANGE_PROBE_PATH,
			&"state_store_probe",
			not bool(get_value(_STATE_CHANGE_PROBE_PATH, false))
		)
		get_viewport().set_input_as_handled()


## Randomizes /maze/seed once per process launch so mazes differ run to run;
## overriding the variable to 0 preserves the pre-existing generation seed fallback.
func get_variable(path: String) -> StateVariable:
	return global_runtime.get_variable(path) if global_runtime != null else null


## Replaces one global runtime variable and notifies path-scoped consumers that
## cached the previous StateVariable object. Ordinary value changes must continue
## through StateVariable.resolved_value_changed instead.
func replace_variable_instance(path: String, replacement_variable: StateVariable) -> bool:
	return global_runtime != null and global_runtime.replace_variable_instance(path, replacement_variable)


func subscribe_resolved_value_changed(path: String, callback: Callable) -> bool:
	var variable := get_variable(path)
	if variable == null or not callback.is_valid():
		return false
	if variable.resolved_value_changed.is_connected(callback):
		return false
	variable.resolved_value_changed.connect(callback)
	return true


func unsubscribe_resolved_value_changed(path: String, callback: Callable) -> bool:
	var variable := get_variable(path)
	if variable == null or not callback.is_valid() or not variable.resolved_value_changed.is_connected(callback):
		return false
	variable.resolved_value_changed.disconnect(callback)
	return true


func get_variables(pattern: String = "*") -> Array[StateVariable]:
	return global_runtime.get_variables(pattern) if global_runtime != null else []


func get_value(path: String, fallback: Variant = null) -> Variant:
	return global_runtime.get_value(path, fallback) if global_runtime != null else fallback


func _perform_variable_mutation(variable: StateVariable, operation: Callable, source: String = "unknown") -> Variant:
	if global_runtime != null:
		return global_runtime.perform_variable_mutation(variable, operation, source)
	return false


func _try_log_state_warning(message_factory: Callable) -> void:
	if Console == null or not Console.has_method("try_log") or not message_factory.is_valid():
		return
	Console.try_log(message_factory, _STATE_WARNING_LOG_LEVEL, _STATE_WARNING_LOG_CHANNEL)


func batch_changes(callback: Callable) -> bool:
	if global_runtime != null:
		return global_runtime.batch_changes(callback)
	_try_log_state_warning(func() -> Array:
		return ["StateStore.batch_changes: Global runtime is unavailable."]
	)
	return false


func set_claim(path: String, code_key: StringName, value: Variant) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_try_log_state_warning(func() -> Array:
			return ["StateStore.set_claim: Unknown variable '%s'" % path]
		)
		return false
	var changed := bool(_perform_variable_mutation(variable, func(): return variable.set_claim(code_key, value), "set_claim:%s" % String(code_key)))
	if not changed and not variable.last_resolution_error.is_empty():
		_try_log_state_warning(func() -> Array:
			return ["StateStore.set_claim: %s" % variable.last_resolution_error]
		)
	return changed


func mute_claim(path: String, target: Variant) -> bool:
	var variable := get_variable(path)
	return variable != null and bool(_perform_variable_mutation(variable, func(): return variable.mute_claim(target), "mute_claim:%s" % str(target)))


func unmute_claim(path: String, target: Variant) -> bool:
	var variable := get_variable(path)
	return variable != null and bool(_perform_variable_mutation(variable, func(): return variable.unmute_claim(target), "unmute_claim:%s" % str(target)))


func mute_all_claims(path: String) -> int:
	var variable := get_variable(path)
	return int(_perform_variable_mutation(variable, func(): return variable.mute_all_claims(), "mute_all_claims")) if variable != null else 0


func unmute_all_claims(path: String) -> int:
	var variable := get_variable(path)
	return int(_perform_variable_mutation(variable, func(): return variable.unmute_all_claims(), "unmute_all_claims")) if variable != null else 0


func get_claim_snapshots(path: String) -> Array[Dictionary]:
	var variable := get_variable(path)
	if variable == null:
		return []
	var snapshots := variable.get_claim_snapshots()
	var present_transition_ids: Dictionary = {}
	for snapshot in snapshots:
		var code_key := str(snapshot.get("code_key", ""))
		if code_key.begins_with("transition/"):
			var parts := code_key.split("/")
			if parts.size() >= 3:
				var transition_id := int(parts[1])
				snapshot["transition_id"] = transition_id
				present_transition_ids[transition_id] = true
				var slot := variable.definition.get_claim_slot_by_id(StringName(parts[2]))
				if slot != null:
					snapshot["slot_id"] = String(slot.get_normalized_slot_id())
	for slot in variable.definition.get_claim_slot_definitions():
		if slot == null or not slot.is_transition_claim():
			continue
		var transition_id := slot.get_normalized_transition_id()
		if present_transition_ids.has(transition_id):
			continue
		snapshots.append({
			"slot_id": String(slot.get_normalized_slot_id()),
			"code_key": "",
			"transition_id": transition_id,
			"value": null,
			"active": false,
			"muted": false,
			"contributes_to_resolution": false,
			"suppressed_by_resolution": false,
			"activation_serial": 0,
			"update_serial": 0,
			"display_order": snapshots.size(),
		})
	return snapshots


func set_possible_values(path: String, values: Array) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_try_log_state_warning(func() -> Array:
			return ["StateStore.set_possible_values: Unknown variable '%s'" % path]
		)
		return false
	return bool(_perform_variable_mutation(variable, func(): return variable.set_possible_values(values), "set_possible_values"))


func clear_claim(path: String, code_key: StringName) -> bool:
	var variable := get_variable(path)
	if variable == null:
		return false
	return bool(_perform_variable_mutation(variable, func(): return variable.clear_claim(code_key), "clear_claim:%s" % String(code_key)))


func add_claim(path: String, value: Variant) -> int:
	var variable := get_variable(path)
	if variable == null:
		_try_log_state_warning(func() -> Array:
			return ["StateStore.add_claim: Unknown variable '%s'" % path]
		)
		return -1
	return int(_perform_variable_mutation(variable, func(): return variable.add_claim(value), "add_claim"))


func remove_claim(path: String, claim_id: int) -> bool:
	var variable := get_variable(path)
	return variable != null and bool(_perform_variable_mutation(variable, func(): return variable.remove_claim(claim_id), "remove_claim:%d" % claim_id))


func reset_variable(path: String) -> void:
	var variable := get_variable(path)
	if variable != null:
		_perform_variable_mutation(variable, func(): return variable.reset(), "reset_variable")


func reset_matching(pattern: String) -> void:
	batch_changes(func():
		for variable in get_variables(pattern):
			_perform_variable_mutation(variable, func(): return variable.reset(), "reset_matching:%s" % pattern)
	)


func reset_tagged(tag: String) -> void:
	if database == null:
		return
	batch_changes(func():
		for definition in database.get_state_definitions_with_tag(tag):
			var variable := get_variable(String(definition.get_normalized_path()))
			if variable != null:
				_perform_variable_mutation(variable, func(): return variable.reset(), "reset_tagged:%s" % tag)
	)


func set_layer_value(path: String, value: Variant, layer: ValueLayer) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_try_log_state_warning(func() -> Array:
			return ["StateStore.set_layer_value: Unknown variable '%s'" % path]
		)
		return false
	match layer:
		ValueLayer.DEFAULT:
			if is_code_declared(path):
				return _write_code_declared_default(variable, path, value)
			var writer := StateDefaultDatabaseWriter.new()
			var result := writer.write_default(_DATABASE_PATH, variable, value)
			if not bool(result.get("ok", false)):
				_log_default_write_failure(path, result)
			return bool(result.get("changed", false))
		ValueLayer.BASE:
			return bool(_perform_variable_mutation(variable, func(): return variable.set_base_value(value), "set_layer_value:base"))
		ValueLayer.OVERRIDE:
			return bool(_perform_variable_mutation(variable, func(): return variable.set_override(value), "set_layer_value:override"))
		_:
			return false


func clear_base(path: String) -> bool:
	var variable := get_variable(path)
	return variable != null and bool(_perform_variable_mutation(variable, func(): return variable.clear_base(), "clear_base"))


## Persists a code-declared variable's DEFAULT to the resource property that declares it
## (PGO-226).
##
## A code-declared variable has no authored row in the monolithic database — PGO-225 made
## the resource property the source-of-truth default — so the database writer would only
## ever report a missing target here. The runtime value moves only after the file agrees,
## which is the same ordering the database writer uses and the reason a refused write
## never leaves the session showing a default that was not saved.
func _write_code_declared_default(variable: StateVariable, path: String, value: Variant) -> bool:
	var writer := StateDefaultResourceWriter.new()
	var result := writer.write_default(variable, value)
	if not bool(result.get("ok", false)):
		_log_default_write_failure(path, result)
		return false
	if not bool(result.get("changed", false)):
		return false
	if not bool(result.get("bake_ok", true)):
		# The property saved but the derived bake did not, so the shipped default and the
		# resource now disagree until the bake is re-run. Reported rather than treated as
		# a write failure: the source of truth on disk is already correct.
		_try_log_state_warning(func() -> Array:
			return [
				"StateStore: saved the DEFAULT of '%s' to its resource, but re-baking the code-declared variables failed, so the generated defaults are stale: %s" % [
					path, str(result.get("bake_errors", PackedStringArray())),
				]
			]
		)
	return bool(_perform_variable_mutation(
		variable,
		func(): return variable.set_default_value(value),
		"set_layer_value:default_code_declared"
	))


func _log_default_write_failure(path: String, result: Dictionary) -> void:
	if Console == null or not Console.has_method("try_log"):
		return
	var log_level := int(result.get("log_level", LogLevel.ERROR))
	Console.try_log(func() -> Array:
		return ["StateStore DEFAULT write failed for '%s': %s" % [path, str(result.get("message", result.get("reason", "unknown failure")))]]
	, log_level, _STATE_WARNING_LOG_CHANNEL)


func set_enum_toggle_option_enabled(path: String, option: Variant, enabled: bool, layer: ValueLayer) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_try_log_state_warning(func() -> Array:
			return ["StateStore.set_enum_toggle_option_enabled: Unknown variable '%s'" % path]
		)
		return false
	if variable.definition.value_type != StateVariableDef.ValueType.ENUM_TOGGLE:
		return false
	var current_value: Variant = _get_layer_value(variable, layer)
	var next_value: Array = variable.definition.enum_toggle_set_option_enabled(current_value, option, enabled)
	return set_layer_value(path, next_value, layer)


func toggle_enum_toggle_root(path: String, layer: ValueLayer) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_try_log_state_warning(func() -> Array:
			return ["StateStore.toggle_enum_toggle_root: Unknown variable '%s'" % path]
		)
		return false
	if variable.definition.value_type != StateVariableDef.ValueType.ENUM_TOGGLE:
		return false
	var current_value: Array = variable.definition.coerce_value(_get_layer_value(variable, layer))
	var next_value: Array = []
	if variable.definition.enum_toggle_count(current_value) > 0:
		next_value = []
	else:
		next_value = variable.get_last_non_empty_enum_toggle_value()
		if next_value.is_empty():
			next_value = variable.definition.coerce_value(variable.get_default_value())
	return set_layer_value(path, next_value, layer)


func add_list_item(path: String, owner_key: StringName, value: Variant) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_try_log_state_warning(func() -> Array:
			return ["StateStore.add_list_item: Unknown variable '%s'" % path]
		)
		return false
	return bool(_perform_variable_mutation(variable, func(): return variable.add_list_item(owner_key, value), "add_list_item"))


func remove_list_item(path: String, owner_key: StringName, value_or_key: Variant) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_try_log_state_warning(func() -> Array:
			return ["StateStore.remove_list_item: Unknown variable '%s'" % path]
		)
		return false
	return bool(_perform_variable_mutation(variable, func(): return variable.remove_list_item(owner_key, value_or_key), "remove_list_item"))


func clear_list_items(path: String, owner_key: StringName) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_try_log_state_warning(func() -> Array:
			return ["StateStore.clear_list_items: Unknown variable '%s'" % path]
		)
		return false
	return bool(_perform_variable_mutation(variable, func(): return variable.clear_list_items(owner_key), "clear_list_items"))


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


func set_override(path: String, value: Variant) -> bool:
	var variable := get_variable(path)
	if variable == null:
		_try_log_state_warning(func() -> Array:
			return ["StateStore.set_override: Unknown variable '%s'" % path]
		)
		return false
	return bool(_perform_variable_mutation(variable, func(): return variable.set_override(value), "set_override"))


func clear_override(path: String) -> bool:
	var variable := get_variable(path)
	return variable != null and bool(_perform_variable_mutation(variable, func(): return variable.clear_override(), "clear_override"))


func clear_all_overrides() -> int:
	var cleared := [0]
	batch_changes(func():
		for variable in _variables_by_path.values():
			var state_variable := variable as StateVariable
			if state_variable == null:
				continue
			if bool(_perform_variable_mutation(state_variable, func(): return state_variable.clear_override())):
				cleared[0] = int(cleared[0]) + 1
	)
	return int(cleared[0])


func get_overridden_variables(pattern: String = "*") -> Array[StateVariable]:
	var matches: Array[StateVariable] = []
	var normalized_pattern := _normalize_path(pattern)
	for key in _variables_by_path.keys():
		var path := String(key)
		if not _glob_matches(normalized_pattern, path):
			continue
		var variable := _variables_by_path[key] as StateVariable
		if variable == null or not variable.has_override():
			continue
		matches.append(variable)
	matches.sort_custom(func(a: StateVariable, b: StateVariable): return String(a.get_path()) < String(b.get_path()))
	return matches


func get_state_graph_debug_mode() -> String:
	return String(_state_graph_debug_mode)


func cycle_state_graph_debug_mode() -> String:
	match String(_state_graph_debug_mode):
		"hidden":
			_set_state_graph_debug_mode(&"shown")
		"shown":
			_set_state_graph_debug_mode(&"transparent_overlay")
		_:
			_set_state_graph_debug_mode(&"hidden")
	return String(_state_graph_debug_mode)


func get_state_graph_snapshot() -> Dictionary:
	_state_graph_snapshot_build_count += 1
	var state_snapshots: Array[Dictionary] = []
	for state_path in _variables_by_path.keys():
		var snapshot := _build_state_graph_state_snapshot(String(state_path))
		if not snapshot.is_empty():
			state_snapshots.append(snapshot)
	state_snapshots.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.get("path", "")) < str(b.get("path", "")))

	var transition_snapshots: Array[Dictionary] = []
	var transition_defs: Array = []
	if database != null and database.has_method("get_transition_definitions"):
		transition_defs = database.get_transition_definitions()
	for transition_variant in transition_defs:
		var transition_def = transition_variant
		if transition_def == null:
			continue
		var transition_id := int(transition_def.get_normalized_transition_id())
		var snapshot := _build_state_graph_transition_snapshot(transition_id)
		if not snapshot.is_empty():
			transition_snapshots.append(snapshot)
	transition_snapshots.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("transition_id", 0)) < int(b.get("transition_id", 0)))

	return {
		"schema_version": _STATE_GRAPH_SCHEMA_VERSION,
		"topology_version": _state_graph_topology_version,
		"mode": String(_state_graph_debug_mode),
		"scope_key": String(StateMachineScopeAddress.GLOBAL_KEY),
		"template_key": String(StateMachineScopeAddress.GLOBAL_KEY),
		"instance_key": "",
		"scope_registry": get_state_graph_scope_registry(),
		"states": state_snapshots,
		"transitions": transition_snapshots,
	}


func get_state_graph_scope_registry() -> Array[Dictionary]:
	var scopes: Array[Dictionary] = [{
		"scope_key": String(StateMachineScopeAddress.GLOBAL_KEY),
		"template_key": String(StateMachineScopeAddress.GLOBAL_KEY),
		"instance_key": "",
		"display_name": "Global",
		"live": global_runtime != null,
	}]
	if coordinator == null:
		return scopes
	for scope_key in coordinator.get_registered_scope_keys():
		if scope_key == StateMachineScopeAddress.GLOBAL_KEY:
			continue
		var runtime := coordinator.get_runtime(scope_key)
		if runtime == null or runtime.scope_address == null:
			continue
		scopes.append({
			"scope_key": String(scope_key),
			"template_key": String(runtime.scope_address.template_key),
			"instance_key": String(runtime.scope_address.instance_key),
			"display_name": "%s / %s" % [
				String(runtime.scope_address.template_key),
				String(runtime.scope_address.instance_key),
			],
			"live": true,
		})
	return scopes


func get_state_graph_snapshot_for_scope(scope_key: StringName) -> Dictionary:
	var normalized_scope_key := StringName(String(scope_key).strip_edges().to_lower())
	if normalized_scope_key == &"" or normalized_scope_key == StateMachineScopeAddress.GLOBAL_KEY:
		return get_state_graph_snapshot()
	if coordinator == null:
		return {}
	var runtime := coordinator.get_runtime(normalized_scope_key)
	if runtime == null:
		return {}
	_state_graph_snapshot_build_count += 1
	var snapshot := runtime.get_state_graph_snapshot()
	snapshot["schema_version"] = _STATE_GRAPH_SCHEMA_VERSION
	snapshot["topology_version"] = _state_graph_topology_version
	snapshot["mode"] = String(_state_graph_debug_mode)
	snapshot["scope_key"] = String(normalized_scope_key)
	snapshot["template_key"] = String(runtime.scope_address.template_key) if runtime.scope_address != null else ""
	snapshot["instance_key"] = String(runtime.scope_address.instance_key) if runtime.scope_address != null else ""
	snapshot["scope_registry"] = get_state_graph_scope_registry()
	return snapshot


func select_state_graph_scope(scope_key: StringName) -> bool:
	var normalized_scope_key := StringName(String(scope_key).strip_edges().to_lower())
	if (
		normalized_scope_key != StateMachineScopeAddress.GLOBAL_KEY
		and (
			coordinator == null
			or coordinator.get_runtime(normalized_scope_key) == null
		)
	):
		return false
	_state_graph_selected_scope_key = normalized_scope_key
	return true


func _build_state_graph_state_snapshot(state_path: String) -> Dictionary:
	var variable := get_variable(state_path)
	if variable == null:
		return {}
	var definition := variable.definition
	return {
		"path": String(variable.get_path()),
		"group": definition.get_group_name(),
		"name": definition.get_leaf_name(),
		"value_type": int(definition.value_type),
		"value_type_name": definition.get_value_type_name(),
		"resolver": int(definition.resolver),
		"resolver_name": definition.get_resolver_name(),
		"resolved_value": _serialize_value(definition, variable.resolved_value),
		"default_value": _serialize_value(definition, variable.get_default_value()),
		"override_enabled": variable.has_override(),
		"override_value": _serialize_value(definition, variable.get_override_value()),
		"base_enabled": variable.has_base_value(),
		"base_value": _serialize_value(definition, variable.get_base_value()),
		"possible_values": definition.possible_values.duplicate(),
		"graph_position": definition.graph_position,
		"claim_slots": variable.get_claim_snapshots(),
	}


func _build_state_graph_transition_snapshot(transition_id: int) -> Dictionary:
	var transition_def = _transition_defs_by_id.get(transition_id)
	if transition_def == null and database != null:
		transition_def = database.get_transition_by_id(transition_id)
	if transition_def == null:
		return {}
	var condition_snapshots: Array[Dictionary] = []
	var active := true
	var invalid_reason := ""
	for condition_variant in transition_def.conditions:
		var condition = condition_variant
		if condition == null:
			continue
		var target_path := String(condition.get_normalized_target_state_path())
		var target_variable := get_variable(target_path)
		var condition_active := false
		if target_variable != null:
			condition_active = bool(condition.matches(target_variable.definition, target_variable.resolved_value))
		else:
			active = false
			if invalid_reason.is_empty():
				invalid_reason = "unknown condition target"
		condition_snapshots.append({
			"target_state_path": target_path,
			"operator": int(condition.operator),
			"expected_value": condition.get_expected_value(target_variable.definition if target_variable != null else null),
			"active": condition_active,
		})
		active = active and condition_active
	var output_snapshots: Array[Dictionary] = []
	for output_variant in transition_def.outputs:
		var output_def = output_variant
		if output_def == null:
			continue
		var output_target_path := String(output_def.get_normalized_target_state_path())
		var output_variable := get_variable(output_target_path)
		if output_variable == null and invalid_reason.is_empty():
			invalid_reason = "unknown output target"
		output_snapshots.append({
			"target_state_path": output_target_path,
			"target_claim_slot_id": String(output_def.get_normalized_target_claim_slot_id()),
			"operation": int(output_def.operation),
			"value": output_def.get_target_value(output_variable.definition if output_variable != null else null),
			"active": active,
		})
	return {
		"transition_id": transition_id,
		"display_name": transition_def.get_display_name(),
		"graph_position": transition_def.graph_position,
		"active": active,
		"invalid_reason": invalid_reason,
		"conditions": condition_snapshots,
		"outputs": output_snapshots,
	}


func save_persistent_values() -> bool:
	_persistence_save_pending = false
	if not _persistence_dirty:
		return true
	if _legacy_migration_retry_required:
		var retry_result := LegacyPersistentStateMigrationV1.migrate_if_needed(
			_SAVE_PATH,
			_variables_by_path
		)
		_log_persistence_warnings(retry_result.get("warnings", []))
		if not bool(retry_result.get("durable", false)):
			_try_log_state_warning(func() -> Array:
				return ["StateStore: Legacy persistence migration retry failed (%s)." % str(retry_result.get("reason", "unknown"))]
			)
			return false
		_legacy_migration_retry_required = false
	var config := ConfigFile.new()
	config.set_value(
		_PERSISTENCE_SCHEMA_SECTION,
		_PERSISTENCE_SCHEMA_KEY,
		_PERSISTENCE_SCHEMA_VERSION
	)
	for variable in _variables_by_path.values():
		var state_variable := variable as StateVariable
		var path := String(state_variable.get_path())
		if state_variable.has_base_value():
			config.set_value(
				_PERSISTENCE_BASES_SECTION,
				path,
				_serialize_value(
					state_variable.definition,
					state_variable.get_base_value()
				)
			)
		if state_variable.has_override():
			config.set_value(
				_PERSISTENCE_OVERRIDES_SECTION,
				path,
				_serialize_value(
				state_variable.definition,
				state_variable.get_override_value()
				)
			)
	var save_error := config.save(_SAVE_PATH)
	if save_error != OK:
		_try_log_state_warning(func() -> Array:
			return ["StateStore: Failed to save state variables config to '%s' (error %d)." % [_SAVE_PATH, save_error]]
		)
		return false
	_persistence_dirty = false
	return true


func _schedule_persistent_save() -> void:
	_persistence_dirty = true
	if _persistence_save_pending:
		return
	_persistence_save_pending = true
	var tree := get_tree()
	if tree == null:
		call_deferred("_flush_scheduled_persistent_save")
		return
	var timer := tree.create_timer(_PERSISTENCE_SAVE_DEBOUNCE_SEC)
	timer.timeout.connect(_flush_scheduled_persistent_save, CONNECT_ONE_SHOT)


func _flush_scheduled_persistent_save() -> void:
	if not _persistence_save_pending:
		return
	save_persistent_values()


func _load_database() -> void:
	var authored := StateVariableDatabase.load_default_database()
	if authored == null:
		_try_log_state_warning(func() -> Array:
			return ["StateStore: Failed to load database at %s" % _DATABASE_PATH]
		)
		return
	authored.ensure_valid_configuration()
	database = _compose_runtime_database(authored)


## Builds the database the global runtime actually runs on: the hand-authored entries
## plus the baked code-declared ones (PGO-225).
##
## The composition is a separate instance on purpose. `load()` hands out the cached
## resource, and the state-graph editor holds that same instance and saves it, so
## appending generated definitions to it would end up writing them into the authored
## `.tres` — restoring exactly the default-value duplication this goal removes.
## [method StateVariableDatabase.mark_runtime_composite] makes that mistake impossible
## rather than merely avoided here.
##
## Reading the bake is one script load. Nothing walks `res://data`, introspects a
## property or touches [ResourceCatalog] on this path, which is what keeps a shipped,
## manifest-authoritative build correct.
func _compose_runtime_database(authored: StateVariableDatabase) -> StateVariableDatabase:
	var generated := StateVariableGenerator.build_baked_definitions()
	if generated.is_empty():
		_generated_paths = {}
		return authored

	var merge := StateVariableGenerator.merge_definitions(authored.get_state_definitions(), generated)
	_generated_paths = merge.get("generated_paths", {}) as Dictionary
	var rejected := merge.get("rejected", []) as Array
	if not rejected.is_empty():
		var rejected_paths := PackedStringArray()
		for rejection in rejected:
			rejected_paths.append(str((rejection as Dictionary).get("path", "")))
		_try_log_state_warning(func() -> Array:
			return [
				"StateStore: %d code-declared state variable(s) collide with hand-authored entries and were dropped in favour of the authored ones: %s. Remove the authored entry to adopt the code-declared default." % [
					rejected_paths.size(), str(rejected_paths),
				]
			]
		)

	var composed := StateVariableDatabase.new()
	composed.mark_runtime_composite(_DATABASE_PATH)
	var definitions: Array[StateVariableDef] = []
	definitions.assign(merge.get("definitions", []) as Array)
	composed.states = definitions
	composed.entries = definitions
	composed.transitions = authored.transitions
	composed.ensure_valid_configuration()
	return composed


## Whether [param path] resolves to a code-declared variable — one generated from a
## resource property rather than authored in the database.
func is_code_declared(path: String) -> bool:
	return _generated_paths.has(StringName(path.strip_edges().to_lower()))


func _adopt_global_runtime() -> void:
	global_runtime.suppress_value_log_path(_STATE_CHANGE_PROBE_PATH)
	_variables_by_path = global_runtime.get_variable_map()
	_transition_defs_by_id = global_runtime.get_transition_definitions_by_id()
	_transition_active_by_id = global_runtime.get_transition_active_map()
	_transition_ids_by_condition_path = global_runtime.get_transition_dependency_index()
	_transition_evaluation_count = global_runtime.transition_evaluation_count
	if not global_runtime.batch_committed.is_connected(_on_global_runtime_batch_committed):
		global_runtime.batch_committed.connect(_on_global_runtime_batch_committed)
	if not global_runtime.variable_instance_replaced.is_connected(_on_global_runtime_variable_instance_replaced):
		global_runtime.variable_instance_replaced.connect(_on_global_runtime_variable_instance_replaced)
	for variable_variant in _variables_by_path.values():
		var variable := variable_variant as StateVariable
		if variable == null:
			continue
		_connect_global_variable_observers(variable)


func _on_global_runtime_variable_instance_replaced(
	variable_path: StringName,
	previous_variable: StateVariable,
	replacement_variable: StateVariable
) -> void:
	_disconnect_global_variable_observers(previous_variable)
	_connect_global_variable_observers(replacement_variable)
	variable_instance_replaced.emit(variable_path, previous_variable, replacement_variable)


func _connect_global_variable_observers(variable: StateVariable) -> void:
	if variable == null:
		return
	if not variable.claims_changed.is_connected(_on_variable_claims_changed):
		variable.claims_changed.connect(_on_variable_claims_changed)
	if not variable.default_value_changed.is_connected(_on_variable_default_value_changed):
		variable.default_value_changed.connect(_on_variable_default_value_changed)
	if not variable.base_value_changed.is_connected(_on_variable_base_value_changed):
		variable.base_value_changed.connect(_on_variable_base_value_changed)
	if not variable.override_changed.is_connected(_on_variable_override_changed):
		variable.override_changed.connect(_on_variable_override_changed)
	if (
		variable.has_signal("console_display_changed")
		and not variable.console_display_changed.is_connected(_on_variable_console_display_changed)
	):
		variable.console_display_changed.connect(_on_variable_console_display_changed)
	_claim_snapshot_state_by_path[String(variable.get_path())] = _claim_snapshot_state(variable)


func _disconnect_global_variable_observers(variable: StateVariable) -> void:
	if variable == null:
		return
	if variable.claims_changed.is_connected(_on_variable_claims_changed):
		variable.claims_changed.disconnect(_on_variable_claims_changed)
	if variable.default_value_changed.is_connected(_on_variable_default_value_changed):
		variable.default_value_changed.disconnect(_on_variable_default_value_changed)
	if variable.base_value_changed.is_connected(_on_variable_base_value_changed):
		variable.base_value_changed.disconnect(_on_variable_base_value_changed)
	if variable.override_changed.is_connected(_on_variable_override_changed):
		variable.override_changed.disconnect(_on_variable_override_changed)
	if variable.has_signal("console_display_changed") and variable.console_display_changed.is_connected(_on_variable_console_display_changed):
		variable.console_display_changed.disconnect(_on_variable_console_display_changed)


func _on_global_runtime_batch_committed(
	changed_paths: PackedStringArray,
	membership_changed_paths: PackedStringArray,
	override_membership_changed_paths: PackedStringArray,
	changed_transition_ids: PackedInt32Array
) -> void:
	_transition_evaluation_count = global_runtime.transition_evaluation_count
	for transition_id in changed_transition_ids:
		_batch_changed_transition_ids[int(transition_id)] = true
	if not changed_paths.is_empty():
		batch_committed.emit(changed_paths)
	# Claim-snapshot and layered-topology refreshes each register/remove console commands
	# for the same batch of changed variables. Wrapping them in one outer batch defers
	# Logot's default-child validation until every refresh has landed, so a variable whose
	# override just switched on (default child now "override/remove") doesn't get validated
	# against a catalog snapshot from mid-way through the refresh, before "override/remove"
	# itself was registered.
	if Console != null:
		Console.batch_ui_updates(func():
			_flush_claim_snapshot_changes()
			_emit_state_graph_delta(changed_paths)
			_flush_targeted_console_changes(
				changed_paths,
				Array(membership_changed_paths),
				Array(override_membership_changed_paths)
			)
		)
	else:
		_flush_claim_snapshot_changes()
		_emit_state_graph_delta(changed_paths)
		_flush_targeted_console_changes(
			changed_paths,
			Array(membership_changed_paths),
			Array(override_membership_changed_paths)
		)
	_batch_changed_transition_ids.clear()


func _on_state_machine_runtime_registered(
	scope_key: StringName,
	runtime: StateMachineRuntime
) -> void:
	if runtime != null:
		var callback := _on_local_runtime_batch_committed.bind(runtime)
		if not runtime.batch_committed.is_connected(callback):
			runtime.batch_committed.connect(callback)
	var event := {
		"action": "registered",
		"scope_key": String(scope_key),
		"scope_registry": get_state_graph_scope_registry(),
	}
	state_graph_scope_registry_changed.emit(event)
	if _should_broadcast_state_graph_snapshot():
		EngineDebugger.send_message("state_graph:scope_registry", [event])


func _on_state_machine_runtime_unregistered(scope_key: StringName) -> void:
	if _state_graph_selected_scope_key == scope_key:
		_state_graph_selected_scope_key = StateMachineScopeAddress.GLOBAL_KEY
	var event := {
		"action": "unregistered",
		"scope_key": String(scope_key),
		"selected_scope_key": String(_state_graph_selected_scope_key),
		"scope_registry": get_state_graph_scope_registry(),
	}
	state_graph_scope_registry_changed.emit(event)
	if _should_broadcast_state_graph_snapshot():
		EngineDebugger.send_message("state_graph:scope_registry", [event])


func _on_local_runtime_batch_committed(
	changed_paths: PackedStringArray,
	_membership_changed_paths: PackedStringArray,
	_override_membership_changed_paths: PackedStringArray,
	_changed_transition_ids: PackedInt32Array,
	runtime: StateMachineRuntime
) -> void:
	if (
		runtime == null
		or runtime.is_torn_down()
		or runtime.get_scope_key() != _state_graph_selected_scope_key
		or not _has_state_graph_delta_consumers()
	):
		return
	var full_snapshot := runtime.get_state_graph_snapshot()
	var changed_lookup: Dictionary = {}
	for path in changed_paths:
		changed_lookup[String(path)] = true
	var states: Array[Dictionary] = []
	for state_variant in full_snapshot.get("states", []):
		var state := state_variant as Dictionary
		if changed_lookup.has(String(state.get("path", ""))):
			states.append(state)
	var delta := {
		"schema_version": _STATE_GRAPH_SCHEMA_VERSION,
		"topology_version": _state_graph_topology_version,
		"scope_key": String(runtime.get_scope_key()),
		"template_key": String(runtime.scope_address.template_key) if runtime.scope_address != null else "",
		"instance_key": String(runtime.scope_address.instance_key) if runtime.scope_address != null else "",
		"states": states,
		"transitions": full_snapshot.get("transitions", []),
	}
	_state_graph_delta_emit_count += 1
	state_graph_delta_ready.emit(delta)
	if _should_broadcast_state_graph_snapshot():
		EngineDebugger.send_message("state_graph:delta", [delta])


func _load_persistent_values() -> void:
	_loading_persistent_values = true
	var migration_result := LegacyPersistentStateMigrationV1.migrate_if_needed(
		_SAVE_PATH,
		_variables_by_path
	)
	_log_persistence_warnings(migration_result.get("warnings", []))
	if not bool(migration_result.get("durable", false)):
		_apply_persistent_layers(
			migration_result.get("bases", {}),
			migration_result.get("overrides", {})
		)
		_legacy_migration_retry_required = true
		_loading_persistent_values = false
		return
	_legacy_migration_retry_required = false
	var config := ConfigFile.new()
	var load_error := config.load(_SAVE_PATH)
	if load_error != OK:
		_loading_persistent_values = false
		return
	if int(config.get_value(_PERSISTENCE_SCHEMA_SECTION, _PERSISTENCE_SCHEMA_KEY, 0)) != _PERSISTENCE_SCHEMA_VERSION:
		_try_log_state_warning(func() -> Array:
			return ["StateStore: Unsupported state persistence schema in '%s'." % _SAVE_PATH]
		)
		_loading_persistent_values = false
		return
	_load_modern_layer_from_config(config, _PERSISTENCE_BASES_SECTION, ValueLayer.BASE)
	_load_modern_layer_from_config(config, _PERSISTENCE_OVERRIDES_SECTION, ValueLayer.OVERRIDE)
	_loading_persistent_values = false
	_persistence_dirty = false


func _load_modern_layer_from_config(
	config: ConfigFile,
	section: String,
	layer: ValueLayer
) -> void:
	if not config.has_section(section):
		return
	var applied_paths: Dictionary = {}
	for raw_path in _ordered_section_keys(config, section):
		var stored_path := String(raw_path).strip_edges().to_lower()
		var path := StatePathAliases.resolve(stored_path)
		if applied_paths.has(path):
			# A live successor key already supplied this path; the retired alias
			# is stale and gets dropped when the file is next written.
			continue
		var variable := get_variable(path)
		if variable == null:
			_try_log_state_warning(func() -> Array:
				return ["StateStore: Unknown state path '%s' in [%s]; skipped." % [stored_path, section]]
			)
			continue
		var decoded := _try_deserialize_value(
			variable.definition,
			config.get_value(section, raw_path, null)
		)
		if not bool(decoded.get("ok", false)):
			_try_log_state_warning(func() -> Array:
				return ["StateStore: Invalid value for '%s' in [%s]; skipped." % [stored_path, section]]
			)
			continue
		applied_paths[path] = true
		set_layer_value(path, decoded.get("value"), layer)


## Orders a section's keys so live paths are read before retired aliases.
##
## A save file written across a rename can hold both names; the current one must
## win regardless of the order ConfigFile happens to return them in.
func _ordered_section_keys(config: ConfigFile, section: String) -> Array[String]:
	var direct_paths: Array[String] = []
	var aliased_paths: Array[String] = []
	for raw_path in config.get_section_keys(section):
		var stored_path := String(raw_path)
		if StatePathAliases.is_alias(stored_path):
			aliased_paths.append(stored_path)
		else:
			direct_paths.append(stored_path)
	direct_paths.sort()
	aliased_paths.sort()
	return direct_paths + aliased_paths


func _apply_persistent_layers(bases: Dictionary, overrides: Dictionary) -> void:
	for path_variant in bases.keys():
		var base_path := String(path_variant)
		if get_variable(base_path) != null:
			set_layer_value(base_path, bases[path_variant], ValueLayer.BASE)
	for path_variant in overrides.keys():
		var override_path := String(path_variant)
		if get_variable(override_path) != null:
			set_layer_value(override_path, overrides[path_variant], ValueLayer.OVERRIDE)


func _log_persistence_warnings(warnings: Variant) -> void:
	if not (warnings is Array):
		return
	for warning_variant in warnings:
		var warning := String(warning_variant)
		_try_log_state_warning(func() -> Array:
			return ["StateStore: %s" % warning]
		)


func _register_console_commands() -> void:
	if Console == null:
		return
	Console.batch_ui_updates(func():
		for variable in _variables_by_path.values():
			var state_variable := variable as StateVariable
			if state_variable == null or state_variable.definition.console_hidden:
				continue
			_register_layered_console_variable(state_variable)
		for folder_path in _get_console_folder_display_paths():
			var notifier := _get_console_notifier(folder_path)
			_register_console_display_variable(
				folder_path,
				Callable(self, "_get_folder_counter_display_text_for_console").bind(folder_path),
				Callable(),
				Callable(self, "_get_folder_counter_items_for_console").bind(folder_path),
				false,
				_CONSOLE_GROUP_NAME,
				_CONSOLE_GROUP_PRIORITY,
				notifier,
				&"changed"
			)
		_refresh_layered_console_topology()
		_refresh_layered_folder_commands()
		_register_state_variable_bake_command()
	)


## Editor/debug-only regeneration entry point for the code-declared bake (PGO-225).
##
## Registered inside the caller's batch like everything else here, so it costs one more
## command and no extra catalog validation pass. Gated on an editable project because
## baking writes a `res://` script, which only exists before export.
func _register_state_variable_bake_command() -> void:
	if not OS.has_feature("editor"):
		return
	_register_console_command(
		"state/bake_declared_variables",
		Callable(self, "_bake_declared_variables_for_console"),
		"Regenerates the baked code-declared state variables from the resource properties that declare them.",
		_CONSOLE_GROUP_NAME,
		_CONSOLE_GROUP_PRIORITY
	)


func _bake_declared_variables_for_console() -> void:
	var result := StateVariableBaker.bake()
	if not bool(result.get("ok", false)):
		Console.print_error("State-variable bake failed: %s" % str(result.get("errors", [])))
		return
	if bool(result.get("changed", false)):
		Console.print_line("Baked %d code-declared state variable(s) into %s. Restart to load them." % [
			int(result.get("count", 0)), str(result.get("path", "")),
		])
	else:
		Console.print_line("Code-declared state variables are already up to date (%d)." % int(result.get("count", 0)))


func _register_layered_console_variable(variable: StateVariable) -> void:
	var variable_path := String(variable.get_path())
	var root_path := _get_console_variable_path(variable_path)
	# Register every possible default child before the root. Logot validates dynamic
	# defaults on catalog changes, so this keeps startup validation both valid and
	# linear in the number of commands.
	# The default/base/override sections are always registered so they stay visible
	# even for variables whose root command opts out of console exposure.
	_register_layered_console_layer(variable, "default", ValueLayer.DEFAULT, _CONSOLE_DEFAULT_COLOR, _CONSOLE_DEFAULT_GROUP_PRIORITY)
	_register_layered_console_layer(variable, "base", ValueLayer.BASE, _CONSOLE_BASE_COLOR, _CONSOLE_BASE_GROUP_PRIORITY)
	_register_layered_console_layer(variable, "override", ValueLayer.OVERRIDE, _CONSOLE_FOLDER_OVERRIDE_COLOR, _CONSOLE_OVERRIDE_GROUP_PRIORITY)
	if not variable.definition.console_exposed:
		return
	Console.add_command(
		root_path,
		Callable(self, "_execute_layered_root_for_console").bind(variable_path),
		[],
		0,
		variable.definition.description,
		_CONSOLE_GROUP_NAME,
		_CONSOLE_GROUP_PRIORITY,
		"",
		0,
		"",
		null,
		Color.TRANSPARENT,
		Color.TRANSPARENT,
		"",
		Callable(self, "_get_layered_root_default_child").bind(variable_path)
	)
	_registered_console_commands.append(root_path)
	_register_console_display_variable(
		root_path,
		Callable(self, "_get_variable_effective_value_for_console").bind(variable_path),
		Callable(self, "_get_variable_inline_color_for_console").bind(variable_path),
		Callable(),
		true,
		_CONSOLE_GROUP_NAME,
		_CONSOLE_GROUP_PRIORITY,
		variable,
		&"console_display_changed"
	)


func _register_layered_console_layer(variable: StateVariable, layer_name: String, layer: ValueLayer, color: Color, priority: int) -> void:
	var variable_path := String(variable.get_path())
	var root_path := _get_console_variable_path(variable_path)
	var layer_path := "%s/%s" % [root_path, layer_name]
	if _get_layered_discrete_options(variable).is_empty():
		# Continuous value types accept a typed value directly at the layer path. Supplying a
		# value_getter with no discrete options is what makes Logot render its live
		# "set to [...]" input row here, validating the text against the variable's type as
		# it is typed, instead of hiding the input behind a "set" child command.
		Console.add_command_with_options(
			layer_path,
			Callable(self, "_set_layer_from_console_text").bind(variable_path, layer),
			["value"],
			1,
			"Sets a valid %s value for the %s layer." % [variable.definition.get_value_type_name(), layer_name],
			Callable(),
			Callable(self, "_get_layer_input_probe_value_for_console").bind(variable_path, layer),
			layer_name,
			priority,
			"",
			0,
			color,
			Color.TRANSPARENT
		)
	else:
		Console.add_command(layer_path, Callable(self, "_layered_console_noop"), [], 0, "Edits the %s layer." % layer_name, layer_name, priority, "", 0, "", null, color, Color.TRANSPARENT)
	_registered_console_commands.append(layer_path)
	_register_console_display_variable(layer_path, Callable(self, "_get_layer_value_for_console").bind(variable_path, layer), Callable(self, "_get_layer_color_for_console").bind(variable_path, layer), Callable(), false, layer_name, priority, variable, &"console_display_changed")
	var current_path := "%s/set_to_current" % layer_path
	_register_console_command(current_path, Callable(self, "_set_layer_to_current_for_console").bind(variable_path, layer), "Sets this %s layer to the resolved value." % layer_name, _CONSOLE_SET_GROUP_NAME, -10)
	Console.set_command_path_disabled(current_path, _layer_matches_resolved_value(variable, layer))
	_register_console_display_variable(
		current_path,
		Callable(self, "_get_variable_effective_value_for_console").bind(variable_path),
		Callable(self, "_get_variable_inline_color_for_console").bind(variable_path),
		Callable(),
		false,
		_CONSOLE_SET_GROUP_NAME,
		-10,
		variable,
		&"console_display_changed"
	)
	_register_layered_console_setter(variable, layer_name, layer, color, priority)


func _register_layered_console_setter(variable: StateVariable, layer_name: String, layer: ValueLayer, color: Color, priority: int) -> void:
	var variable_path := String(variable.get_path())
	var layer_path := "%s/%s" % [_get_console_variable_path(variable_path), layer_name]
	if variable.definition.value_type == StateVariableDef.ValueType.ENUM_TOGGLE:
		_register_layered_enum_toggle_setter(variable, layer_path, layer, layer_name)
		return
	var options := _get_layered_discrete_options(variable)
	if options.is_empty():
		# Continuous types are set through the layer command's own live text input row.
		return
	# Discrete option values sit directly in the "set" group at the layer level,
	# rather than behind an extra "set" submenu, so choosing a value is one click.
	for option_variant in options:
		var option_key := _get_layered_option_key(variable, option_variant)
		if option_key.is_empty():
			continue
		_register_console_command("%s/%s" % [layer_path, option_key], Callable(self, "_set_layer_value_for_console").bind(variable_path, option_variant, layer), "Sets the %s layer." % layer_name, _CONSOLE_SET_GROUP_NAME, _CONSOLE_SET_GROUP_PRIORITY)


## An enum mask is a SET: every option enters and leaves the layer's value
## independently. Registering the options as whole-value commands (PTK-630)
## made choosing one REPLACE the set, so only ever a single option could be
## enabled. Each option is a boolean set/get against this layer's own value
## instead, which is what lets a toggle genuinely remove an entry.
func _register_layered_enum_toggle_setter(variable: StateVariable, layer_path: String, layer: ValueLayer, layer_name: String) -> void:
	var variable_path := String(variable.get_path())
	_register_console_command(
		"%s/%s" % [layer_path, _get_layered_option_key(variable, [])],
		Callable(self, "_set_layer_value_for_console").bind(variable_path, [], layer),
		"Clears every option from the %s layer." % layer_name,
		_CONSOLE_SET_GROUP_NAME,
		_CONSOLE_SET_GROUP_PRIORITY
	)
	for option_variant in variable.definition.possible_values:
		var option_key := _get_layered_option_key(variable, [option_variant])
		if option_key.is_empty():
			continue
		_register_console_setget_command(
			"%s/%s" % [layer_path, option_key],
			Callable(self, "_set_layer_enum_toggle_option_for_console").bind(variable_path, option_key, layer),
			Callable(self, "_get_layer_enum_toggle_option_for_console").bind(variable_path, option_key, layer),
			"Adds or removes '%s' on the %s layer." % [option_key, layer_name],
			Callable(),
			Callable(),
			Callable(),
			_CONSOLE_SET_GROUP_NAME,
			_CONSOLE_SET_GROUP_PRIORITY,
			"",
			0,
			variable,
			&"console_display_changed"
		)


func _set_layer_enum_toggle_option_for_console(enabled: bool, path: String, option_key: String, layer: ValueLayer) -> void:
	set_enum_toggle_option_enabled(path, option_key, enabled, layer)


func _get_layer_enum_toggle_option_for_console(path: String, option_key: String, layer: ValueLayer) -> bool:
	var variable := get_variable(path)
	if variable == null or variable.definition.value_type != StateVariableDef.ValueType.ENUM_TOGGLE:
		return false
	return variable.definition.enum_toggle_has_option(_get_layer_value(variable, layer), option_key)


func _get_layered_discrete_options(variable: StateVariable) -> Array:
	match variable.definition.value_type:
		StateVariableDef.ValueType.BOOL, StateVariableDef.ValueType.ENUM:
			return variable.get_options() as Array
		StateVariableDef.ValueType.ENUM_TOGGLE:
			var values: Array = [[]]
			for option_variant in variable.definition.possible_values:
				values.append([option_variant])
			return values
		_:
			return []


func _get_layered_option_key(variable: StateVariable, value: Variant) -> String:
	if variable.definition.value_type == StateVariableDef.ValueType.ENUM_TOGGLE:
		var entries := variable.definition.enum_toggle_values(value)
		return "none" if entries.is_empty() else "_".join(entries)
	return str(value).strip_edges().to_lower().replace("/", "_").replace(" ", "_")


func _layered_console_noop() -> void:
	pass


func _set_layer_value_for_console(path: String, value: Variant, layer: ValueLayer) -> void:
	set_layer_value(path, value, layer)
	_after_console_layer_write(path, layer)


func _set_layer_from_console_text(value: String, path: String, layer: ValueLayer) -> void:
	set_layer_value(path, value, layer)
	_after_console_layer_write(path, layer)


func _set_layer_to_current_for_console(path: String, layer: ValueLayer) -> void:
	var variable := get_variable(path)
	if variable != null:
		set_layer_value(path, variable.resolved_value, layer)
		_after_console_layer_write(path, layer)


## A console base/default write is an explicit user choice. It must not report
## success while the one-shot startup seed claim still shadows that choice.
func _after_console_layer_write(_path: String, _layer: ValueLayer) -> void:
	pass


func _get_layer_value_for_console(path: String, layer: ValueLayer) -> Variant:
	var variable := get_variable(path)
	if variable == null:
		return ""
	match layer:
		ValueLayer.DEFAULT:
			return variable.get_default_value()
		ValueLayer.BASE:
			return variable.get_base_value() if variable.has_base_value() else ""
		ValueLayer.OVERRIDE:
			return variable.get_override_value() if variable.has_override() else ""
	return ""


## Reports a value whose type always matches the variable's declared value type, so Logot can label
## and validate the layer's typed input. Empty layers fall back to the resolved value because the
## display getter reports "" for them, which would otherwise be probed as a string.
func _get_layer_input_probe_value_for_console(path: String, layer: ValueLayer) -> Variant:
	var variable := get_variable(path)
	if variable == null:
		return ""
	var probe_value: Variant = variable.resolved_value
	match layer:
		ValueLayer.DEFAULT:
			probe_value = variable.get_default_value()
		ValueLayer.BASE:
			if variable.has_base_value():
				probe_value = variable.get_base_value()
		ValueLayer.OVERRIDE:
			if variable.has_override():
				probe_value = variable.get_override_value()
	return variable.definition.coerce_value(probe_value)


func _get_layer_color_for_console(path: String, layer: ValueLayer) -> Variant:
	var variable := get_variable(path)
	if variable == null:
		return null
	match layer:
		ValueLayer.DEFAULT:
			return _CONSOLE_DEFAULT_COLOR
		ValueLayer.BASE:
			return _CONSOLE_BASE_COLOR if variable.has_base_value() else _CONSOLE_DEFAULT_COLOR
		ValueLayer.OVERRIDE:
			return _CONSOLE_FOLDER_OVERRIDE_COLOR if variable.has_override() else _CONSOLE_DEFAULT_COLOR
	return null


func _layer_matches_resolved_value(variable: StateVariable, layer: ValueLayer) -> bool:
	match layer:
		ValueLayer.BASE:
			if not variable.has_base_value():
				return false
		ValueLayer.OVERRIDE:
			if not variable.has_override():
				return false
	var layer_value: Variant = _get_layer_value_for_console(String(variable.get_path()), layer)
	return variable.definition.values_equal(layer_value, variable.resolved_value)


func _get_layered_root_default_child(path: String) -> String:
	var variable := get_variable(path)
	if variable == null:
		return ""
	if variable.has_override():
		return "override/remove"
	var options := _get_layered_discrete_options(variable)
	if options.is_empty():
		return "override"
	var current_key := _get_layered_option_key(variable, variable.resolved_value)
	var start_index := -1
	for option_index in range(options.size()):
		if _get_layered_option_key(variable, options[option_index]) == current_key:
			start_index = option_index
			break
	var next_index := (start_index + 1) % options.size()
	var next_key := _get_layered_option_key(variable, options[next_index])
	return "override/%s" % next_key


func _execute_layered_root_for_console(path: String) -> void:
	var child_path := _get_layered_root_default_child(path)
	if child_path.is_empty():
		return
	Console.execute_console_command("/%s/%s" % [_get_console_variable_path(path), child_path])


func _refresh_layered_console_topology() -> void:
	if Console == null:
		return
	Console.batch_ui_updates(func():
		for variable_variant in _variables_by_path.values():
			var variable := variable_variant as StateVariable
			if variable != null and not variable.definition.console_hidden:
				_refresh_layered_variable_topology(String(variable.get_path()))
		_refresh_layered_folder_commands()
	)


func _refresh_layered_variable_topology(path: String) -> void:
	var variable := get_variable(path)
	if variable == null:
		return
	var root_path := _get_console_variable_path(path)
	var desired: Dictionary = {}
	if variable.has_base_value():
		desired["%s/base/remove" % root_path] = Callable(self, "clear_base").bind(path)
	if variable.has_override():
		desired["%s/override/remove" % root_path] = Callable(self, "clear_override").bind(path)
	var registered := _registered_layered_dynamic_commands.get(path, {}) as Dictionary
	for command_path_variant in registered.keys():
		var command_path := String(command_path_variant)
		if not desired.has(command_path):
			Console.remove_command(command_path)
	for command_path_variant in desired.keys():
		var command_path := String(command_path_variant)
		if not registered.has(command_path):
			_register_console_command(command_path, desired[command_path], "Removes this local layer value.", "remove", -20)
	_registered_layered_dynamic_commands[path] = desired
	for layer in [ValueLayer.DEFAULT, ValueLayer.BASE, ValueLayer.OVERRIDE]:
		Console.set_command_path_disabled(
			"%s/%s/set_to_current" % [root_path, _get_layered_layer_name(layer)],
			_layer_matches_resolved_value(variable, layer)
		)
	_refresh_layered_claim_commands(path)


func _get_layered_layer_name(layer: ValueLayer) -> String:
	match layer:
		ValueLayer.DEFAULT:
			return "default"
		ValueLayer.BASE:
			return "base"
		ValueLayer.OVERRIDE:
			return "override"
	return ""


func _refresh_layered_claim_commands(path: String) -> void:
	var variable := get_variable(path)
	if variable == null:
		return
	var root_path := _get_console_variable_path(path)
	var claims_path := "%s/claims" % root_path
	var desired: Dictionary = {}
	var desired_displays: Dictionary = {}
	var snapshots := get_claim_snapshots(path)
	var active_claim_count := 0
	var muted_claim_count := 0
	for snapshot_variant in snapshots:
		var snapshot := snapshot_variant as Dictionary
		if not bool(snapshot.get("active", false)) and int(snapshot.get("transition_id", 0)) == 0:
			continue
		if bool(snapshot.get("active", false)):
			active_claim_count += 1
		if bool(snapshot.get("muted", false)):
			muted_claim_count += 1
		var stable_key := _get_claim_console_key(snapshot)
		var claim_key := stable_key.to_lower().replace("/", "_").replace(" ", "_")
		var claim_path := "%s/%s" % [claims_path, claim_key]
		desired[claim_path] = Callable(self, "_layered_console_noop")
		desired_displays[claim_path] = stable_key
		var muted := bool(snapshot.get("muted", false))
		var code_key := str(snapshot.get("code_key", ""))
		if code_key.is_empty():
			continue
		var action_name := "unmute" if muted else "temporarily_mute"
		var method_name := "unmute_claim" if muted else "mute_claim"
		desired["%s/%s" % [claim_path, action_name]] = Callable(self, method_name).bind(path, StringName(code_key))
	if active_claim_count > 0 and muted_claim_count < active_claim_count:
		desired["%s/mute_all" % claims_path] = Callable(self, "mute_all_claims").bind(path)
	if muted_claim_count > 0:
		desired["%s/unmute_all" % claims_path] = Callable(self, "unmute_all_claims").bind(path)
	var registered := _registered_layered_claim_commands.get(path, {}) as Dictionary
	var registered_displays := _registered_layered_claim_display_variables.get(path, {}) as Dictionary
	if desired.is_empty() and Console.get_console_commands().has(claims_path):
		Console.remove_command(claims_path)
	elif not desired.is_empty() and not Console.get_console_commands().has(claims_path):
		Console.add_command(claims_path, Callable(self, "_layered_console_noop"), [], 0, "Shows resolver-ordered state claims.", "claims", _CONSOLE_CLAIMS_GROUP_PRIORITY, "", 0, "", null, _CONSOLE_FOLDER_CLAIM_COLOR, Color.TRANSPARENT)
		_registered_console_commands.append(claims_path)
	for command_path_variant in registered.keys():
		var command_path := String(command_path_variant)
		if not desired.has(command_path):
			Console.remove_command(command_path)
	for command_path_variant in desired.keys():
		var command_path := String(command_path_variant)
		if registered.has(command_path):
			if desired_displays.has(command_path):
				_refresh_layered_claim_command_presentation(command_path, path, String(desired_displays[command_path]))
			continue
		var action: Callable = desired[command_path] as Callable
		if command_path.ends_with("/temporarily_mute") or command_path.ends_with("/unmute"):
			_register_console_command(command_path, action, "Temporarily includes or excludes this claim from resolution.", "claims", _CONSOLE_CLAIMS_GROUP_PRIORITY)
		elif command_path.ends_with("/mute_all") or command_path.ends_with("/unmute_all"):
			_register_console_command(command_path, action, "Changes all active claims for this variable in one batch.", "claims", _CONSOLE_CLAIMS_GROUP_PRIORITY)
		else:
			var stable_key := String(desired_displays.get(command_path, "claim"))
			var snapshot := _get_claim_snapshot_for_console(path, stable_key)
			var icon: Texture2D = _get_muted_claim_icon() if bool(snapshot.get("muted", false)) else null
			Console.add_command(command_path, action, [], 0, "Resolver claim.", "claims", _CONSOLE_CLAIMS_GROUP_PRIORITY, "", 0, stable_key, icon, _CONSOLE_FOLDER_CLAIM_COLOR, Color.TRANSPARENT)
			_registered_console_commands.append(command_path)
	for display_path_variant in registered_displays.keys():
		var display_path := String(display_path_variant)
		if not desired_displays.has(display_path):
			Console.remove_display_variable(display_path)
	for display_path_variant in desired_displays.keys():
		var display_path := String(display_path_variant)
		if registered_displays.has(display_path):
			continue
		var stable_key := String(desired_displays[display_path])
		Console.add_display_variable(
			display_path,
			Callable(self, "_get_claim_value_for_console").bind(path, stable_key),
			Callable(self, "_get_claim_color_for_console").bind(path, stable_key),
			Callable(),
			false,
			"claims",
			_CONSOLE_CLAIMS_GROUP_PRIORITY,
			variable,
			&"console_display_changed"
		)
	_registered_layered_claim_commands[path] = desired
	_registered_layered_claim_display_variables[path] = desired_displays


func _get_claim_console_key(snapshot: Dictionary) -> String:
	var code_key := str(snapshot.get("code_key", ""))
	return code_key if not code_key.is_empty() else str(snapshot.get("slot_id", "claim"))


func _get_claim_snapshot_for_console(path: String, stable_key: String) -> Dictionary:
	for snapshot in get_claim_snapshots(path):
		if _get_claim_console_key(snapshot) == stable_key:
			return snapshot
	return {}


func _get_claim_value_for_console(path: String, stable_key: String) -> Variant:
	return _get_claim_snapshot_for_console(path, stable_key).get("value")


func _get_claim_color_for_console(path: String, stable_key: String) -> Variant:
	var snapshot := _get_claim_snapshot_for_console(path, stable_key)
	if bool(snapshot.get("muted", false)):
		return _CONSOLE_DEFAULT_COLOR
	return _CONSOLE_FOLDER_CLAIM_COLOR if bool(snapshot.get("active", false)) else Color("64748b")


func _refresh_layered_claim_command_presentation(command_path: String, path: String, stable_key: String) -> void:
	var command = Console.get_console_commands().get(command_path)
	if command == null:
		return
	var snapshot := _get_claim_snapshot_for_console(path, stable_key)
	var icon: Texture2D = _get_muted_claim_icon() if bool(snapshot.get("muted", false)) else null
	if command.icon == icon:
		return
	command.icon = icon
	Console.notify_display_variable_changed(command_path)


func _get_muted_claim_icon() -> Texture2D:
	if _muted_claim_icon != null:
		return _muted_claim_icon
	_muted_claim_icon = _MUTED_CLAIM_ICON
	return _muted_claim_icon


func _refresh_layered_folder_commands() -> void:
	# Bulk actions live directly under the folder as an untitled, tint-boxed
	# subgroup instead of a named "bulk" path, so they read as part of the
	# state group rather than a separate menu.
	var desired: Dictionary = {}
	for folder_path in _get_console_folder_display_paths():
		var counts := _get_folder_counter_counts(folder_path)
		if int(counts.get("stored_base", 0)) > 0:
			desired["%s/remove_all_base" % folder_path] = [folder_path, ValueLayer.BASE]
		if int(counts.get("overridden", 0)) > 0:
			desired["%s/remove_all_overrides" % folder_path] = [folder_path, ValueLayer.OVERRIDE]
	for command_path_variant in _registered_layered_folder_commands.keys():
		var command_path := String(command_path_variant)
		if not desired.has(command_path):
			Console.remove_command(command_path)
			Console.remove_display_variable(command_path)
	for command_path_variant in desired.keys():
		var command_path := String(command_path_variant)
		if _registered_layered_folder_commands.has(command_path):
			continue
		var entry: Array = desired[command_path]
		var folder_path: String = entry[0]
		var layer: ValueLayer = entry[1]
		Console.add_command(command_path, Callable(self, "_clear_folder_layer_for_console").bind(folder_path, layer), [], 0, "Bulk state-layer action.", "", -20, "", 0, "", null, _CONSOLE_BASE_COLOR, Color.TRANSPARENT)
		_registered_console_commands.append(command_path)
		Console.add_display_variable(command_path, Callable(self, "_get_folder_bulk_remove_count_for_console").bind(folder_path, layer), Callable(), Callable(), false, "", -20, _get_console_notifier(folder_path), &"changed")
	_registered_layered_folder_commands = desired


func _get_folder_bulk_remove_count_for_console(folder_path: String, layer: ValueLayer) -> int:
	var counts := _get_folder_counter_counts(folder_path)
	match layer:
		ValueLayer.BASE:
			return int(counts.get("stored_base", 0))
		ValueLayer.OVERRIDE:
			return int(counts.get("overridden", 0))
	return 0


func _clear_folder_layer_for_console(folder_path: String, layer: ValueLayer) -> void:
	var prefix := _normalize_path(folder_path).trim_suffix("/") + "/"
	batch_changes(func():
		for variable_variant in _variables_by_path.values():
			var variable := variable_variant as StateVariable
			if variable == null or not variable.definition.console_exposed:
				continue
			var variable_path := String(variable.get_path())
			if variable_path.begins_with(prefix):
				if layer == ValueLayer.BASE:
					clear_base(variable_path)
				elif layer == ValueLayer.OVERRIDE:
					clear_override(variable_path)
	)



func _unregister_console_commands() -> void:
	if Console == null:
		return
	Console.batch_ui_updates(func():
		_clear_override_console_entries()
		for claim_display_paths_variant in _registered_layered_claim_display_variables.values():
			var claim_display_paths := claim_display_paths_variant as Dictionary
			for claim_display_path_variant in claim_display_paths.keys():
				Console.remove_display_variable(String(claim_display_path_variant))
		_registered_layered_claim_display_variables.clear()
		_registered_layered_claim_commands.clear()
		_registered_layered_dynamic_commands.clear()
		for folder_command_path_variant in _registered_layered_folder_commands.keys():
			Console.remove_display_variable(String(folder_command_path_variant))
		_registered_layered_folder_commands.clear()
		for path in _registered_console_commands:
			Console.remove_command(path)
		_registered_console_commands.clear()
		_registered_override_set_commands.clear()
		for path in _registered_console_display_variables:
			Console.remove_display_variable(path)
		_registered_console_display_variables.clear()
	)


func _register_console_command(path: String, callable: Callable, description: String, group_name: String = "", group_priority: int = 0, arguments: Array = [], required: int = 0, options_provider: Callable = Callable()) -> void:
	if options_provider.is_valid():
		Console.add_command_with_options(path, callable, arguments, required, description, options_provider, Callable(), group_name, group_priority)
	else:
		Console.add_command(path, callable, arguments, required, description, group_name, group_priority)
	_registered_console_commands.append(path)


func _register_console_setget_command(path: String, setter: Callable, getter: Callable, description: String, options_provider: Callable = Callable(), inline_color_provider: Callable = Callable(), display_getter: Callable = Callable(), group_name: String = "", group_priority: int = 0, option_group_name: String = "", option_group_priority: int = 0, change_signal_source: Object = null, change_signal_name: StringName = &"") -> void:
	Console.add_setget_command(path, setter, getter, description, options_provider, inline_color_provider, group_name, group_priority, option_group_name, option_group_priority, change_signal_source, change_signal_name)
	if display_getter.is_valid():
		Console.add_display_variable(path, display_getter, inline_color_provider, Callable(), true, group_name, group_priority, change_signal_source, change_signal_name)
	_registered_console_commands.append(path)
	_registered_console_display_variables.append(path)


func _register_console_display_variable(path: String, getter: Callable, inline_color_provider: Callable = Callable(), items_provider: Callable = Callable(), pinnable: bool = true, group_name: String = "", group_priority: int = 0, change_signal_source: Object = null, change_signal_name: StringName = &"") -> void:
	Console.add_display_variable(path, getter, inline_color_provider, items_provider, pinnable, group_name, group_priority, change_signal_source, change_signal_name)
	_registered_console_display_variables.append(path)


func _print_variable_summary(path: String) -> void:
	var variable := get_variable(path)
	if variable == null:
		Console.print_error("Unknown state variable: %s" % path)
		return
	var console_path := _get_console_variable_path(path)
	var override_text := "none"
	if variable.has_override():
		override_text = "%s (remove: /%s)" % [
			str(variable.get_override_value()),
			_get_console_remove_override_path(console_path),
		]
	Console.print_line("%s = %s | override: %s | claims: %s" % [
		console_path,
		str(variable.resolved_value),
		override_text,
		variable.describe_claims(),
	])


func _get_variable_current_value_for_console(path: String) -> Variant:
	var variable := get_variable(path)
	if variable == null:
		return null
	if variable.definition.value_type == StateVariableDef.ValueType.LIST:
		return variable.definition.list_count(variable.resolved_value)
	if variable.definition.value_type == StateVariableDef.ValueType.ENUM_TOGGLE:
		return variable.definition.enum_toggle_count(variable.resolved_value)
	return variable.resolved_value


func _set_variable_current_value_for_console(value: Variant, path: String) -> void:
	if _is_no_override_console_marker(value):
		clear_override(path)
		return
	var variable := get_variable(path)
	if variable == null:
		return
	if value == null and variable.definition.value_type == StateVariableDef.ValueType.ENUM_TOGGLE:
		toggle_enum_toggle_root(path, ValueLayer.OVERRIDE)
		return
	set_override(path, value)


func _set_variable_base_value_for_console(value: Variant, path: String) -> void:
	set_layer_value(path, value, ValueLayer.BASE)


func _get_variable_base_value_for_console(path: String) -> Variant:
	var variable := get_variable(path)
	if variable == null:
		return null
	return variable.get_effective_bottom_value()


func _set_variable_override_value_for_console(value: Variant, path: String) -> void:
	if _is_no_override_console_marker(value):
		clear_override(path)
		return
	set_override(path, value)


func _get_variable_default_value_for_console(path: String) -> Variant:
	var variable := get_variable(path)
	if variable == null:
		return null
	return variable.get_default_value()


func _get_variable_effective_value_for_console(path: String) -> Variant:
	var variable := get_variable(path)
	if variable == null:
		return null
	return variable.resolved_value


func _set_variable_default_value_for_console(value: Variant, path: String) -> void:
	set_layer_value(path, value, ValueLayer.DEFAULT)


func _get_variable_options_for_console(path: String) -> Variant:
	var variable := get_variable(path)
	if variable == null:
		return null
	if variable.definition.value_type == StateVariableDef.ValueType.ENUM_TOGGLE:
		return _get_enum_toggle_root_options_for_console(variable)
	return variable.get_options()


func _get_variable_current_options_for_console(path: String) -> Variant:
	var variable := get_variable(path)
	if variable == null:
		return null
	var options: Variant = variable.get_options()
	if not (options is Array):
		return options
	var options_with_clear: Array = []
	if variable.definition.value_type == StateVariableDef.ValueType.BOOL:
		options_with_clear = [true, false]
	elif variable.definition.value_type == StateVariableDef.ValueType.ENUM_TOGGLE:
		options_with_clear = _get_enum_toggle_root_options_for_console(variable)
	else:
		options_with_clear = (options as Array).duplicate()
	options_with_clear.append(_build_no_override_console_option())
	return options_with_clear


func _get_enum_toggle_root_options_for_console(variable: StateVariable) -> Array:
	if variable == null or variable.definition.value_type != StateVariableDef.ValueType.ENUM_TOGGLE:
		return []
	var options: Array = [[]]
	var remembered_value: Array = variable.get_last_non_empty_enum_toggle_value()
	if not remembered_value.is_empty():
		options.append(remembered_value)
	return options


func _get_enum_toggle_current_options_for_console(path: String) -> Array:
	var variable := get_variable(path)
	if variable == null:
		return []
	return _get_enum_toggle_root_options_for_console(variable)


func _get_enum_toggle_override_options_for_console(path: String) -> Array:
	var options := _get_enum_toggle_current_options_for_console(path)
	options.append(_build_no_override_console_option())
	return options


func _set_default_to_current_override_for_console(path: String) -> void:
	var variable := get_variable(path)
	if variable == null:
		return
	if not variable.has_override():
		if Console != null:
			Console.print_line("No active override for %s." % path)
		return
	var override_value: Variant = variable.get_override_value()
	set_layer_value(path, override_value, ValueLayer.DEFAULT)
	clear_override(path)


func _get_variable_current_override_value_for_console(path: String) -> Variant:
	var variable := get_variable(path)
	if variable == null:
		return null
	if variable.has_override():
		return variable.get_override_value()
	return _build_no_override_console_marker()


func _get_variable_inline_color_for_console(path: String) -> Variant:
	var variable := get_variable(path)
	if variable == null:
		return null
	if variable.has_override():
		return _CONSOLE_FOLDER_OVERRIDE_COLOR
	for snapshot in get_claim_snapshots(path):
		if bool(snapshot.get("contributes_to_resolution", false)):
			return _CONSOLE_FOLDER_CLAIM_COLOR
	if variable.has_base_value():
		return _CONSOLE_BASE_COLOR
	return _CONSOLE_DEFAULT_COLOR


func _build_no_override_console_option() -> Dictionary:
	return {
		"label": _CONSOLE_NO_OVERRIDE_LABEL,
		"value": _build_no_override_console_marker(),
	}


func _build_no_override_console_marker() -> Dictionary:
	return {_CONSOLE_NO_OVERRIDE_MARKER_KEY: true}


func _is_no_override_console_marker(value: Variant) -> bool:
	return value is Dictionary and bool((value as Dictionary).get(_CONSOLE_NO_OVERRIDE_MARKER_KEY, false))


func _get_variable_override_value_for_console(path: String) -> Variant:
	var variable := get_variable(path)
	if variable == null or not variable.has_override():
		return null
	return variable.get_override_value()


func _get_console_folder_display_paths() -> Array[String]:
	var folder_paths: Dictionary = {}
	for variable_path_variant in _variables_by_path.keys():
		var variable_path := str(variable_path_variant)
		var variable := _variables_by_path[variable_path_variant] as StateVariable
		if variable == null or not variable.definition.console_exposed:
			continue
		var segments := variable_path.split("/", false)
		if segments.size() <= 1:
			continue
		var folder_parts: PackedStringArray = PackedStringArray()
		for segment_index in range(segments.size() - 1):
			folder_parts.append(segments[segment_index])
			folder_paths["/".join(folder_parts)] = true
	var sorted_paths: Array[String] = []
	for folder_path in folder_paths.keys():
		sorted_paths.append(str(folder_path))
	sorted_paths.sort()
	return sorted_paths


func _get_folder_counter_counts(folder_path: String) -> Dictionary:
	var normalized_folder_path := _normalize_path(folder_path).trim_suffix("/")
	var folder_prefix := normalized_folder_path + "/"
	var claimed_count := 0
	var base_count := 0
	var stored_base_count := 0
	var overridden_count := 0
	for variable_variant in _variables_by_path.values():
		var state_variable := variable_variant as StateVariable
		if state_variable == null or not state_variable.definition.console_exposed:
			continue
		var variable_path := String(state_variable.get_path())
		if variable_path == normalized_folder_path or not variable_path.begins_with(folder_prefix):
			continue
		if state_variable.has_base_value():
			stored_base_count += 1
		if state_variable.has_override():
			overridden_count += 1
			continue
		var claim_contributes := false
		for snapshot in get_claim_snapshots(variable_path):
			if bool(snapshot.get("contributes_to_resolution", false)):
				claim_contributes = true
				break
		if claim_contributes:
			claimed_count += 1
		elif state_variable.has_base_value():
			base_count += 1
	return {
		"claimed": claimed_count,
		"base": base_count,
		"stored_base": stored_base_count,
		"overridden": overridden_count,
	}


func _get_folder_counter_items_for_console(folder_path: String) -> Array:
	var counts := _get_folder_counter_counts(folder_path)
	var items: Array = []
	var claimed_count := int(counts.get("claimed", 0))
	var base_count := int(counts.get("base", 0))
	var overridden_count := int(counts.get("overridden", 0))
	if base_count > 0:
		items.append({
			"text": str(base_count),
			"color": _CONSOLE_BASE_COLOR,
		})
	if claimed_count > 0:
		items.append({
			"text": str(claimed_count),
			"color": _CONSOLE_FOLDER_CLAIM_COLOR,
		})
	if overridden_count > 0:
		items.append({
			"text": str(overridden_count),
			"color": _CONSOLE_FOLDER_OVERRIDE_COLOR,
		})
	return items


func _get_folder_counter_display_text_for_console(folder_path: String) -> String:
	var items := _get_folder_counter_items_for_console(folder_path)
	var parts: PackedStringArray = PackedStringArray()
	for item_variant in items:
		if item_variant is Dictionary:
			parts.append(str((item_variant as Dictionary).get("text", "")))
	return " ".join(parts)


func _clear_override_for_console(path: String) -> void:
	if not clear_override(path):
		Console.print_line("No active override for %s." % path)
		return
	Console.print_line("Removed override for %s." % path)


func _clear_all_overrides_for_console(confirmation: String = "") -> void:
	if not _confirm_override_replacement_for_console(confirmation, "clear overrides"):
		return
	var cleared := [0]
	batch_changes(func():
		for variable_path in _get_overridden_variable_paths():
			if clear_override(variable_path):
				cleared[0] = int(cleared[0]) + 1
	)
	if int(cleared[0]) <= 0:
		Console.print_line("No active state variable overrides.")
		return
	Console.print_line("Cleared %d state variable override(s)." % int(cleared[0]))


func _get_override_confirmation_options() -> Array:
	return [["confirm"]]


func _confirm_override_replacement_for_console(confirmation: String, action: String) -> bool:
	if _get_overridden_variable_paths().is_empty():
		return true
	if confirmation.strip_edges().to_lower() == "confirm":
		return true
	Console.print_error("Active overrides must be cleared before %s. Select 'confirm' to continue." % action)
	return false


func _validate_override_set_name(raw_name: String) -> Dictionary:
	var set_name := raw_name.strip_edges()
	if set_name.is_empty():
		return {"ok": false, "error": "Override set name cannot be empty."}
	for invalid_character in ["/", "\\", " ", "\t", "\n", "\r"]:
		if set_name.find(invalid_character) != -1:
			return {"ok": false, "error": "Override set names cannot contain spaces or slashes."}
	return {"ok": true, "name": set_name}


func _load_override_sets_config() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(_OVERRIDE_SETS_SAVE_PATH)
	return config


func _get_saved_override_set_names() -> Array[String]:
	var names: Array[String] = []
	for section in _load_override_sets_config().get_sections():
		names.append(str(section))
	names.sort()
	return names


func _capture_current_overrides() -> Dictionary:
	var values := {}
	for variable in get_overridden_variables():
		values[String(variable.get_path())] = _serialize_value(variable.definition, variable.get_override_value())
	return values


func _write_override_set(set_name: String, allow_overwrite: bool) -> bool:
	var config := _load_override_sets_config()
	if config.has_section(set_name) and not allow_overwrite:
		Console.print_error("An override set named '%s' already exists." % set_name)
		return false
	if config.has_section(set_name):
		config.erase_section(set_name)
	config.set_value(set_name, _OVERRIDE_SET_METADATA_KEY, true)
	var current_overrides := _capture_current_overrides()
	for path in current_overrides:
		config.set_value(set_name, path, current_overrides[path])
	var error := config.save(_OVERRIDE_SETS_SAVE_PATH)
	if error != OK:
		Console.print_error("Failed to save override set '%s' (error %d)." % [set_name, error])
		return false
	return true


func _save_override_set_for_console(raw_name: String) -> void:
	var validation := _validate_override_set_name(raw_name)
	if not bool(validation.get("ok", false)):
		Console.print_error(str(validation.get("error", "Invalid override set name.")))
		return
	var set_name := str(validation.get("name", ""))
	if not _write_override_set(set_name, false):
		return
	_reload_override_set_console_commands()
	if not _get_saved_override_set_names().has(set_name):
		Console.print_error("Saved override set '%s' could not be found after reloading." % set_name)
		return
	Console.print_line("Saved override set '%s'." % set_name)
	Console.call_deferred("reveal_command_path", "%s/load/%s" % [_CONSOLE_OVERRIDES_PATH, set_name])


func _reload_override_set_console_commands() -> void:
	for path in _registered_override_set_commands:
		Console.remove_command(path)
		_registered_console_commands.erase(path)
	_registered_override_set_commands.clear()
	for set_name in _get_saved_override_set_names():
		var base_path := "%s/load/%s" % [_CONSOLE_OVERRIDES_PATH, set_name]
		_register_override_set_command(base_path, Callable(self, "_load_override_set_for_console").bind(set_name), "Loads this override set after clearing active overrides.", ["confirm"], 0, Callable(self, "_get_override_confirmation_options"))
		_register_override_set_command("%s/delete" % base_path, Callable(self, "_delete_override_set_for_console").bind(set_name), "Deletes this saved override set.")
		_register_override_set_command("%s/overwrite" % base_path, Callable(self, "_overwrite_override_set_for_console").bind(set_name), "Overwrites this set with the current overrides.")


func _register_override_set_command(path: String, callable: Callable, description: String, arguments: Array = [], required: int = 0, options_provider: Callable = Callable()) -> void:
	_register_console_command(path, callable, description, _CONSOLE_GROUP_NAME, _CONSOLE_GROUP_PRIORITY, arguments, required, options_provider)
	_registered_override_set_commands.append(path)


func _load_override_set_for_console(confirmation: String, set_name: String) -> void:
	if not _confirm_override_replacement_for_console(confirmation, "load override set '%s'" % set_name):
		return
	var config := _load_override_sets_config()
	if not config.has_section(set_name):
		Console.print_error("Override set not found: %s" % set_name)
		_reload_override_set_console_commands()
		return
	var failures: Array[String] = []
	batch_changes(func():
		clear_all_overrides()
		for raw_path in config.get_section_keys(set_name):
			var path := str(raw_path)
			if path == _OVERRIDE_SET_METADATA_KEY:
				continue
			var variable := get_variable(path)
			if variable == null:
				failures.append(path)
				continue
			var stored_value: Variant = config.get_value(set_name, path, null)
			if not set_override(path, _deserialize_value(variable.definition, stored_value)):
				failures.append(path)
	)
	Console.print_line("Loaded override set '%s'." % set_name)
	for path in failures:
		Console.print_error("Could not apply saved state variable '%s'." % path)


func _delete_override_set_for_console(set_name: String) -> void:
	var config := _load_override_sets_config()
	if not config.has_section(set_name):
		Console.print_error("Override set not found: %s" % set_name)
		return
	config.erase_section(set_name)
	var error := config.save(_OVERRIDE_SETS_SAVE_PATH)
	if error != OK:
		Console.print_error("Failed to delete override set '%s' (error %d)." % [set_name, error])
		return
	_reload_override_set_console_commands()
	Console.print_line("Deleted override set '%s'." % set_name)


func _overwrite_override_set_for_console(set_name: String) -> void:
	if not _get_saved_override_set_names().has(set_name):
		Console.print_error("Override set not found: %s" % set_name)
		return
	if _write_override_set(set_name, true):
		Console.print_line("Overwrote override set '%s' with the current overrides." % set_name)


func _print_overrides_summary_for_console() -> void:
	var overridden_paths := _get_overridden_variable_paths()
	if overridden_paths.is_empty():
		Console.print_line("No active state variable overrides.")
		return
	var lines: PackedStringArray = []
	lines.append("Active state variable overrides:")
	for path in overridden_paths:
		var variable := get_variable(path)
		if variable == null:
			continue
		var console_path := _get_console_variable_path(path)
		lines.append(
			"  %s = %s (remove: /%s)" % [
				console_path,
				str(variable.get_override_value()),
				_get_console_remove_override_path(console_path),
			]
		)
	lines.append("  remove all: /%s/clear" % _CONSOLE_OVERRIDES_PATH)
	Console.print_line("\n".join(lines))


func _get_overrides_display_text_for_console() -> String:
	return str(_get_overridden_variable_paths().size())


func _get_overridden_variable_paths() -> Array[String]:
	var overridden_paths: Array[String] = []
	for variable in get_overridden_variables():
		if not variable.definition.console_exposed:
			continue
		overridden_paths.append(String(variable.get_path()))
	overridden_paths.sort()
	return overridden_paths


func _get_console_notifier(address: String) -> StateConsoleNotifier:
	var normalized_address := _normalize_path(address)
	if not _console_notifiers_by_address.has(normalized_address):
		_console_notifiers_by_address[normalized_address] = StateConsoleNotifier.new()
	return _console_notifiers_by_address[normalized_address] as StateConsoleNotifier


func _flush_targeted_console_changes(
	_committed_paths: PackedStringArray,
	membership_changed_paths: Array,
	override_changed_paths: Array
) -> void:
	var addresses_to_notify: Dictionary = {}
	for path_variant in membership_changed_paths:
		var state_variable := get_variable(String(path_variant))
		if state_variable == null or not state_variable.definition.console_exposed:
			continue
		var segments := String(path_variant).split("/", false)
		var folder_parts := PackedStringArray()
		for segment_index in range(maxi(0, segments.size() - 1)):
			folder_parts.append(segments[segment_index])
			addresses_to_notify["/".join(folder_parts)] = true
	if Console != null and (not membership_changed_paths.is_empty() or not override_changed_paths.is_empty()):
		var topology_paths: Dictionary = {}
		for path_variant in override_changed_paths:
			topology_paths[String(path_variant)] = true
		Console.batch_ui_updates(func():
			# Override-only changes (no claim membership change) still need the per-variable
			# topology refreshed, since the "override/remove" default-child command only exists
			# once has_override() is true; otherwise the root command's default child resolves
			# to a target that was never registered.
			for path_variant in topology_paths.keys():
				var state_variable := get_variable(String(path_variant))
				if state_variable != null and not state_variable.definition.console_hidden:
					_refresh_layered_variable_topology(String(path_variant))
			# Folder bulk actions reflect stored base and override membership only;
			# claim topology cannot change them. Recomputing every folder counter on
			# each gameplay claim made physics callbacks scan the entire state graph.
			if not override_changed_paths.is_empty():
				_refresh_layered_folder_commands()
			if not override_changed_paths.is_empty():
				_sync_override_console_entries()
		)
	for address_variant in addresses_to_notify.keys():
		var address := String(address_variant)
		if _console_notifiers_by_address.has(address):
			(_console_notifiers_by_address[address] as StateConsoleNotifier).notify()


func _sync_override_console_entries() -> void:
	if Console == null:
		return
	var desired_paths: Dictionary = {}
	for variable_path in _get_overridden_variable_paths():
		desired_paths[variable_path] = true
	var registered_paths: Dictionary = {}
	for variable_path in _registered_override_menu_dynamic_display_variables.keys():
		registered_paths[String(variable_path)] = true
	for variable_path in _registered_override_menu_dynamic_commands.keys():
		registered_paths[String(variable_path)] = true
	for variable_path in _registered_variable_remove_override_commands.keys():
		registered_paths[String(variable_path)] = true
	var removed_paths: Array[String] = []
	for variable_path in registered_paths.keys():
		if not desired_paths.has(variable_path):
			removed_paths.append(String(variable_path))
	removed_paths.sort()
	var added_paths: Array[String] = []
	for variable_path in desired_paths.keys():
		if not registered_paths.has(variable_path):
			added_paths.append(String(variable_path))
	added_paths.sort()
	if removed_paths.is_empty() and added_paths.is_empty():
		return
	Console.batch_ui_updates(func():
		for variable_path in removed_paths:
			_remove_override_console_entry(variable_path)
		for variable_path in added_paths:
			_add_override_console_entry(variable_path)
	)


func _add_override_console_entry(variable_path: String) -> void:
	var variable := get_variable(variable_path)
	if variable == null or not variable.definition.console_exposed:
		return
	var console_variable_path := _get_console_variable_path(variable_path)
	var override_entry_path := "%s/%s" % [_CONSOLE_OVERRIDES_PATH, console_variable_path]
	var menu_remove_path := "%s/remove" % override_entry_path
	var variable_remove_path := _get_console_remove_override_path(console_variable_path)
	Console.add_display_variable(
		override_entry_path,
		Callable(self, "_get_variable_override_value_for_console").bind(variable_path),
		Callable(self, "_get_variable_inline_color_for_console").bind(variable_path),
		Callable(),
		true,
		_CONSOLE_OVERRIDE_GROUP_NAME,
		_CONSOLE_OVERRIDE_GROUP_PRIORITY,
		variable,
		&"console_display_changed"
	)
	Console.add_command(menu_remove_path, Callable(self, "_clear_override_for_console").bind(variable_path), [], 0, "Removes this state variable override.", _CONSOLE_GROUP_NAME, _CONSOLE_GROUP_PRIORITY)
	Console.add_command(variable_remove_path, Callable(self, "_clear_override_for_console").bind(variable_path), [], 0, "Removes the active override for this state variable.", _CONSOLE_OVERRIDE_GROUP_NAME, _CONSOLE_OVERRIDE_GROUP_PRIORITY)
	Console.set_display_variable_transiently_pinned(override_entry_path, true)
	_registered_override_menu_dynamic_display_variables[variable_path] = override_entry_path
	_registered_override_menu_dynamic_commands[variable_path] = menu_remove_path
	_registered_variable_remove_override_commands[variable_path] = variable_remove_path


func _remove_override_console_entry(variable_path: String) -> void:
	var menu_remove_path := String(_registered_override_menu_dynamic_commands.get(variable_path, ""))
	if not menu_remove_path.is_empty():
		Console.remove_command(menu_remove_path)
	var variable_remove_path := String(_registered_variable_remove_override_commands.get(variable_path, ""))
	if not variable_remove_path.is_empty():
		Console.remove_command(variable_remove_path)
	var override_entry_path := String(_registered_override_menu_dynamic_display_variables.get(variable_path, ""))
	if not override_entry_path.is_empty():
		Console.set_display_variable_transiently_pinned(override_entry_path, false)
		Console.remove_display_variable(override_entry_path)
	_registered_override_menu_dynamic_commands.erase(variable_path)
	_registered_override_menu_dynamic_display_variables.erase(variable_path)
	_registered_variable_remove_override_commands.erase(variable_path)


func _clear_override_console_entries() -> void:
	var registered_paths: Dictionary = {}
	for variable_path in _registered_override_menu_dynamic_display_variables.keys():
		registered_paths[String(variable_path)] = true
	for variable_path in _registered_override_menu_dynamic_commands.keys():
		registered_paths[String(variable_path)] = true
	for variable_path in _registered_variable_remove_override_commands.keys():
		registered_paths[String(variable_path)] = true
	var sorted_paths: Array[String] = []
	for variable_path in registered_paths.keys():
		sorted_paths.append(String(variable_path))
	sorted_paths.sort()
	for variable_path in sorted_paths:
		_remove_override_console_entry(variable_path)


func _get_console_remove_override_path(console_variable_path: String) -> String:
	return "%s/remove_override" % console_variable_path


func _on_variable_default_value_changed(_variable_path: StringName, _old_value: Variant, _new_value: Variant) -> void:
	pass


func _on_variable_base_value_changed(_variable_path: StringName, _has_value: bool, _value: Variant) -> void:
	if not _loading_persistent_values:
		_schedule_persistent_save()


func _on_variable_claims_changed(variable_path: StringName) -> void:
	var path := String(variable_path)
	var variable := get_variable(path)
	if variable == null:
		return
	var previous := _claim_snapshot_state_by_path.get(path, {}) as Dictionary
	var current := _claim_snapshot_state(variable)
	var changed_keys: Dictionary = {}
	for key in previous.keys():
		if not current.has(key) or str(previous[key]) != str(current[key]):
			changed_keys[String(key)] = true
	for key in current.keys():
		if not previous.has(key) or str(previous[key]) != str(current[key]):
			changed_keys[String(key)] = true
	_claim_snapshot_state_by_path[path] = current
	if changed_keys.is_empty():
		return
	var pending := _pending_claim_snapshot_keys_by_path.get(path, {}) as Dictionary
	for key in changed_keys.keys():
		pending[String(key)] = true
	_pending_claim_snapshot_keys_by_path[path] = pending


func _claim_snapshot_state(variable: StateVariable) -> Dictionary:
	var state: Dictionary = {}
	for snapshot in variable.get_claim_snapshots():
		var code_key := str(snapshot.get("code_key", ""))
		var stable_key := code_key if not code_key.is_empty() else str(snapshot.get("slot_id", ""))
		state[stable_key] = var_to_str(snapshot)
	return state


func _flush_claim_snapshot_changes() -> void:
	var paths: Array[String] = []
	for path_variant in _pending_claim_snapshot_keys_by_path.keys():
		paths.append(String(path_variant))
	paths.sort()
	for path in paths:
		var changed := _pending_claim_snapshot_keys_by_path.get(path, {}) as Dictionary
		var keys := PackedStringArray()
		for key_variant in changed.keys():
			keys.append(String(key_variant))
		keys.sort()
		if not keys.is_empty():
			claim_snapshots_changed.emit(StringName(path), keys)
			if Console != null:
				if Console.has_method("is_visible") and bool(Console.is_visible()):
					Console.batch_ui_updates(func(): _refresh_layered_claim_commands(path))
				else:
					_deferred_claim_console_paths[path] = true
	_pending_claim_snapshot_keys_by_path.clear()


## Claim inspection remains live through StateStore signals while gameplay runs.
## The command palette topology is presentation-only, so hidden-console changes
## coalesce here and are reconciled when the console is opened.
func flush_pending_console_updates() -> void:
	if Console == null or _deferred_claim_console_paths.is_empty():
		return
	var paths: Array[String] = []
	for path_variant in _deferred_claim_console_paths.keys():
		paths.append(String(path_variant))
	paths.sort()
	_deferred_claim_console_paths.clear()
	Console.batch_ui_updates(func():
		for path in paths:
			_refresh_layered_claim_commands(path)
	)


func _on_variable_override_changed(_variable_path: StringName, _overridden: bool, _value: Variant) -> void:
	if not _loading_persistent_values:
		_schedule_persistent_save()


func _on_variable_console_display_changed(_variable_path: StringName) -> void:
	pass


func _serialize_value(definition: StateVariableDef, value: Variant) -> Variant:
	match definition.value_type:
		StateVariableDef.ValueType.ENUM_TOGGLE:
			return definition.enum_toggle_values(value)
		StateVariableDef.ValueType.LIST:
			return definition.list_keys(value)
		StateVariableDef.ValueType.VECTOR2:
			if value == null:
				return null
			var vec := value as Vector2
			return [vec.x, vec.y]
		StateVariableDef.ValueType.VECTOR3:
			if value == null:
				return null
			var vec3 := value as Vector3
			return [vec3.x, vec3.y, vec3.z]
		_:
			return value


func _deserialize_value(definition: StateVariableDef, value: Variant) -> Variant:
	match definition.value_type:
		StateVariableDef.ValueType.BOOL:
			return bool(value)
		StateVariableDef.ValueType.INT:
			return int(value)
		StateVariableDef.ValueType.FLOAT:
			return float(value)
		StateVariableDef.ValueType.ENUM, StateVariableDef.ValueType.STRING:
			return str(value)
		StateVariableDef.ValueType.ENUM_TOGGLE:
			if value is Array:
				return (value as Array).duplicate()
			return []
		StateVariableDef.ValueType.LIST:
			if value is Array:
				return (value as Array).duplicate()
			return []
		StateVariableDef.ValueType.VECTOR2:
			if value is Array and value.size() >= 2:
				return Vector2(float(value[0]), float(value[1]))
			return Vector2.ZERO
		StateVariableDef.ValueType.VECTOR3:
			if value is Array and value.size() >= 3:
				return Vector3(float(value[0]), float(value[1]), float(value[2]))
			return Vector3.ZERO
		_:
			return value


func _try_deserialize_value(definition: StateVariableDef, value: Variant) -> Dictionary:
	var valid := false
	match definition.value_type:
		StateVariableDef.ValueType.BOOL:
			valid = value is bool
		StateVariableDef.ValueType.INT:
			valid = value is int
		StateVariableDef.ValueType.FLOAT:
			valid = value is float or value is int
		StateVariableDef.ValueType.ENUM, StateVariableDef.ValueType.STRING:
			valid = value is String or value is StringName
		StateVariableDef.ValueType.ENUM_TOGGLE, StateVariableDef.ValueType.LIST:
			valid = value is Array
		StateVariableDef.ValueType.VECTOR2:
			valid = value is Vector2 or (
				value is Array
				and value.size() >= 2
				and (value[0] is float or value[0] is int)
				and (value[1] is float or value[1] is int)
			)
		StateVariableDef.ValueType.VECTOR3:
			valid = value is Vector3 or (
				value is Array
				and value.size() >= 3
				and (value[0] is float or value[0] is int)
				and (value[1] is float or value[1] is int)
				and (value[2] is float or value[2] is int)
			)
	if not valid:
		return {"ok": false}
	return {"ok": true, "value": _deserialize_value(definition, value)}


func _normalize_path(path: String) -> String:
	return path.strip_edges().to_lower()


func _get_console_variable_path(path: String) -> String:
	return _normalize_path(path)


func _refresh_all_emitted_claims() -> void:
	for source_path in _emitted_claims_by_source.keys():
		_clear_emitted_claims_for_source(String(source_path))
	for variable in _variables_by_path.values():
		var state_variable := variable as StateVariable
		_refresh_emitted_claims_for_source(String(state_variable.get_path()))


func _refresh_emitted_claims_for_source(source_path: String) -> void:
	source_path = _normalize_path(source_path)
	if _blocked_emitter_paths.has(source_path):
		_clear_emitted_claims_for_source(source_path)
		return
	var source_variable := get_variable(source_path)
	if source_variable == null:
		_clear_emitted_claims_for_source(source_path)
		return
	var case_def: StateVariableCaseDef = source_variable.definition.find_matching_case(source_variable.resolved_value)
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
		var entry_key := "%s|%s" % [str(entry.get("target_path", "")), str(entry.get("code_key", ""))]
		if desired.has(entry_key):
			continue
		clear_claim(str(entry.get("target_path", "")), StringName(str(entry.get("code_key", ""))))
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
	if _batch_processing:
		if _batch_transition_evaluation_count >= _batch_transition_evaluation_limit:
			_batch_transition_limit_hit = true
			return
		_batch_transition_evaluation_count += 1
	_transition_evaluation_count += 1
	_batch_changed_transition_ids[transition_id] = true
	var active := _is_transition_active(transition_def)
	var was_active := bool(_transition_active_by_id.get(transition_id, false))
	if active != was_active or not _transition_active_by_id.has(transition_id):
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
			var code_key := String(_build_transition_claim_code_key(transition_def, output_def, output_index))
			var entry_key := _transition_claim_key(target_path, code_key)
			desired[entry_key] = {
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
		if desired.has(_transition_claim_key(target_path, code_key)):
			continue
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


func _is_transition_active(transition_def) -> bool:
	if transition_def == null:
		return false
	for condition_variant in transition_def.conditions:
		var condition: Variant = condition_variant
		if condition == null:
			continue
		var target_path := String(condition.get_normalized_target_state_path())
		var target_variable := get_variable(target_path)
		if target_variable == null:
			return false
		if not bool(condition.matches(target_variable.definition, target_variable.resolved_value)):
			return false
	return true


func _build_transition_claim_code_key(transition_def, output_def, output_index: int) -> StringName:
	var suffix := String(output_def.get_normalized_target_claim_slot_id())
	if suffix.is_empty():
		suffix = "output_%d" % output_index
	return StringName("transition/%d/%s" % [int(transition_def.get_normalized_transition_id()), suffix])


func _transition_claim_key(target_path: String, code_key: String) -> String:
	return "%s|%s" % [_normalize_path(target_path), str(code_key).strip_edges().to_lower()]


func _snapshot_resolved_values() -> Dictionary:
	var snapshot: Dictionary = {}
	for path_variant in _variables_by_path.keys():
		var path := String(path_variant)
		var variable := _variables_by_path[path_variant] as StateVariable
		if variable == null:
			continue
		snapshot[path] = _serialize_value(variable.definition, variable.resolved_value)
	return snapshot


func _resolved_value_snapshots_match(previous: Dictionary, current: Dictionary) -> bool:
	if previous.size() != current.size():
		return false
	for path_variant in _variables_by_path.keys():
		var path := String(path_variant)
		if not previous.has(path) or not current.has(path):
			return false
		var variable := _variables_by_path[path_variant] as StateVariable
		if variable == null:
			continue
		var previous_value: Variant = _deserialize_value(variable.definition, previous.get(path))
		var current_value: Variant = _deserialize_value(variable.definition, current.get(path))
		if not variable.definition.values_equal(previous_value, current_value):
			return false
	return true


func _clear_emitted_claims_for_source(source_path: String) -> void:
	source_path = _normalize_path(source_path)
	if not _emitted_claims_by_source.has(source_path):
		return
	var emitted: Array = _emitted_claims_by_source.get(source_path, [])
	_emitted_claims_by_source.erase(source_path)
	for entry in emitted:
		if not (entry is Dictionary):
			continue
		var target_path := String(entry.get("target_path", ""))
		var code_key := StringName(str(entry.get("code_key", "")))
		if target_path.is_empty() or code_key == &"":
			continue
		clear_claim(target_path, code_key)


func _validate_outgoing_change_graph() -> void:
	_blocked_emitter_paths.clear()
	_invalid_targets_by_source.clear()
	_case_emitter_source_paths.clear()
	if database == null:
		return

	var graph: Dictionary = {}
	for definition in database.get_definitions():
		if definition == null:
			continue
		var source_path := String(definition.get_normalized_path())
		if source_path.is_empty():
			continue
		var unique_targets: Dictionary = {}
		for case_def in definition.get_case_definitions():
			if case_def == null:
				continue
			for change in case_def.outgoing_changes:
				if change == null:
					continue
				var target_path := String(change.get_normalized_target_path())
				if target_path.is_empty():
					continue
				if target_path == source_path:
					_mark_invalid_target(source_path, target_path, "self-reference")
					continue
					if not _variables_by_path.has(target_path):
						_mark_invalid_target(source_path, target_path, "unknown target")
						continue
					unique_targets[target_path] = true
					_case_emitter_source_paths[source_path] = true
			graph[source_path] = unique_targets.keys()

	var visit_state: Dictionary = {}
	var stack: Array[String] = []
	for source_path in graph.keys():
		if int(visit_state.get(source_path, 0)) != 0:
			continue
		_validate_graph_node(String(source_path), graph, visit_state, stack)


func _validate_graph_node(node: String, graph: Dictionary, visit_state: Dictionary, stack: Array[String]) -> void:
	visit_state[node] = 1
	stack.append(node)

	var neighbors: Array = graph.get(node, [])
	for neighbor_variant in neighbors:
		var neighbor := String(neighbor_variant)
		var state := int(visit_state.get(neighbor, 0))
		if state == 0:
			_validate_graph_node(neighbor, graph, visit_state, stack)
			continue
		if state != 1:
			continue
		var cycle_start := stack.find(neighbor)
		if cycle_start == -1:
			continue
		for idx in range(cycle_start, stack.size()):
			var cycle_node := stack[idx]
			if _blocked_emitter_paths.has(cycle_node):
				continue
			_blocked_emitter_paths[cycle_node] = true
			_try_log_state_warning(func() -> Array:
				return ["StateStore: Outgoing state changes for '%s' were rejected because they participate in a cycle." % cycle_node]
			)

		stack.pop_back()
		visit_state[node] = 2


func _rebuild_transition_dependency_indexes() -> void:
	_transition_ids_by_condition_path.clear()
	_transition_defs_by_id.clear()
	_transition_active_by_id.clear()
	if database == null:
		return
	var transition_defs: Array = database.get_transition_definitions()
	for transition_variant in transition_defs:
		var transition_def: Variant = transition_variant
		if transition_def == null:
			continue
		var transition_id := int(transition_def.get_normalized_transition_id())
		if transition_id <= 0:
			continue
		_transition_defs_by_id[transition_id] = transition_def
		for condition_variant in transition_def.conditions:
			var condition: Variant = condition_variant
			if condition == null:
				continue
			var source_path := _normalize_path(String(condition.get_normalized_target_state_path()))
			if source_path.is_empty():
				continue
			if not _transition_ids_by_condition_path.has(source_path):
				_transition_ids_by_condition_path[source_path] = []
			var ids: Array = _transition_ids_by_condition_path[source_path]
			if not ids.has(transition_id):
				ids.append(transition_id)


func _mark_invalid_target(source_path: String, target_path: String, reason: String) -> void:
	if not _invalid_targets_by_source.has(source_path):
		_invalid_targets_by_source[source_path] = {}
	_invalid_targets_by_source[source_path][target_path] = true
	_try_log_state_warning(func() -> Array:
		return ["StateStore: Outgoing state change from '%s' to '%s' was rejected (%s)." % [source_path, target_path, reason]]
	)


func _glob_matches(pattern: String, text: String) -> bool:
	var regex := RegEx.new()
	var escaped := ""
	for character in pattern:
		if character == "*":
			escaped += ".*"
		else:
			escaped += _escape_regex_character(character)
	return regex.compile("^%s$" % escaped) == OK and regex.search(text) != null


func _escape_regex_character(character: String) -> String:
	if character in ["\\", ".", "^", "$", "|", "(", ")", "[", "]", "{", "}", "+", "?", "-"]:
		return "\\%s" % character
	return character


func _ensure_state_graph_toggle_action() -> void:
	if InputMap.has_action(_STATE_GRAPH_TOGGLE_ACTION):
		return
	InputMap.add_action(_STATE_GRAPH_TOGGLE_ACTION)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_BACKSLASH
	InputMap.action_add_event(_STATE_GRAPH_TOGGLE_ACTION, event)


func _ensure_state_change_probe_action() -> void:
	if InputMap.has_action(_STATE_CHANGE_PROBE_ACTION):
		return
	InputMap.add_action(_STATE_CHANGE_PROBE_ACTION)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F9
	InputMap.action_add_event(_STATE_CHANGE_PROBE_ACTION, event)


func _set_state_graph_debug_mode(mode: StringName) -> void:
	if _state_graph_debug_mode == mode:
		return
	_state_graph_debug_mode = mode
	state_graph_debug_mode_changed.emit(_state_graph_debug_mode)
	if mode == &"hidden":
		if _state_graph_overlay != null and is_instance_valid(_state_graph_overlay):
			_state_graph_overlay.visible = false
			_state_graph_overlay.queue_free()
		_state_graph_overlay = null
		_set_logot_pinned_overlay_suppressed(false)
		return
	_ensure_state_graph_overlay()
	_set_logot_pinned_overlay_suppressed(
		_state_graph_overlay != null and is_instance_valid(_state_graph_overlay)
	)
	if _state_graph_overlay != null and _state_graph_overlay.has_method("set_mode"):
		_state_graph_overlay.call("set_mode", String(_state_graph_debug_mode))


func _set_logot_pinned_overlay_suppressed(suppressed: bool) -> void:
	if Console == null:
		return
	if not suppressed:
		if Console.has_method("_sync_pinned_overlay_suppression"):
			Console.call("_sync_pinned_overlay_suppression")
		return
	if not Console.has_method("_get_live_displays"):
		return
	for display in Console.call("_get_live_displays"):
		if display != null and display.has_method("set_pinned_display_variables_suppressed"):
			display.call("set_pinned_display_variables_suppressed", true)


func _ensure_state_graph_overlay() -> void:
	var overlay_script := StateGraphOverlayScript
	if overlay_script == null:
		return
	if _state_graph_overlay != null and is_instance_valid(_state_graph_overlay):
		return
	_state_graph_overlay = CanvasLayer.new()
	_state_graph_overlay.set_script(overlay_script)
	_state_graph_overlay.layer = STATE_GRAPH_OVERLAY_CANVAS_LAYER
	add_child(_state_graph_overlay)
	if _state_graph_overlay.has_method("set_state_store"):
		_state_graph_overlay.call("set_state_store", self)
	if _state_graph_overlay.has_method("set_mode"):
		_state_graph_overlay.call("set_mode", String(_state_graph_debug_mode))


func _register_debugger_capture() -> void:
	if not EngineDebugger.is_active():
		return
	if EngineDebugger.has_capture("state_graph"):
		return
	EngineDebugger.register_message_capture("state_graph", Callable(self, "_on_debugger_message"))


func _on_debugger_message(message: String, data: Array) -> bool:
	var subscriber_key := str(data[0]) if not data.is_empty() else "editor"
	match message:
		"state_graph:subscribe":
			_state_graph_debug_subscribers[subscriber_key] = true
			return true
		"state_graph:unsubscribe":
			_state_graph_debug_subscribers.erase(subscriber_key)
			return true
		"state_graph:request_snapshot":
			_send_state_graph_snapshot_now()
			return true
		"state_graph:select_scope":
			if data.size() > 1 and select_state_graph_scope(StringName(str(data[1]))):
				_send_state_graph_snapshot_now()
			return true
	return false


func _send_state_graph_snapshot_now() -> void:
	if not _should_broadcast_state_graph_snapshot():
		return
	EngineDebugger.send_message(
		"state_graph:snapshot",
		[get_state_graph_snapshot_for_scope(_state_graph_selected_scope_key)]
	)


func _emit_state_graph_delta(changed_paths: PackedStringArray) -> void:
	if changed_paths.is_empty() and _batch_changed_transition_ids.is_empty():
		return
	if not _has_state_graph_delta_consumers():
		return
	var state_snapshots: Array[Dictionary] = []
	for path in changed_paths:
		var snapshot := _build_state_graph_state_snapshot(path)
		if not snapshot.is_empty():
			state_snapshots.append(snapshot)
	var transition_snapshots: Array[Dictionary] = []
	var transition_ids: Array[int] = []
	for transition_id_variant in _batch_changed_transition_ids.keys():
		transition_ids.append(int(transition_id_variant))
	transition_ids.sort()
	for transition_id in transition_ids:
		var snapshot := _build_state_graph_transition_snapshot(transition_id)
		if not snapshot.is_empty():
			transition_snapshots.append(snapshot)
	var delta := {
		"schema_version": _STATE_GRAPH_SCHEMA_VERSION,
		"topology_version": _state_graph_topology_version,
		"scope_key": String(StateMachineScopeAddress.GLOBAL_KEY),
		"template_key": String(StateMachineScopeAddress.GLOBAL_KEY),
		"instance_key": "",
		"states": state_snapshots,
		"transitions": transition_snapshots,
	}
	_state_graph_delta_emit_count += 1
	state_graph_delta_ready.emit(delta)
	if _should_broadcast_state_graph_snapshot():
		EngineDebugger.send_message("state_graph:delta", [delta])


func _has_state_graph_delta_consumers() -> bool:
	return not state_graph_delta_ready.get_connections().is_empty() or not _state_graph_debug_subscribers.is_empty()


func _should_broadcast_state_graph_snapshot() -> bool:
	if not EngineDebugger.is_active():
		return false
	return not _state_graph_debug_subscribers.is_empty()


func _initialize_host_defaults() -> void:
	pass
