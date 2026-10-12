@tool
extends Resource
class_name StateVariableChangeDef

const StateVariableDef = preload("state_variable_def.gd")

# Identifies the scene node used for target.
@export var target_path: StringName = &""
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
# Sets the vector3 value used by this component.
@export var vector3_value: Vector3 = Vector3.ZERO


func get_normalized_target_path() -> StringName:
	return StringName(str(target_path).strip_edges().to_lower())


func get_target_value(definition: StateVariableDef) -> Variant:
	if definition == null:
		return null
	match definition.value_type:
		StateVariableDef.ValueType.BOOL:
			return bool_value
		StateVariableDef.ValueType.INT:
			return int_value
		StateVariableDef.ValueType.FLOAT:
			return float_value
		StateVariableDef.ValueType.ENUM, StateVariableDef.ValueType.STRING:
			return string_value
		StateVariableDef.ValueType.ENUM_TOGGLE:
			return string_array_value.duplicate()
		StateVariableDef.ValueType.VECTOR2:
			return vector2_value
		StateVariableDef.ValueType.VECTOR3:
			return vector3_value
		_:
			return string_value


func set_target_value(definition: StateVariableDef, value: Variant) -> void:
	if definition == null:
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
		StateVariableDef.ValueType.ENUM_TOGGLE:
			string_array_value = definition.enum_toggle_values(coerced)
		StateVariableDef.ValueType.VECTOR2:
			vector2_value = coerced as Vector2
		StateVariableDef.ValueType.VECTOR3:
			vector3_value = coerced as Vector3
