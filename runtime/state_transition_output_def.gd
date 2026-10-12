@tool
extends Resource
class_name StateTransitionOutputDef

const StateVariableDef = preload("state_variable_def.gd")
const StateTransitionScope = preload("state_transition_scope.gd")

enum Operation {
	SET,
	ADD,
	REMOVE,
}

# Identifies the scene node used for target state.
@export var target_state_path: StringName = &""
# Resolves the target relative to this runtime, the global runtime, or an allowlisted binding.
@export var target_scope: StateTransitionScope.Scope = StateTransitionScope.Scope.CURRENT
# Names an instance binding when target_scope is BOUND.
@export var binding_key: StringName = &""
# Selects the target claim slot id.
@export var target_claim_slot_id: StringName = &""
# Sets the operation used by this component.
@export var operation: Operation = Operation.SET
# Enables or disables bool value.
@export var bool_value: bool = false
# Sets the int value used by this component.
@export var int_value: int = 0
# Sets the float value used by this component.
@export var float_value: float = 0.0
# Selects the string value.
@export var string_value: String = ""
# Selects the string array value.
@export var string_array_value: Array[String] = []
# Sets the vector2 value used by this component.
@export var vector2_value: Vector2 = Vector2.ZERO


func get_normalized_target_state_path() -> StringName:
	return StringName(str(target_state_path).strip_edges().to_lower())


func get_normalized_binding_key() -> StringName:
	return StateTransitionScope.normalize_binding_key(binding_key)


func get_normalized_target_claim_slot_id() -> StringName:
	return StringName(str(target_claim_slot_id).strip_edges().to_lower())


func get_target_value(definition: StateVariableDef) -> Variant:
	if definition == null:
		return null
	if definition.value_type == StateVariableDef.ValueType.LIST:
		return string_value
	if definition.value_type == StateVariableDef.ValueType.ENUM_TOGGLE:
		return string_array_value.duplicate()
	match definition.value_type:
		StateVariableDef.ValueType.BOOL:
			return bool_value
		StateVariableDef.ValueType.INT:
			return int_value
		StateVariableDef.ValueType.FLOAT:
			return float_value
		StateVariableDef.ValueType.ENUM, StateVariableDef.ValueType.STRING:
			return string_value
		StateVariableDef.ValueType.VECTOR2:
			return vector2_value
		_:
			return string_value


func set_target_value(definition: StateVariableDef, value: Variant) -> void:
	if definition == null:
		return
	if definition.value_type == StateVariableDef.ValueType.LIST:
		string_value = str(value)
		return
	if definition.value_type == StateVariableDef.ValueType.ENUM_TOGGLE:
		string_array_value = definition.enum_toggle_values(value)
		return
	var coerced: Variant = definition.coerce_value(value)
	match definition.value_type:
		StateVariableDef.ValueType.BOOL:
			bool_value = bool(coerced)
		StateVariableDef.ValueType.INT:
			int_value = int(coerced)
		StateVariableDef.ValueType.FLOAT:
			float_value = float(coerced)
		StateVariableDef.ValueType.ENUM, StateVariableDef.ValueType.STRING:
			string_value = str(coerced)
		StateVariableDef.ValueType.VECTOR2:
			vector2_value = coerced as Vector2


func get_supported_operations(definition: StateVariableDef) -> Array[int]:
	if definition != null and definition.value_type == StateVariableDef.ValueType.LIST:
		return [Operation.ADD, Operation.REMOVE]
	return [Operation.SET]


func get_operation_label() -> String:
	match operation:
		Operation.ADD:
			return "add"
		Operation.REMOVE:
			return "remove"
		_:
			return "set"
