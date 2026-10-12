extends Node
class_name EntityLocalStateMachine

const StateStore = preload("state_store_access.gd")
const EntityStateMachineTemplate = preload("entity_state_machine_template.gd")
const StateMachineRuntime = preload("state_machine_runtime.gd")
const StateMachineScopeAddress = preload("state_machine_scope_address.gd")

signal configured(scope_key: StringName)
signal state_changed(changed_paths: PackedStringArray)
signal torn_down(scope_key: StringName)

var runtime: StateMachineRuntime = null
var template: EntityStateMachineTemplate = null
var scope_key: StringName = &""
var placement_id := -1
var owner_instance_2d: Node2D = null
var observer_instance_3d: Node3D = null

var _tearing_down := false


func configure(
	machine_template: EntityStateMachineTemplate,
	authoritative_placement_id: int,
	instance_2d: Node2D,
	instance_3d: Node3D = null,
	scope_bindings: Dictionary = {},
	initial_values: Dictionary = {}
) -> bool:
	teardown()
	if (
		machine_template == null
		or authoritative_placement_id < 0
		or instance_2d == null
		or StateStore == null
		or StateStore.coordinator == null
	):
		return false
	var address: StateMachineScopeAddress = StateMachineScopeAddress.entity(
		machine_template.get_normalized_template_key(),
		StringName(str(authoritative_placement_id))
	)
	var created_runtime := machine_template.instantiate_runtime(address, scope_bindings)
	if created_runtime == null:
		return false
	for path_variant in initial_values:
		created_runtime.set_claim(str(path_variant), &"entity_local_initial_value", initial_values[path_variant])
	template = machine_template
	placement_id = authoritative_placement_id
	owner_instance_2d = instance_2d
	observer_instance_3d = instance_3d
	runtime = created_runtime
	scope_key = address.qualified_key
	if not StateStore.coordinator.register_runtime(runtime):
		runtime.teardown()
		runtime = null
		scope_key = &""
		return false
	runtime.batch_committed.connect(_on_runtime_batch_committed)
	if observer_instance_3d != null:
		observer_instance_3d.set("entity_local_state_machine", self)
	configured.emit(scope_key)
	return true


func get_variable(path: String):
	return runtime.get_variable(path) if runtime != null else null


func get_value(path: String, fallback: Variant = null) -> Variant:
	return runtime.get_value(path, fallback) if runtime != null else fallback


func set_claim(path: String, code_key: StringName, value: Variant) -> bool:
	return runtime != null and runtime.set_claim(path, code_key, value)


func clear_claim(path: String, code_key: StringName) -> bool:
	return runtime != null and runtime.clear_claim(path, code_key)


func teardown() -> void:
	if _tearing_down:
		return
	_tearing_down = true
	var old_scope_key := scope_key
	if runtime != null and runtime.batch_committed.is_connected(_on_runtime_batch_committed):
		runtime.batch_committed.disconnect(_on_runtime_batch_committed)
	if (
		runtime != null
		and StateStore != null
		and StateStore.coordinator != null
		and scope_key != &""
	):
		if not StateStore.coordinator.unregister_runtime(scope_key):
			runtime.teardown()
	elif runtime != null:
		runtime.teardown()
	if (
		observer_instance_3d != null
		and observer_instance_3d.get("entity_local_state_machine") == self
	):
		observer_instance_3d.set("entity_local_state_machine", null)
	runtime = null
	template = null
	scope_key = &""
	placement_id = -1
	owner_instance_2d = null
	observer_instance_3d = null
	_tearing_down = false
	if old_scope_key != &"":
		torn_down.emit(old_scope_key)


func _exit_tree() -> void:
	teardown()


func _on_runtime_batch_committed(
	changed_paths: PackedStringArray,
	_membership_changed_paths: PackedStringArray,
	_override_membership_changed_paths: PackedStringArray,
	_changed_transition_ids: PackedInt32Array
) -> void:
	if not changed_paths.is_empty():
		state_changed.emit(changed_paths)
