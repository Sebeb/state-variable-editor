@tool
extends Resource
class_name StateTransitionConditionDef

const StateVariableDef = preload("state_variable_def.gd")
const StateTransitionScope = preload("state_transition_scope.gd")

enum Operator {
	EQUALS,
	NOT_EQUALS,
	GREATER_EQUAL,
	GREATER_THAN,
	LESS_THAN,
	LESS_EQUAL,
	LIST_HAS,
	LIST_NOT_HAS,
	COUNT_EQUALS,
	COUNT_GREATER_EQUAL,
	COUNT_GREATER_THAN,
	COUNT_LESS_THAN,
	COUNT_LESS_EQUAL,
}

# Identifies the scene node used for target state.
@export var target_state_path: StringName = &""
# Resolves the target relative to this runtime, the global runtime, or an allowlisted binding.
@export var target_scope: StateTransitionScope.Scope = StateTransitionScope.Scope.CURRENT
# Names an instance binding when target_scope is BOUND.
@export var binding_key: StringName = &""
# Sets the operator used by this component.
@export var operator: Operator = Operator.EQUALS
# Enables or disables bool value.
@export var bool_value: bool = false
# Sets the int value used by this component.
@export var int_value: int = 0
# Sets the float value used by this component.
@export var float_value: float = 0.0
# Selects the string value.
@export var string_value: String = ""
# Selects the enum value when the target state is an enum.
@export var enum_value: String = ""
# Selects the string array value.
@export var string_array_value: Array[String] = []
# Sets the vector2 value used by this component.
@export var vector2_value: Vector2 = Vector2.ZERO


func get_normalized_target_state_path() -> StringName:
	return StringName(str(target_state_path).strip_edges().to_lower())


func get_normalized_binding_key() -> StringName:
	return StateTransitionScope.normalize_binding_key(binding_key)


func get_expected_value(definition: StateVariableDef) -> Variant:
	if definition == null:
		return null
	if definition.value_type == StateVariableDef.ValueType.LIST:
		if _operator_uses_list_count():
			return int_value
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
		StateVariableDef.ValueType.ENUM:
			return enum_value if not enum_value.is_empty() else string_value
		StateVariableDef.ValueType.STRING:
			return string_value
		StateVariableDef.ValueType.VECTOR2:
			return vector2_value
		_:
			return string_value


func set_expected_value(definition: StateVariableDef, value: Variant) -> void:
	if definition == null:
		return
	if definition.value_type == StateVariableDef.ValueType.LIST:
		if _operator_uses_list_count():
			int_value = int(value)
		else:
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
		StateVariableDef.ValueType.ENUM:
			enum_value = str(coerced)
			string_value = enum_value
		StateVariableDef.ValueType.STRING:
			string_value = str(coerced)
		StateVariableDef.ValueType.VECTOR2:
			vector2_value = coerced as Vector2


func matches(definition: StateVariableDef, actual_value: Variant) -> bool:
	if definition == null:
		return false
	var expected_value: Variant = get_expected_value(definition)
	if definition.value_type == StateVariableDef.ValueType.LIST:
		if _operator_uses_list_count():
			return _matches_numeric(float(definition.list_count(actual_value)), float(int(expected_value)))
		match operator:
			Operator.LIST_HAS:
				return definition.list_has_item_key(actual_value, expected_value)
			Operator.LIST_NOT_HAS:
				return not definition.list_has_item_key(actual_value, expected_value)
			_:
				return false
	if definition.value_type == StateVariableDef.ValueType.INT:
		return _matches_numeric(float(int(actual_value)), float(int(expected_value)))
	if definition.value_type == StateVariableDef.ValueType.FLOAT:
		return _matches_numeric(float(actual_value), float(expected_value))
	var is_equal: bool = definition.values_equal(actual_value, expected_value)
	match operator:
		Operator.NOT_EQUALS:
			return not is_equal
		_:
			return is_equal


func get_operator_label() -> String:
	match operator:
		Operator.NOT_EQUALS:
			return "!="
		Operator.GREATER_EQUAL:
			return ">="
		Operator.GREATER_THAN:
			return ">"
		Operator.LESS_THAN:
			return "<"
		Operator.LESS_EQUAL:
			return "<="
		Operator.LIST_HAS:
			return "has"
		Operator.LIST_NOT_HAS:
			return "does not have"
		Operator.COUNT_EQUALS:
			return "count =="
		Operator.COUNT_GREATER_EQUAL:
			return "count >="
		Operator.COUNT_GREATER_THAN:
			return "count >"
		Operator.COUNT_LESS_THAN:
			return "count <"
		Operator.COUNT_LESS_EQUAL:
			return "count <="
		_:
			return "=="


func get_supported_operators(definition: StateVariableDef) -> Array[int]:
	if definition == null:
		return [Operator.EQUALS, Operator.NOT_EQUALS]
	match definition.value_type:
		StateVariableDef.ValueType.INT, StateVariableDef.ValueType.FLOAT:
			return [
				Operator.EQUALS,
				Operator.NOT_EQUALS,
				Operator.GREATER_EQUAL,
				Operator.GREATER_THAN,
				Operator.LESS_THAN,
				Operator.LESS_EQUAL,
			]
		StateVariableDef.ValueType.ENUM:
			return [Operator.EQUALS, Operator.NOT_EQUALS]
		StateVariableDef.ValueType.LIST:
			return [
				Operator.LIST_HAS,
				Operator.LIST_NOT_HAS,
				Operator.COUNT_EQUALS,
				Operator.COUNT_GREATER_EQUAL,
				Operator.COUNT_GREATER_THAN,
				Operator.COUNT_LESS_THAN,
				Operator.COUNT_LESS_EQUAL,
			]
		_:
			return [Operator.EQUALS, Operator.NOT_EQUALS]


func _operator_uses_list_count() -> bool:
	return operator in [
		Operator.COUNT_EQUALS,
		Operator.COUNT_GREATER_EQUAL,
		Operator.COUNT_GREATER_THAN,
		Operator.COUNT_LESS_THAN,
		Operator.COUNT_LESS_EQUAL,
	]


func _matches_numeric(actual: float, expected: float) -> bool:
	match operator:
		Operator.NOT_EQUALS:
			return not is_equal_approx(actual, expected)
		Operator.GREATER_EQUAL, Operator.COUNT_GREATER_EQUAL:
			return actual >= expected
		Operator.GREATER_THAN, Operator.COUNT_GREATER_THAN:
			return actual > expected
		Operator.LESS_THAN, Operator.COUNT_LESS_THAN:
			return actual < expected
		Operator.LESS_EQUAL, Operator.COUNT_LESS_EQUAL:
			return actual <= expected
		_:
			return is_equal_approx(actual, expected)
