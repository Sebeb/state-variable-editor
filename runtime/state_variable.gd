extends RefCounted
class_name StateVariable

const StateClaim = preload("state_claim.gd")
const StateVariableDef = preload("state_variable_def.gd")
const StateValueResolution = preload("state_value_resolution.gd")

signal claims_changed(variable_path: StringName)
signal claim_membership_changed(variable_path: StringName)
signal resolved_value_changed(variable_path: StringName, old_value: Variant, new_value: Variant)
signal default_value_changed(variable_path: StringName, old_value: Variant, new_value: Variant)
signal base_value_changed(variable_path: StringName, has_value: bool, value: Variant)
signal override_changed(variable_path: StringName, overridden: bool, value: Variant)
signal console_display_changed(variable_path: StringName)

var definition: StateVariableDef
var claims: Array[StateClaim] = []
var resolved_value: Variant = null

var _next_claim_id: int = 1
var _next_claim_serial: int = 1
var _base_enabled := false
var _base_value: Variant = null
var _override_enabled := false
var _override_value: Variant = null
var _claim_ids_by_code_key: Dictionary = {}
var _code_keys_by_claim_id: Dictionary = {}
var _last_non_empty_enum_toggle_value: Array = []
var _change_batch_depth := 0
var _change_batch_initial: Dictionary = {}
var last_resolution_error := ""


func _init(variable_definition: StateVariableDef) -> void:
	definition = variable_definition
	var default_claim := StateClaim.new(0, definition.coerce_value(definition.default_value), true)
	claims = [default_claim]
	resolved_value = _resolve_value()
	_remember_enum_toggle_value(default_claim.value)
	_remember_enum_toggle_value(resolved_value)


func get_path() -> StringName:
	return definition.get_normalized_path()


func get_default_value() -> Variant:
	return claims[0].value


func has_base_value() -> bool:
	return _base_enabled


func get_base_value() -> Variant:
	return _base_value if _base_enabled else null


func get_effective_bottom_value() -> Variant:
	return _base_value if _base_enabled else get_default_value()


func begin_change_batch() -> void:
	if _change_batch_depth == 0:
		_change_batch_initial = _capture_change_state()
	_change_batch_depth += 1


func end_change_batch() -> void:
	if _change_batch_depth <= 0:
		return
	_change_batch_depth -= 1
	if _change_batch_depth > 0:
		return
	var initial := _change_batch_initial
	_change_batch_initial = {}
	_emit_changes_from(initial)


func get_pending_change_summary() -> Dictionary:
	if _change_batch_depth <= 0 or _change_batch_initial.is_empty():
		return {}
	return _build_change_summary(_change_batch_initial, _capture_change_state())


func set_default_value(value: Variant) -> bool:
	var before := _capture_change_state()
	var coerced: Variant = definition.coerce_value(value)
	if definition.values_equal(claims[0].value, coerced):
		return false
	claims[0].value = coerced
	if _base_enabled and definition.values_equal(_base_value, coerced):
		_base_enabled = false
		_base_value = null
	resolved_value = _resolve_value()
	_remember_enum_toggle_value(coerced)
	_remember_enum_toggle_value(resolved_value)
	_finish_change(before)
	return true


func set_base_value(value: Variant) -> bool:
	var coerced: Variant = definition.coerce_value(value)
	if definition.values_equal(coerced, get_default_value()):
		return clear_base()
	if _base_enabled and definition.values_equal(_base_value, coerced):
		return false
	var before := _capture_change_state()
	_base_enabled = true
	_base_value = coerced
	resolved_value = _resolve_value()
	_remember_enum_toggle_value(coerced)
	_remember_enum_toggle_value(resolved_value)
	_finish_change(before)
	return true


func clear_base() -> bool:
	if not _base_enabled:
		return false
	var before := _capture_change_state()
	_base_enabled = false
	_base_value = null
	resolved_value = _resolve_value()
	_remember_enum_toggle_value(resolved_value)
	_finish_change(before)
	return true


func add_claim(value: Variant) -> int:
	var resolved_input := _resolve_claim_input(value)
	if not bool(resolved_input.get("ok", false)):
		return -1
	var before := _capture_change_state()
	var claim_id: int = _next_claim_id
	_next_claim_id += 1
	var claim := StateClaim.new(claim_id, resolved_input.get("value"), false, _next_claim_serial)
	_next_claim_serial += 1
	claims.append(claim)
	resolved_value = _resolve_value()
	_remember_enum_toggle_value(claim.value)
	_remember_enum_toggle_value(resolved_value)
	_finish_change(before)
	return claim_id


func set_claim(code_key: StringName, value: Variant) -> bool:
	var normalized_code_key := StringName(str(code_key).strip_edges().to_lower())
	if normalized_code_key == &"":
		return false
	var resolved_input := _resolve_claim_input(value)
	if not bool(resolved_input.get("ok", false)):
		return false
	var coerced_value: Variant = resolved_input.get("value")
	var existing_claim_id := int(_claim_ids_by_code_key.get(normalized_code_key, -1))
	if existing_claim_id > 0:
		for claim_index in range(claims.size()):
			var claim := claims[claim_index]
			if claim.claim_id != existing_claim_id:
				continue
			if definition.values_equal(claim.value, coerced_value):
				return false
			var before := _capture_change_state()
			claim.value = coerced_value
			claim.muted = false
			claim.update_serial = _next_claim_serial
			_next_claim_serial += 1
			# A keyed claim keeps its identity, while an update still counts as the
			# latest contribution for ordered/latest resolution.
			if claim_index != claims.size() - 1:
				claims.remove_at(claim_index)
				claims.append(claim)
			resolved_value = _resolve_value()
			_remember_enum_toggle_value(claim.value)
			_remember_enum_toggle_value(resolved_value)
			_finish_change(before)
			return true
	var before := _capture_change_state()
	var claim_id: int = _next_claim_id
	_next_claim_id += 1
	var claim := StateClaim.new(claim_id, coerced_value, false, _next_claim_serial)
	_next_claim_serial += 1
	claims.append(claim)
	_claim_ids_by_code_key[normalized_code_key] = claim_id
	_code_keys_by_claim_id[claim_id] = normalized_code_key
	resolved_value = _resolve_value()
	_remember_enum_toggle_value(claim.value)
	_remember_enum_toggle_value(resolved_value)
	_finish_change(before)
	return true


func mute_claim(target: Variant) -> bool:
	return _set_claim_muted(target, true)


func unmute_claim(target: Variant) -> bool:
	return _set_claim_muted(target, false)


func mute_all_claims() -> int:
	return _set_all_claims_muted(true)


func unmute_all_claims() -> int:
	return _set_all_claims_muted(false)


func _set_claim_muted(target: Variant, muted: bool) -> bool:
	var claim: StateClaim = null
	if target is String or target is StringName:
		claim = _get_keyed_claim(StringName(str(target).strip_edges().to_lower()))
	else:
		claim = _get_claim_by_id(int(target))
	if claim == null or claim.muted == muted:
		return false
	var before := _capture_change_state()
	claim.muted = muted
	claim.update_serial = _next_claim_serial
	_next_claim_serial += 1
	resolved_value = _resolve_value()
	_remember_enum_toggle_value(resolved_value)
	_finish_change(before)
	return true


func _set_all_claims_muted(muted: bool) -> int:
	var changed_claims: Array[StateClaim] = []
	for claim in claims.slice(1):
		if claim.muted != muted:
			changed_claims.append(claim)
	if changed_claims.is_empty():
		return 0
	var before := _capture_change_state()
	for claim in changed_claims:
		claim.muted = muted
		claim.update_serial = _next_claim_serial
		_next_claim_serial += 1
	resolved_value = _resolve_value()
	_remember_enum_toggle_value(resolved_value)
	_finish_change(before)
	return changed_claims.size()


func clear_claim(code_key: StringName) -> bool:
	var normalized_code_key := StringName(str(code_key).strip_edges().to_lower())
	var existing_claim_id := int(_claim_ids_by_code_key.get(normalized_code_key, -1))
	if existing_claim_id <= 0:
		return false
	_claim_ids_by_code_key.erase(normalized_code_key)
	_code_keys_by_claim_id.erase(existing_claim_id)
	return remove_claim(existing_claim_id)


func remove_claim(claim_id: int) -> bool:
	if claim_id <= 0:
		return false
	for idx in range(1, claims.size()):
		if claims[idx].claim_id != claim_id:
			continue
		var before := _capture_change_state()
		claims.remove_at(idx)
		for key in _claim_ids_by_code_key.keys():
			if int(_claim_ids_by_code_key[key]) == claim_id:
				_claim_ids_by_code_key.erase(key)
				break
		_code_keys_by_claim_id.erase(claim_id)
		resolved_value = _resolve_value()
		_remember_enum_toggle_value(resolved_value)
		_finish_change(before)
		return true
	return false


func reset() -> bool:
	if claims.size() <= 1 and not _base_enabled:
		return false
	var before := _capture_change_state()
	claims.resize(1)
	_base_enabled = false
	_base_value = null
	_claim_ids_by_code_key.clear()
	_code_keys_by_claim_id.clear()
	resolved_value = _resolve_value()
	_remember_enum_toggle_value(resolved_value)
	_finish_change(before)
	return true

func _get_keyed_claim(code_key: StringName) -> StateClaim:
	return _get_claim_by_id(int(_claim_ids_by_code_key.get(code_key, -1)))


func _get_claim_by_id(claim_id: int) -> StateClaim:
	if claim_id <= 0:
		return null
	for claim in claims:
		if claim.claim_id == claim_id:
			return claim
	return null


func get_claim_value(code_key: StringName, fallback: Variant = null) -> Variant:
	var normalized_code_key := StringName(str(code_key).strip_edges().to_lower())
	var claim := _get_keyed_claim(normalized_code_key)
	return claim.value if claim != null else fallback


func add_list_item(owner_key: StringName, value: Variant) -> bool:
	if definition.value_type != StateVariableDef.ValueType.LIST:
		return false
	var next_list: Array = definition.coerce_value(get_claim_value(owner_key, []))
	var normalized_key := definition.get_list_item_key(value)
	if normalized_key == &"":
		return false
	var replaced := false
	for index in range(next_list.size()):
		if definition.get_list_item_key(next_list[index]) != normalized_key:
			continue
		if next_list[index] == value:
			return false
		next_list[index] = value
		replaced = true
		break
	if not replaced:
		next_list.append(value)
	_apply_list_value(owner_key, next_list)
	return true


func remove_list_item(owner_key: StringName, value_or_key: Variant) -> bool:
	if definition.value_type != StateVariableDef.ValueType.LIST:
		return false
	var next_list: Array = definition.coerce_value(get_claim_value(owner_key, []))
	var normalized_key := definition.get_list_item_key(value_or_key)
	if normalized_key == &"":
		return false
	for index in range(next_list.size()):
		if definition.get_list_item_key(next_list[index]) != normalized_key:
			continue
		next_list.remove_at(index)
		_apply_list_value(owner_key, next_list)
		return true
	return false


func clear_list_items(owner_key: StringName) -> bool:
	if definition.value_type != StateVariableDef.ValueType.LIST:
		return false
	return clear_claim(owner_key)


func get_last_non_empty_enum_toggle_value() -> Array:
	if definition.value_type != StateVariableDef.ValueType.ENUM_TOGGLE:
		return []
	return (_last_non_empty_enum_toggle_value as Array).duplicate()


func has_override() -> bool:
	return _override_enabled


func get_override_value() -> Variant:
	return _override_value if _override_enabled else null


func set_override(value: Variant) -> bool:
	var coerced: Variant = definition.coerce_value(value)
	if _override_enabled and definition.values_equal(_override_value, coerced):
		return false
	var before := _capture_change_state()
	_override_enabled = true
	_override_value = coerced
	resolved_value = _resolve_value()
	_remember_enum_toggle_value(_override_value)
	_remember_enum_toggle_value(resolved_value)
	_finish_change(before)
	return true


func clear_override() -> bool:
	if not _override_enabled:
		return false
	var before := _capture_change_state()
	_override_enabled = false
	_override_value = null
	resolved_value = _resolve_value()
	_remember_enum_toggle_value(resolved_value)
	_finish_change(before)
	return true


func get_options() -> Variant:
	match definition.value_type:
		StateVariableDef.ValueType.BOOL:
			return [false, true]
		StateVariableDef.ValueType.ENUM, StateVariableDef.ValueType.ENUM_TOGGLE:
			return definition.possible_values.duplicate()
		_:
			return null


func set_possible_values(values: Array) -> bool:
	if not definition.uses_possible_values():
		return false
	var normalized: Array = []
	for value in values:
		var coerced: Variant = definition.coerce_value(value)
		if not normalized.has(coerced):
			normalized.append(coerced)
	if definition.possible_values == normalized:
		return false
	definition.possible_values = normalized
	console_display_changed.emit(get_path())
	return true


func describe_claims() -> String:
	var segments: Array[String] = []
	for claim in claims:
		segments.append(_describe_claim_value(claim))
	return " -> ".join(segments)


func get_claim_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	if claims.size() <= 1:
		return snapshots
	var contributing_ids := _get_contributing_claim_ids()
	var snapshot_claims: Array[StateClaim] = claims.slice(1)
	match definition.resolver:
		StateVariableDef.Resolver.LATEST:
			snapshot_claims.reverse()
		StateVariableDef.Resolver.ORDERED:
			snapshot_claims.sort_custom(_claim_precedes_for_ordered_snapshot)
		_:
			pass
	for idx in range(snapshot_claims.size()):
		var claim: StateClaim = snapshot_claims[idx]
		var code_key := String(_code_keys_by_claim_id.get(claim.claim_id, &""))
		var contributes := contributing_ids.has(claim.claim_id)
		snapshots.append({
			"slot_id": "claim_%d" % claim.claim_id,
			"code_key": code_key,
			"transition_id": 0,
			"value": _serialize_snapshot_value(claim.value),
			"active": true,
			"muted": claim.muted,
			"contributes_to_resolution": contributes,
			"suppressed_by_resolution": not contributes and not claim.muted,
			"activation_serial": claim.activation_serial,
			"update_serial": claim.update_serial,
			"display_order": idx,
		})
	return snapshots


func _claim_precedes_for_ordered_snapshot(a: StateClaim, b: StateClaim) -> bool:
	var a_priority := _ordered_claim_priority(StringName(_code_keys_by_claim_id.get(a.claim_id, &"")))
	var b_priority := _ordered_claim_priority(StringName(_code_keys_by_claim_id.get(b.claim_id, &"")))
	if a_priority != b_priority:
		return a_priority > b_priority
	return a.activation_serial < b.activation_serial


func _enabled_claims() -> Array[StateClaim]:
	var enabled: Array[StateClaim] = []
	for claim in claims.slice(1):
		if not claim.muted:
			enabled.append(claim)
	return enabled


func _resolution_values() -> Array:
	var values: Array = [get_effective_bottom_value()]
	for claim in _enabled_claims():
		values.append(claim.value)
	return values


func _resolve_value() -> Variant:
	if _override_enabled:
		return _override_value
	var enabled_claims := _enabled_claims()
	var values := _resolution_values()
	match definition.resolver:
		StateVariableDef.Resolver.ANY:
			return _resolve_bool_any(values)
		StateVariableDef.Resolver.NONE:
			return _resolve_bool_none(values)
		StateVariableDef.Resolver.LATEST:
			return enabled_claims[enabled_claims.size() - 1].value if not enabled_claims.is_empty() else get_effective_bottom_value()
		StateVariableDef.Resolver.FIRST:
			return enabled_claims[0].value if not enabled_claims.is_empty() else get_effective_bottom_value()
		StateVariableDef.Resolver.ADD:
			return _resolve_add(values)
		StateVariableDef.Resolver.MULTIPLY:
			return _resolve_multiply(values)
		StateVariableDef.Resolver.MIN:
			return _resolve_min(values)
		StateVariableDef.Resolver.MAX:
			return _resolve_max(values)
		StateVariableDef.Resolver.ORDERED:
			return _resolve_ordered(enabled_claims)
		StateVariableDef.Resolver.MERGE:
			return _resolve_merge(values)
		_:
			return enabled_claims[enabled_claims.size() - 1].value if not enabled_claims.is_empty() else get_effective_bottom_value()


func _resolve_claim_input(value: Variant) -> Dictionary:
	last_resolution_error = ""
	var result := StateValueResolution.evaluate(value, definition, get_effective_bottom_value())
	if bool(result.get("ok", false)):
		return result
	last_resolution_error = str(result.get("error", "Custom state value resolution failed."))
	return result


func _resolve_bool_any(values: Array) -> bool:
	for value in values:
		if bool(value):
			return true
	return false


func _resolve_bool_none(values: Array) -> bool:
	for value in values:
		if not bool(value):
			return false
	return true


func _resolve_add(values: Array) -> Variant:
	match definition.value_type:
		StateVariableDef.ValueType.INT:
			var total_int := 0
			for value in values:
				total_int += int(value)
			return total_int
		StateVariableDef.ValueType.FLOAT:
			var total_float := 0.0
			for value in values:
				total_float += float(value)
			return total_float
		StateVariableDef.ValueType.VECTOR2:
			var total_vec := Vector2.ZERO
			for value in values:
				total_vec += value as Vector2
			return total_vec
		StateVariableDef.ValueType.VECTOR3:
			var total_vec3 := Vector3.ZERO
			for value in values:
				total_vec3 += value as Vector3
			return total_vec3
		_:
			return values[values.size() - 1]


func _resolve_multiply(values: Array) -> Variant:
	match definition.value_type:
		StateVariableDef.ValueType.INT:
			var product_int := 1
			for value in values:
				product_int *= int(value)
			return product_int
		StateVariableDef.ValueType.FLOAT:
			var product_float := 1.0
			for value in values:
				product_float *= float(value)
			return product_float
		StateVariableDef.ValueType.VECTOR2:
			var product_vec := Vector2.ONE
			for value in values:
				product_vec *= value as Vector2
			return product_vec
		StateVariableDef.ValueType.VECTOR3:
			var product_vec3 := Vector3.ONE
			for value in values:
				product_vec3 *= value as Vector3
			return product_vec3
		_:
			return values[values.size() - 1]


func _resolve_min(values: Array) -> Variant:
	if values.is_empty():
		return definition.default_value
	match definition.value_type:
		StateVariableDef.ValueType.INT:
			var current_int := int(values[0])
			for idx in range(1, values.size()):
				current_int = mini(current_int, int(values[idx]))
			return current_int
		StateVariableDef.ValueType.FLOAT:
			var current_float := float(values[0])
			for idx in range(1, values.size()):
				current_float = minf(current_float, float(values[idx]))
			return current_float
		_:
			return values[values.size() - 1]


func _resolve_max(values: Array) -> Variant:
	if values.is_empty():
		return definition.default_value
	match definition.value_type:
		StateVariableDef.ValueType.INT:
			var current_int := int(values[0])
			for idx in range(1, values.size()):
				current_int = maxi(current_int, int(values[idx]))
			return current_int
		StateVariableDef.ValueType.FLOAT:
			var current_float := float(values[0])
			for idx in range(1, values.size()):
				current_float = maxf(current_float, float(values[idx]))
			return current_float
		_:
			return values[values.size() - 1]


func _resolve_merge(values: Array) -> Variant:
	match definition.value_type:
		StateVariableDef.ValueType.ENUM_TOGGLE:
			var merged_toggle: Array = []
			for value in values:
				for option in definition.coerce_value(value):
					if not merged_toggle.has(option):
						merged_toggle.append(option)
			return definition.coerce_value(merged_toggle)
		StateVariableDef.ValueType.LIST:
			var merged_list: Array = []
			for value in values:
				for item in definition.coerce_value(value):
					var item_key := definition.get_list_item_key(item)
					if item_key == &"":
						continue
					var existing_index := -1
					for index in range(merged_list.size()):
						if definition.get_list_item_key(merged_list[index]) == item_key:
							existing_index = index
							break
					if existing_index < 0:
						merged_list.append(item)
			return merged_list
		_:
			return values[values.size() - 1]


func _get_contributing_claim_ids() -> Dictionary:
	var contributing: Dictionary = {}
	if _override_enabled or claims.size() <= 1:
		return contributing
	var enabled := _enabled_claims()
	if enabled.is_empty():
		return contributing
	match definition.resolver:
		StateVariableDef.Resolver.LATEST:
			contributing[enabled[enabled.size() - 1].claim_id] = true
		StateVariableDef.Resolver.FIRST:
			contributing[enabled[0].claim_id] = true
		StateVariableDef.Resolver.ANY:
			for claim in enabled:
				if bool(claim.value):
					contributing[claim.claim_id] = true
		StateVariableDef.Resolver.NONE:
			for claim in enabled:
				if not bool(claim.value):
					contributing[claim.claim_id] = true
		StateVariableDef.Resolver.ORDERED:
			var winner := _ordered_winning_claim(enabled)
			if winner != null:
				contributing[winner.claim_id] = true
		_:
			for claim in enabled:
				contributing[claim.claim_id] = true
	return contributing


func _serialize_snapshot_value(value: Variant) -> Variant:
	if definition.value_type == StateVariableDef.ValueType.LIST:
		return definition.list_keys(value)
	if definition.value_type == StateVariableDef.ValueType.ENUM_TOGGLE:
		return definition.enum_toggle_values(value)
	return value


func _describe_claim_value(claim: StateClaim) -> String:
	var value_text := definition.describe_value(claim.value)
	if claim.claim_id == 0:
		return "[default] %s" % value_text
	return "#%d %s" % [claim.claim_id, value_text]


func _resolve_ordered(enabled_claims: Array[StateClaim]) -> Variant:
	var winning_claim := _ordered_winning_claim(enabled_claims)
	return winning_claim.value if winning_claim != null else get_effective_bottom_value()


func _ordered_winning_claim(enabled_claims: Array[StateClaim]) -> StateClaim:
	var winning_claim: StateClaim = null
	var winning_priority := -1
	for claim in enabled_claims:
		var code_key := StringName(_code_keys_by_claim_id.get(claim.claim_id, &""))
		var priority := _ordered_claim_priority(code_key)
		if winning_claim == null or priority >= winning_priority:
			winning_claim = claim
			winning_priority = priority
	return winning_claim


func _ordered_claim_priority(code_key: StringName) -> int:
	var normalized_code_key := String(code_key).strip_edges().to_lower()
	for index in range(definition.claim_slots.size()):
		var slot := definition.claim_slots[index]
		if slot == null:
			continue
		var slot_code_key := String(slot.get_normalized_code_key())
		var slot_id := String(slot.get_normalized_slot_id())
		if normalized_code_key == slot_code_key or normalized_code_key.ends_with("/%s" % slot_id):
			return index
	return -1


func _apply_list_value(owner_key: StringName, next_list: Array) -> void:
	if next_list.is_empty():
		clear_claim(owner_key)
	else:
		set_claim(owner_key, next_list)


func _remember_enum_toggle_value(value: Variant) -> void:
	if definition.value_type != StateVariableDef.ValueType.ENUM_TOGGLE:
		return
	var normalized_value: Array = definition.coerce_value(value)
	if normalized_value.is_empty():
		return
	_last_non_empty_enum_toggle_value = normalized_value.duplicate()


func _finish_change(before: Dictionary) -> void:
	if _change_batch_depth > 0:
		return
	_emit_changes_from(before)


func _capture_change_state() -> Dictionary:
	return {
		"default_value": _duplicate_variant(get_default_value()),
		"has_base_value": has_base_value(),
		"base_value": _duplicate_variant(get_base_value()),
		"resolved_value": _duplicate_variant(resolved_value),
		"override_enabled": _override_enabled,
		"override_value": _duplicate_variant(_override_value),
		"claims_fingerprint": _claims_fingerprint(true),
		"claim_membership_fingerprint": _claims_fingerprint(false),
	}


func _build_change_summary(before: Dictionary, after: Dictionary) -> Dictionary:
	var default_changed := not definition.values_equal(before.get("default_value"), after.get("default_value"))
	var base_membership_changed := bool(before.get("has_base_value", false)) != bool(after.get("has_base_value", false))
	var base_value_changed_value := false
	if not base_membership_changed and bool(after.get("has_base_value", false)):
		base_value_changed_value = not definition.values_equal(before.get("base_value"), after.get("base_value"))
	var base_changed := base_membership_changed or base_value_changed_value
	var resolved_changed := not definition.values_equal(before.get("resolved_value"), after.get("resolved_value"))
	var override_membership_changed := bool(before.get("override_enabled", false)) != bool(after.get("override_enabled", false))
	var override_value_changed := false
	if not override_membership_changed and bool(after.get("override_enabled", false)):
		override_value_changed = not definition.values_equal(before.get("override_value"), after.get("override_value"))
	var override_changed_value := override_membership_changed or override_value_changed
	var claims_changed_value := str(before.get("claims_fingerprint", "")) != str(after.get("claims_fingerprint", ""))
	var membership_changed := str(before.get("claim_membership_fingerprint", "")) != str(after.get("claim_membership_fingerprint", ""))
	return {
		"changed": default_changed or base_changed or resolved_changed or override_changed_value or claims_changed_value,
		"default_changed": default_changed,
		"base_changed": base_changed,
		"has_base_value": bool(after.get("has_base_value", false)),
		"new_base_value": after.get("base_value"),
		"resolved_changed": resolved_changed,
		"override_changed": override_changed_value,
		"override_membership_changed": override_membership_changed,
		"override_value_changed": override_value_changed,
		"claims_changed": claims_changed_value,
		"claim_membership_changed": membership_changed,
		"old_default": before.get("default_value"),
		"new_default": after.get("default_value"),
		"old_resolved": before.get("resolved_value"),
		"new_resolved": after.get("resolved_value"),
	}


func _emit_changes_from(before: Dictionary) -> void:
	if before.is_empty():
		return
	var after := _capture_change_state()
	var summary := _build_change_summary(before, after)
	if not bool(summary.get("changed", false)):
		return
	var path := get_path()
	if bool(summary.get("default_changed", false)):
		default_value_changed.emit(path, summary.get("old_default"), summary.get("new_default"))
	if bool(summary.get("base_changed", false)):
		base_value_changed.emit(path, bool(summary.get("has_base_value", false)), summary.get("new_base_value"))
	if bool(summary.get("override_changed", false)):
		override_changed.emit(path, _override_enabled, _duplicate_variant(_override_value) if _override_enabled else null)
	if bool(summary.get("claim_membership_changed", false)):
		claim_membership_changed.emit(path)
	if bool(summary.get("claims_changed", false)):
		claims_changed.emit(path)
	if bool(summary.get("resolved_changed", false)):
		resolved_value_changed.emit(path, summary.get("old_resolved"), summary.get("new_resolved"))
	console_display_changed.emit(path)


func _claims_fingerprint(include_values: bool) -> String:
	var parts: Array = []
	for claim in claims:
		var part := {
			"claim_id": claim.claim_id,
			"code_key": String(_code_keys_by_claim_id.get(claim.claim_id, &"")),
			"default": claim.is_default,
			"muted": claim.muted,
			"activation_serial": claim.activation_serial,
			"update_serial": claim.update_serial,
		}
		if include_values:
			part["value"] = _serialize_snapshot_value(claim.value)
		parts.append(part)
	if not include_values:
		parts.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("claim_id", -1)) < int(b.get("claim_id", -1)))
	return var_to_str(parts)


func _duplicate_variant(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value


func set_claim_value(code_key: StringName, value: Variant) -> bool:
	return set_claim(code_key, value)

func set_current_value(value: Variant) -> int:
	begin_change_batch()
	for claim in claims.duplicate():
		if claim.claim_id != 0:
			remove_claim(claim.claim_id)
	var claim_id := add_claim(value)
	end_change_batch()
	return claim_id
