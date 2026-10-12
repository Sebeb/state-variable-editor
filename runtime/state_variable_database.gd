@tool
extends Resource
class_name StateVariableDatabase

const LogLevel = preload("state_log_level.gd")
const StateTransitionDef = preload("state_transition_def.gd")
const StateVariableDef = preload("state_variable_def.gd")
const StateVariableRename = preload("state_variable_rename.gd")
const StateBindingIndex = preload("state_binding_index.gd")
const STATE_VALUES_SAVE_PATH := "user://state_variables.cfg"

const DEFAULT_DATABASE_PATH := "res://data/state/state_variable_database.tres"

# Provides the entries configured for this component.
@export var entries: Array[StateVariableDef] = []
# Provides the states configured for this component.
@export var states: Array[StateVariableDef] = []
# Provides the transitions configured for this component.
@export var transitions: Array[StateTransitionDef] = []
# Provides authored state definitions loaded alongside the stable main graph.
@export var supplemental_states: Array[StateVariableDef] = []

## Set when this instance is a runtime composition of the authored database plus baked
## code-declared definitions (see [method StateStore._load_database]). Not exported: it
## describes an in-memory instance, never a stored one.
##
## The guard exists because saving a composite would write generated entries back into
## the hand-authored `.tres`, re-creating the default/property duplication PGO-225 exists
## to remove — and doing it silently, since the file would still load fine afterwards.
var _runtime_composite_source := ""


func get_definitions() -> Array[StateVariableDef]:
	return get_state_definitions()


func get_state_definitions() -> Array[StateVariableDef]:
	_sync_legacy_state_arrays()
	return states


func get_transition_definitions() -> Array[StateTransitionDef]:
	return transitions


func get_definition_by_path(path: String) -> StateVariableDef:
	return get_state_definition_by_path(path)


func get_state_definition_by_path(path: String) -> StateVariableDef:
	var normalized := StringName(path.strip_edges().to_lower())
	for definition in get_state_definitions():
		if definition == null:
			continue
		if definition.get_normalized_path() == normalized:
			return definition
	return null


func get_transition_by_id(transition_id: int) -> StateTransitionDef:
	var normalized_transition_id := maxi(0, transition_id)
	for transition_def in transitions:
		if transition_def == null:
			continue
		if transition_def.get_normalized_transition_id() == normalized_transition_id:
			return transition_def
	return null


func get_next_transition_id() -> int:
	var max_transition_id := 0
	for transition_def in transitions:
		if transition_def == null:
			continue
		max_transition_id = maxi(max_transition_id, transition_def.get_normalized_transition_id())
	return max_transition_id + 1


func get_all_paths() -> Array[String]:
	var paths: Array[String] = []
	for definition in get_state_definitions():
		if definition == null:
			continue
		paths.append(String(definition.get_normalized_path()))
	paths.sort()
	return paths


func get_state_definitions_with_tag(tag: String) -> Array[StateVariableDef]:
	var definitions: Array[StateVariableDef] = []
	for definition in get_state_definitions():
		if definition != null and definition.has_tag(tag):
			definitions.append(definition)
	definitions.sort_custom(func(a: StateVariableDef, b: StateVariableDef): return String(a.get_normalized_path()) < String(b.get_normalized_path()))
	return definitions


func ensure_valid_configuration() -> void:
	_sync_legacy_state_arrays()
	var normalized_states: Array[StateVariableDef] = []
	var seen_paths: Dictionary = {}
	for definition in states:
		if definition == null:
			continue
		definition.ensure_valid_configuration()
		var normalized_path := definition.get_normalized_path()
		if normalized_path == &"":
			continue
		if seen_paths.has(normalized_path):
			# Two definitions claiming one path diverge silently: path lookups
			# resolve to the first while runtime variables are built from the
			# last, so editing one copy looks saved but never reaches gameplay.
			# Every state path must be defined exactly once.
			var kept := seen_paths[normalized_path] as StateVariableDef
			push_error(
				"StateVariableDatabase '%s': duplicate definition for state variable '%s'. Keeping default %s and discarding default %s." % [
					get_save_target_path(),
					String(normalized_path),
					var_to_str(kept.default_value),
					var_to_str(definition.default_value),
				]
			)
			continue
		seen_paths[normalized_path] = definition
		normalized_states.append(definition)
	states = normalized_states
	entries = states

	var normalized_transitions: Array[StateTransitionDef] = []
	var seen_transitions: Dictionary = {}
	for transition_def in transitions:
		if transition_def == null:
			continue
		transition_def.ensure_valid_configuration()
		var normalized_transition_id := transition_def.get_normalized_transition_id()
		if normalized_transition_id <= 0 or seen_transitions.has(normalized_transition_id):
			continue
		seen_transitions[normalized_transition_id] = true
		normalized_transitions.append(transition_def)
	transitions = normalized_transitions


## Marks this instance as a runtime composite of [param source_path] plus baked
## code-declared definitions, which makes it unsaveable.
func mark_runtime_composite(source_path: String) -> void:
	_runtime_composite_source = source_path


func is_runtime_composite() -> bool:
	return not _runtime_composite_source.is_empty()


## Reports a refused composite save through Logot when it is available, falling back to
## the engine log for editor-only callers that boot without the console autoload.
func _report_composite_save_refusal() -> void:
	var message := "StateVariableDatabase: refusing to save a runtime composite over '%s'. It holds baked code-declared definitions whose defaults belong to their own resources." % _runtime_composite_source
	# This script is @tool, and autoloads do not run in the editor, so the console is
	# resolved through the scene tree rather than by naming the autoload directly.
	var scene_tree := Engine.get_main_loop() as SceneTree
	var console: Node = scene_tree.get_root().get_node_or_null("Console") if scene_tree != null else null
	if console != null and console.has_method("try_log"):
		console.call("try_log", func() -> Array: return [message], LogLevel.ERROR, "State")
		return
	push_error(message)


func save_to_default_path() -> bool:
	if is_runtime_composite():
		_report_composite_save_refusal()
		return false
	ensure_valid_configuration()
	var target := get_save_target_path()
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	if error != OK and error != ERR_ALREADY_EXISTS:
		return false
	return ResourceSaver.save(self, target) == OK


# Local-machine template databases persist to their own resource path so editing
# an entity-type template never overwrites the global state database, while the
# global database (whose resource_path is the default path) is unaffected.
func get_save_target_path() -> String:
	if is_runtime_composite():
		return _runtime_composite_source
	var source_path := String(resource_path).strip_edges()
	if source_path.is_empty():
		return get_default_database_path()
	return source_path


func rename_state_variable(old_path: String, new_path: String) -> Dictionary:
	var bindings := StateBindingIndex.scan()
	var rename_plan := StateVariableRename.plan(states, transitions, bindings, old_path, new_path)
	if not bool(rename_plan.get("ok", false)) or str(rename_plan.get("reason", "")) == "no_op":
		return rename_plan
	var next_states: Array = states.duplicate(true)
	var next_transitions: Array = transitions.duplicate(true)
	if not StateVariableRename.apply(next_states, next_transitions, rename_plan):
		rename_plan.ok = false
		rename_plan.reason = "apply_failed"
		rename_plan.diagnostic = "The rename plan could not be applied."
		return rename_plan
	var previous_states: Array = states.duplicate(true)
	var previous_transitions: Array = transitions.duplicate(true)
	var binding_edits := rename_plan.get("binding_edits", {}) as Dictionary
	var previous_bindings := _binding_values(binding_edits)
	var resources := _load_binding_resources(binding_edits)
	if resources.is_empty() and not binding_edits.is_empty():
		return _rename_failure(rename_plan, "binding_unavailable", "A bound pill resource could not be loaded.")
	states = next_states
	transitions = next_transitions
	if not save_to_default_path():
		states = previous_states
		transitions = previous_transitions
		return _rename_failure(rename_plan, "save_failed", "The state database could not be saved.")
	for resource_path_variant in binding_edits.keys():
		var resource_path := str(resource_path_variant)
		var properties := resources.get(resource_path) as Resource
		if !StateBindingIndex.is_binding_resource(properties):
			continue
		properties.set(StateBindingIndex.get_property_name(), StringName(str(binding_edits[resource_path_variant])))
		if ResourceSaver.save(properties, resource_path) != OK:
			states = previous_states
			transitions = previous_transitions
			save_to_default_path()
			_restore_binding_values(resources, previous_bindings)
			return _rename_failure(rename_plan, "save_failed", "A bound pill resource could not be saved.")
	_migrate_persistent_value_keys(str(rename_plan.old_path), str(rename_plan.new_path))
	return rename_plan


func _migrate_persistent_value_keys(old_path: String, new_path: String) -> void:
	var config := ConfigFile.new()
	if config.load(STATE_VALUES_SAVE_PATH) != OK:
		return
	for section in ["bases", "overrides", "persistent_defaults"]:
		if config.has_section_key(section, old_path):
			config.set_value(section, new_path, config.get_value(section, old_path))
			config.erase_section_key(section, old_path)
	config.save(STATE_VALUES_SAVE_PATH)


func _load_binding_resources(bindings: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for resource_path_variant in bindings.keys():
		var resource_path := str(resource_path_variant)
		var properties := ResourceLoader.load(resource_path) as Resource
		if !StateBindingIndex.is_binding_resource(properties):
			return {}
		result[resource_path] = properties
	return result


func _binding_values(bindings: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for resource_path_variant in bindings.keys():
		var resource_path := str(resource_path_variant)
		var properties := ResourceLoader.load(resource_path) as Resource
		if properties != null:
			result[resource_path] = String(properties.get(StateBindingIndex.get_property_name()))
	return result


func _restore_binding_values(resources: Dictionary, bindings: Dictionary) -> void:
	for resource_path_variant in bindings.keys():
		var resource_path := str(resource_path_variant)
		var properties := resources.get(resource_path) as Resource
		if properties != null:
			properties.set(StateBindingIndex.get_property_name(), StringName(str(bindings[resource_path_variant])))
			ResourceSaver.save(properties, resource_path)


func _rename_failure(rename_plan: Dictionary, reason: String, diagnostic: String) -> Dictionary:
	rename_plan.ok = false
	rename_plan.reason = reason
	rename_plan.diagnostic = diagnostic
	return rename_plan


func _sync_legacy_state_arrays() -> void:
	if states.is_empty() and not entries.is_empty():
		states = entries
	elif entries.is_empty() and not states.is_empty():
		entries = states
	elif not states.is_empty() and not entries.is_empty() and states != entries:
		var merged_states := states.duplicate()
		for definition in entries:
			if definition != null and not merged_states.has(definition):
				merged_states.append(definition)
		states = merged_states
	for definition in supplemental_states:
		if definition != null and not states.has(definition):
			states.append(definition)
	entries = states


static func load_default_database() -> StateVariableDatabase:
	var path := str(ProjectSettings.get_setting("state_variables/database_path", DEFAULT_DATABASE_PATH))
	return load(path) as StateVariableDatabase if ResourceLoader.exists(path) else StateVariableDatabase.new()


static func get_default_database_path() -> String:
	return str(ProjectSettings.get_setting("state_variables/database_path", DEFAULT_DATABASE_PATH))
