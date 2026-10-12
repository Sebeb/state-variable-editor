@tool
extends Resource
class_name StateVariableDef

const StateClaimSlotDef = preload("state_claim_slot_def.gd")
const StateVariableCaseDef = preload("state_variable_case_def.gd")

enum ValueType {
	BOOL,
	INT,
	FLOAT,
	ENUM,
	VECTOR2,
	STRING,
	LIST,
	ENUM_TOGGLE,
	# Appended last on purpose: ValueType is serialised as its integer index in
	# data/state/state_variable_database.tres, so new members must never shift
	# the existing ones.
	VECTOR3,
}

enum Resolver {
	ANY,
	NONE,
	LATEST,
	FIRST,
	ADD,
	MULTIPLY,
	MIN,
	MAX,
	ORDERED,
	# Combines collection contributions without changing the base value's authority.
	# This is intentionally opt-in; existing ENUM_TOGGLE and LIST states retain
	# their LATEST/ORDERED behaviour.
	MERGE,
}

# Selects the path.
## Legacy host preference persistence; modern BASE persistence is independent.
@export var persistent: bool = false

@export var path: StringName = &""
# Explains the variable's purpose when it is highlighted in Logot or inspected in tooling.
@export_multiline var description: String = ""
# Sets the value type used by this component.
@export var value_type: ValueType = ValueType.BOOL
# Sets the resolver used by this component.
@export var resolver: Resolver = Resolver.LATEST
# Sets the default value used by this component.
@export var default_value: Variant = null
# Enables or disables console exposed. Disabled variables still show their default/base/override
# sections in Logot (read-only, inspectable) but skip the editable root command.
@export var console_exposed: bool = true
# Fully excludes this variable from Logot, including default/base/override sections. Reserved for
# performance-sensitive variables (e.g. benchmark probes) that must add zero console overhead.
@export var console_hidden: bool = false
# Provides the possible values configured for this component.
@export var possible_values: Array = []
# Provides the cases configured for this component.
@export var cases: Dictionary = {}
# Provides the claim slots configured for this component.
@export var claim_slots: Array[StateClaimSlotDef] = []
# Assigns declarative lifecycle tags used to query and reset related state.
@export var tags: Array[String] = []
# Sets the graph position used by this component.
@export var graph_position: Vector2 = Vector2.ZERO


func get_normalized_path() -> StringName:
	return StringName(str(path).strip_edges().to_lower())


func get_normalized_tags() -> PackedStringArray:
	var normalized_tags := PackedStringArray()
	for tag in tags:
		var normalized_tag := tag.strip_edges().to_lower()
		if not normalized_tag.is_empty() and not normalized_tags.has(normalized_tag):
			normalized_tags.append(normalized_tag)
	return normalized_tags


func has_tag(tag: String) -> bool:
	return get_normalized_tags().has(tag.strip_edges().to_lower())

func get_group_name() -> String:
	var normalized_path := String(get_normalized_path())
	if normalized_path.is_empty():
		return ""
	return normalized_path.split("/")[0]


func get_leaf_name() -> String:
	var normalized_path := String(get_normalized_path())
	if normalized_path.is_empty():
		return ""
	var parts := normalized_path.split("/")
	return parts[parts.size() - 1]


func get_value_type_name() -> String:
	return ValueType.keys()[value_type].to_lower()


func get_resolver_name() -> String:
	return Resolver.keys()[resolver].to_lower()


func uses_possible_values() -> bool:
	return value_type == ValueType.ENUM or value_type == ValueType.ENUM_TOGGLE


func get_supported_resolvers() -> Array[int]:
	match value_type:
		ValueType.BOOL:
			return [
				Resolver.ORDERED,
				Resolver.ANY,
				Resolver.NONE,
				Resolver.LATEST,
				Resolver.FIRST,
			]
		ValueType.INT, ValueType.FLOAT:
			return [
				Resolver.ORDERED,
				Resolver.ADD,
				Resolver.MULTIPLY,
				Resolver.MIN,
				Resolver.MAX,
				Resolver.LATEST,
				Resolver.FIRST,
			]
		ValueType.ENUM, ValueType.STRING:
			return [
				Resolver.ORDERED,
				Resolver.LATEST,
				Resolver.FIRST,
			]
		ValueType.ENUM_TOGGLE:
			return [
				Resolver.ORDERED,
				Resolver.MERGE,
				Resolver.LATEST,
				Resolver.FIRST,
			]
		ValueType.LIST:
			return [
				Resolver.ORDERED,
				Resolver.MERGE,
				Resolver.LATEST,
				Resolver.FIRST,
			]
		ValueType.VECTOR2, ValueType.VECTOR3:
			return [
				Resolver.ORDERED,
				Resolver.ADD,
				Resolver.MULTIPLY,
				Resolver.LATEST,
				Resolver.FIRST,
			]
		_:
			return [Resolver.LATEST]


func coerce_value(value: Variant) -> Variant:
	match value_type:
		ValueType.BOOL:
			return bool(value)
		ValueType.INT:
			return int(value)
		ValueType.FLOAT:
			return float(value)
		ValueType.ENUM, ValueType.STRING:
			return str(value)
		ValueType.ENUM_TOGGLE:
			return _coerce_enum_toggle_values(value)
		ValueType.LIST:
			if value is Array:
				return (value as Array).duplicate()
			if value == null:
				return []
			return [value]
		ValueType.VECTOR2:
			if value is Vector2:
				return value
			if value is Array and value.size() >= 2:
				return Vector2(float(value[0]), float(value[1]))
			return Vector2.ZERO
		ValueType.VECTOR3:
			if value is Vector3:
				return value
			if value is Array and value.size() >= 3:
				return Vector3(float(value[0]), float(value[1]), float(value[2]))
			# Logot's generic "set this layer" command hands the handler raw
			# console text, so accept the "x,y,z" spelling it produces rather
			# than silently collapsing a typed value to zero.
			if value is String or value is StringName:
				var parts := str(value).replace("(", "").replace(")", "").split(",", false)
				if parts.size() >= 3:
					return Vector3(
						parts[0].strip_edges().to_float(),
						parts[1].strip_edges().to_float(),
						parts[2].strip_edges().to_float()
					)
			return Vector3.ZERO
		_:
			return value


func values_equal(a: Variant, b: Variant) -> bool:
	if value_type == ValueType.LIST:
		return _list_values_equal(a, b)
	return coerce_value(a) == coerce_value(b)


func get_case_key(value: Variant) -> String:
	var coerced: Variant = coerce_value(value)
	match value_type:
		ValueType.BOOL:
			return "true" if bool(coerced) else "false"
		ValueType.INT:
			return str(int(coerced))
		ValueType.FLOAT:
			return str(float(coerced))
		ValueType.ENUM, ValueType.STRING:
			return str(coerced)
		ValueType.ENUM_TOGGLE:
			return JSON.stringify(_enum_toggle_values_to_strings(coerced))
		ValueType.LIST:
			return JSON.stringify(_list_keys_for_value(coerced))
		ValueType.VECTOR2:
			var vector_value := coerced as Vector2
			return JSON.stringify([vector_value.x, vector_value.y])
		ValueType.VECTOR3:
			var vector3_value := coerced as Vector3
			return JSON.stringify([vector3_value.x, vector3_value.y, vector3_value.z])
		_:
			return str(coerced)

func get_value_key(value: Variant) -> String:
	return get_case_key(value)


func get_case_value_from_key(key: String) -> Variant:
	match value_type:
		ValueType.BOOL:
			return key.strip_edges().to_lower() == "true"
		ValueType.INT:
			return int(key)
		ValueType.FLOAT:
			return float(key)
		ValueType.ENUM, ValueType.STRING:
			return key
		ValueType.ENUM_TOGGLE:
			var parsed_toggle: Variant = JSON.parse_string(key)
			if parsed_toggle is Array:
				return _coerce_enum_toggle_values(parsed_toggle)
			return []
		ValueType.LIST:
			var parsed: Variant = JSON.parse_string(key)
			if parsed is Array:
				return parsed.duplicate()
			return []
		ValueType.VECTOR2:
			var parsed: Variant = JSON.parse_string(key)
			if parsed is Array and parsed.size() >= 2:
				return Vector2(float(parsed[0]), float(parsed[1]))
			return Vector2.ZERO
		ValueType.VECTOR3:
			var parsed_vector3: Variant = JSON.parse_string(key)
			if parsed_vector3 is Array and parsed_vector3.size() >= 3:
				return Vector3(float(parsed_vector3[0]), float(parsed_vector3[1]), float(parsed_vector3[2]))
			return Vector3.ZERO
		_:
			return key

func get_value_from_key(key: String) -> Variant:
	return get_case_value_from_key(key)


func get_case_definition(value: Variant) -> StateVariableCaseDef:
	return cases.get(get_case_key(value)) as StateVariableCaseDef


func set_case_definition(value: Variant, case_def: StateVariableCaseDef) -> void:
	cases[get_case_key(value)] = case_def


func remove_case_definition(value: Variant) -> void:
	cases.erase(get_case_key(value))


func rename_case_definition(old_value: Variant, new_value: Variant) -> bool:
	var old_key := get_case_key(old_value)
	var new_key := get_case_key(new_value)
	if old_key == new_key:
		return true
	if not cases.has(old_key) or cases.has(new_key):
		return false
	var case_def: StateVariableCaseDef = cases[old_key] as StateVariableCaseDef
	cases.erase(old_key)
	cases[new_key] = case_def
	return true


func get_case_values_sorted() -> Array[Variant]:
	var keys: Array[String] = []
	for key_variant in cases.keys():
		keys.append(str(key_variant))
	keys.sort_custom(func(a: String, b: String): return describe_value(get_case_value_from_key(a)) < describe_value(get_case_value_from_key(b)))
	var values: Array[Variant] = []
	for key in keys:
		values.append(get_case_value_from_key(key))
	return values


func get_case_definitions() -> Array[StateVariableCaseDef]:
	var results: Array[StateVariableCaseDef] = []
	for key_variant in cases.keys():
		var case_def := cases[key_variant] as StateVariableCaseDef
		if case_def != null:
			results.append(case_def)
	return results


func find_matching_case(value: Variant) -> StateVariableCaseDef:
	return get_case_definition(value)


func get_claim_slot_by_id(slot_id: StringName) -> StateClaimSlotDef:
	var normalized_slot_id := StringName(str(slot_id).strip_edges().to_lower())
	for slot_def in claim_slots:
		if slot_def == null:
			continue
		if slot_def.get_normalized_slot_id() == normalized_slot_id:
			return slot_def
	return null


func get_claim_slot_by_code_key(code_key: StringName) -> StateClaimSlotDef:
	var normalized_code_key := StringName(str(code_key).strip_edges().to_lower())
	for slot_def in claim_slots:
		if slot_def == null:
			continue
		if slot_def.get_normalized_code_key() == normalized_code_key:
			return slot_def
	return null


func get_claim_slot_definitions() -> Array[StateClaimSlotDef]:
	var results: Array[StateClaimSlotDef] = []
	for slot_def in claim_slots:
		if slot_def != null:
			results.append(slot_def)
	return results


func get_console_values() -> Array:
	match value_type:
		ValueType.BOOL:
			return [false, true]
		ValueType.ENUM:
			return possible_values.duplicate()
		ValueType.ENUM_TOGGLE:
			return possible_values.duplicate()
		_:
			return []


func ensure_valid_configuration() -> void:
	path = get_normalized_path()
	var normalized_tags := get_normalized_tags()
	tags.clear()
	for tag in normalized_tags:
		tags.append(tag)
	default_value = coerce_value(default_value)
	if uses_possible_values():
		var normalized_values: Array = []
		var seen: Dictionary = {}
		for raw_value in possible_values:
			var normalized_entries: Array = []
			if value_type == ValueType.ENUM_TOGGLE:
				var raw_entries: Array = []
				if raw_value is Array:
					raw_entries = (raw_value as Array).duplicate()
				else:
					raw_entries = [raw_value]
				for raw_entry in raw_entries:
					var normalized_entry: Variant = _normalize_enum_toggle_option(raw_entry)
					if normalized_entry == null:
						continue
					normalized_entries.append(normalized_entry)
			else:
				normalized_entries = [coerce_value(raw_value)]
			for normalized_value in normalized_entries:
				var value_key := get_case_key(normalized_value)
				if seen.has(value_key):
					continue
				seen[value_key] = true
				normalized_values.append(normalized_value)
		possible_values = normalized_values
		if not possible_values.is_empty():
			var default_key := get_case_key(default_value)
			var has_default := false
			for option_value in possible_values:
				if get_case_key(option_value) == default_key:
					has_default = true
					break
			if not has_default and value_type != ValueType.ENUM_TOGGLE:
				default_value = possible_values[0]
	else:
		possible_values = []
	var supported_resolvers := get_supported_resolvers()
	if not supported_resolvers.has(resolver):
		resolver = supported_resolvers[0] if not supported_resolvers.is_empty() else Resolver.LATEST

	var normalized_claim_slots: Array[StateClaimSlotDef] = []
	var seen_slot_ids: Dictionary = {}
	var fallback_index := 0
	for slot_def in claim_slots:
		if slot_def == null:
			continue
		slot_def.ensure_valid_configuration(StringName("%s_slot_%d" % [get_leaf_name(), fallback_index]))
		fallback_index += 1
		var normalized_slot_id := slot_def.get_normalized_slot_id()
		if normalized_slot_id == &"" or seen_slot_ids.has(normalized_slot_id):
			continue
		seen_slot_ids[normalized_slot_id] = true
		normalized_claim_slots.append(slot_def)
	claim_slots = normalized_claim_slots

	var normalized_cases: Dictionary = {}
	for raw_key in cases.keys():
		var case_def := cases[raw_key] as StateVariableCaseDef
		if case_def == null:
			continue
		var normalized_key := get_case_key(get_case_value_from_key(str(raw_key)))
		if normalized_cases.has(normalized_key):
			continue
		normalized_cases[normalized_key] = case_def
	cases = normalized_cases


func describe_value(value: Variant) -> String:
	var coerced: Variant = coerce_value(value)
	if value_type == ValueType.ENUM_TOGGLE:
		return "[%s]" % ", ".join(_enum_toggle_values_to_strings(coerced))
	if value_type == ValueType.LIST:
		return "[%s]" % ", ".join(_list_keys_for_value(coerced))
	if coerced is String:
		return coerced
	return str(coerced)


func get_list_item_key(value: Variant) -> StringName:
	if value == null:
		return &""
	if value is StringName:
		return StringName(str(value).strip_edges().to_lower())
	if value is String:
		return StringName((value as String).strip_edges().to_lower())
	if value is Object:
		var object_value := value as Object
		if object_value.has_method("get_state_variable_item_key"):
			return StringName(str(object_value.call("get_state_variable_item_key")).strip_edges().to_lower())
	return StringName(str(value).strip_edges().to_lower())


func enum_toggle_count(value: Variant) -> int:
	return _coerce_enum_toggle_values(value).size()


func enum_toggle_values(value: Variant) -> Array[String]:
	return _enum_toggle_values_to_strings(_coerce_enum_toggle_values(value))


func enum_toggle_has_option(value: Variant, option: Variant) -> bool:
	var normalized_option := String(_normalize_enum_toggle_option(option))
	if normalized_option.is_empty():
		return false
	for existing_option in _coerce_enum_toggle_values(value):
		if str(existing_option) == normalized_option:
			return true
	return false


func enum_toggle_set_option_enabled(value: Variant, option: Variant, enabled: bool) -> Array:
	var normalized_values: Array = _coerce_enum_toggle_values(value)
	var normalized_option: Variant = _normalize_enum_toggle_option(option)
	if normalized_option == null:
		return normalized_values
	var next_values: Array = []
	var had_option := false
	for existing_option in normalized_values:
		if str(existing_option) == str(normalized_option):
			had_option = true
			if enabled:
				next_values.append(existing_option)
			continue
		next_values.append(existing_option)
	if enabled and not had_option:
		next_values.append(normalized_option)
	return _coerce_enum_toggle_values(next_values)


func list_has_item_key(list_value: Variant, expected_key: Variant) -> bool:
	var normalized_expected := get_list_item_key(expected_key)
	if normalized_expected == &"":
		return false
	for entry in coerce_value(list_value):
		if get_list_item_key(entry) == normalized_expected:
			return true
	return false


func list_count(value: Variant) -> int:
	return coerce_value(value).size()


func list_keys(value: Variant) -> Array[String]:
	return _list_keys_for_value(value)


func _list_values_equal(a: Variant, b: Variant) -> bool:
	var coerced_a: Array = coerce_value(a)
	var coerced_b: Array = coerce_value(b)
	if coerced_a.size() != coerced_b.size():
		return false
	for index in range(coerced_a.size()):
		var item_a: Variant = coerced_a[index]
		var item_b: Variant = coerced_b[index]
		if get_list_item_key(item_a) != get_list_item_key(item_b):
			return false
		if item_a != item_b:
			return false
	return true


func _coerce_enum_toggle_values(value: Variant) -> Array:
	var requested_values: Array = []
	if value is Array:
		requested_values = (value as Array).duplicate()
	elif value == null:
		requested_values = []
	else:
		requested_values = [value]
	var allowed_by_key: Dictionary = {}
	var ordered_allowed: Array = []
	for raw_option in possible_values:
		var normalized_option: Variant = _normalize_enum_toggle_option(raw_option)
		if normalized_option == null:
			continue
		var option_key := String(normalized_option)
		if allowed_by_key.has(option_key):
			continue
		allowed_by_key[option_key] = normalized_option
		ordered_allowed.append(normalized_option)
	var seen: Dictionary = {}
	var normalized_requested: Array = []
	for raw_value in requested_values:
		var normalized_value: Variant = _normalize_enum_toggle_option(raw_value)
		if normalized_value == null:
			continue
		var value_key := String(normalized_value)
		if not allowed_by_key.is_empty():
			if not allowed_by_key.has(value_key):
				continue
			normalized_value = allowed_by_key[value_key]
		if seen.has(value_key):
			continue
		seen[value_key] = true
		normalized_requested.append(normalized_value)
	if allowed_by_key.is_empty():
		return normalized_requested
	var ordered_result: Array = []
	for allowed_value in ordered_allowed:
		var allowed_key := String(allowed_value)
		if seen.has(allowed_key):
			ordered_result.append(allowed_value)
	return ordered_result


func _normalize_enum_toggle_option(value: Variant) -> Variant:
	if value == null:
		return null
	var normalized_value: Variant = coerce_enum_toggle_option(value)
	if normalized_value == null:
		return null
	return normalized_value


func coerce_enum_toggle_option(value: Variant) -> Variant:
	if value == null:
		return null
	return str(value).strip_edges().to_lower()


func _enum_toggle_values_to_strings(value: Variant) -> Array[String]:
	var values: Array[String] = []
	for option in _coerce_enum_toggle_values(value):
		values.append(str(option))
	return values


func _list_keys_for_value(value: Variant) -> Array[String]:
	var keys: Array[String] = []
	for entry in coerce_value(value):
		keys.append(String(get_list_item_key(entry)))
	return keys
