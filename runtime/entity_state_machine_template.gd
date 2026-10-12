@tool
extends Resource
class_name EntityStateMachineTemplate

const StateMachineRuntime = preload("state_machine_runtime.gd")
const StateMachineScopeAddress = preload("state_machine_scope_address.gd")
const StateVariableDatabase = preload("state_variable_database.gd")

# Identifies this reusable local-machine definition across authored entities.
@export var template_key: StringName = &""
# Provides the shared variable and transition definitions for each runtime instance.
@export var database: StateVariableDatabase = null


func get_normalized_template_key() -> StringName:
	return StringName(String(template_key).strip_edges().to_lower().trim_prefix("/").trim_suffix("/"))


func ensure_valid_configuration() -> void:
	template_key = get_normalized_template_key()
	if database != null:
		database.ensure_valid_configuration()


func instantiate_runtime(
	scope_address: StateMachineScopeAddress,
	scope_bindings: Dictionary = {}
) -> StateMachineRuntime:
	ensure_valid_configuration()
	if template_key == &"" or database == null or scope_address == null:
		return null
	if not scope_address.is_valid() or scope_address.is_global():
		return null
	if scope_address.template_key != template_key:
		return null
	var runtime := StateMachineRuntime.new()
	if not runtime.configure(database, scope_address, false, false):
		return null
	runtime.set_scope_bindings(scope_bindings)
	return runtime
