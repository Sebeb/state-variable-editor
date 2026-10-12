@tool
extends "../runtime/state_declaring_resource.gd"

@export var amount: int = 3
@export var state_path: StringName = &"test/value"

func _get_state_variable_declarations() -> Array[Dictionary]:
	return [{"property": "amount", "description": "Contract fixture amount"}]
