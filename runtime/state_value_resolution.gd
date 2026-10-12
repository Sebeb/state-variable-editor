class_name StateValueResolution
extends RefCounted

## Evaluates author-authored state claim expressions. A value is code only when
## it starts with `=`, leaving ordinary string and enum values untouched.


static func is_custom_code(value: Variant) -> bool:
	return value is String and (value as String).strip_edges().begins_with("=")


static func evaluate(value: Variant, definition: StateVariableDef, base_value: Variant) -> Dictionary:
	if not is_custom_code(value):
		return {"ok": true, "value": value}
	if definition == null:
		return {"ok": false, "error": "A custom state value needs a state definition."}
	var source := (value as String).strip_edges().trim_prefix("=").strip_edges()
	if source.is_empty():
		return {"ok": false, "error": "Custom state value code is empty."}
	var expression := Expression.new()
	if expression.parse(source) != OK:
		return {"ok": false, "error": expression.get_error_text()}
	var context := _ResolutionContext.new(definition, base_value)
	var result: Variant = expression.execute([], context)
	if expression.has_execute_failed():
		return {"ok": false, "error": expression.get_error_text()}
	if definition.value_type == StateVariableDef.ValueType.ENUM and not definition.possible_values.has(result):
		return {"ok": false, "error": "Custom state value must resolve to one of the enum's possible values."}
	return {"ok": true, "value": definition.coerce_value(result)}


class _ResolutionContext extends RefCounted:
	var possible_values: Array = []
	var base_value: Variant = null
	var _rng := RandomNumberGenerator.new()

	func _init(definition: StateVariableDef, base: Variant) -> void:
		possible_values = definition.possible_values.duplicate()
		base_value = definition.coerce_value(base)
		_rng.randomize()

	func random_enum_excluding_default() -> Variant:
		return random_enum_excluding_base()

	func random_enum_excluding_base() -> Variant:
		var candidates: Array = []
		for option in possible_values:
			if option != base_value:
				candidates.append(option)
		if candidates.is_empty():
			return null
		return candidates[_rng.randi_range(0, candidates.size() - 1)]
