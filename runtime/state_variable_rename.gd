@tool
extends RefCounted
class_name StateVariableRename

## Pure planning/apply helper for state-variable renames. Persistence belongs to
## the editor snapshot boundary so callers can include pill resources in undo.

static func plan(states: Array, transitions: Array, bindings: Dictionary, old_path: String, new_path: String) -> Dictionary:
	var old_normalized := _normalize(old_path)
	var new_normalized := _normalize(new_path)
	var result := _result(old_normalized, new_normalized)
	if not _is_valid_path(new_normalized):
		return _failure(result, "invalid_path", "State paths must use non-empty lowercase a-z, 0-9, _ and / segments.")
	if old_normalized == new_normalized:
		result.reason = "no_op"
		result.diagnostic = "The state path is unchanged."
		return result

	var source_index := -1
	for index in range(states.size()):
		var state_def := states[index] as StateVariableDef
		if state_def == null:
			continue
		var candidate := String(state_def.get_normalized_path())
		if candidate == old_normalized:
			source_index = index
		elif candidate == new_normalized:
			return _failure(result, "path_collision", "A state already uses '%s'." % new_normalized)
	if source_index < 0:
		return _failure(result, "source_missing", "No state uses '%s'." % old_normalized)

	result.state_edits.append({"state_index": source_index, "path": new_normalized})
	for transition_variant in transitions:
		var transition_def := transition_variant as StateTransitionDef
		if transition_def == null:
			continue
		var transition_id := transition_def.get_normalized_transition_id()
		for condition_index in range(transition_def.conditions.size()):
			var condition := transition_def.conditions[condition_index] as StateTransitionConditionDef
			if condition != null and String(condition.get_normalized_target_state_path()) == old_normalized:
				result.condition_edits.append({"transition_id": transition_id, "condition_index": condition_index, "path": new_normalized})
		for output_index in range(transition_def.outputs.size()):
			var output_def := transition_def.outputs[output_index] as StateTransitionOutputDef
			if output_def != null and String(output_def.get_normalized_target_state_path()) == old_normalized:
				result.output_edits.append({"transition_id": transition_id, "output_index": output_index, "path": new_normalized})
	for resource_path_variant in bindings.keys():
		var resource_path := String(resource_path_variant)
		if _normalize(String(bindings[resource_path_variant])) == old_normalized:
			result.binding_edits[resource_path] = new_normalized
	result.diagnostic = "Rename '%s' to '%s'." % [old_normalized, new_normalized]
	return result


static func apply(states: Array, transitions: Array, plan_result: Dictionary) -> bool:
	if not bool(plan_result.get("ok", false)):
		return false
	for edit_variant in plan_result.get("state_edits", []):
		var edit := edit_variant as Dictionary
		var state_index := int(edit.get("state_index", -1))
		if state_index < 0 or state_index >= states.size():
			return false
		var state_def := states[state_index] as StateVariableDef
		if state_def == null:
			return false
		state_def.path = StringName(str(edit.get("path", "")))
	for edit_variant in plan_result.get("condition_edits", []):
		if not _apply_transition_path_edit(transitions, edit_variant as Dictionary, true):
			return false
	for edit_variant in plan_result.get("output_edits", []):
		if not _apply_transition_path_edit(transitions, edit_variant as Dictionary, false):
			return false
	return true


static func _apply_transition_path_edit(transitions: Array, edit: Dictionary, is_condition: bool) -> bool:
	var wanted_id := int(edit.get("transition_id", 0))
	for transition_variant in transitions:
		var transition_def := transition_variant as StateTransitionDef
		if transition_def == null or transition_def.get_normalized_transition_id() != wanted_id:
			continue
		var index_key := "condition_index" if is_condition else "output_index"
		var edit_index := int(edit.get(index_key, -1))
		var entries: Array = transition_def.conditions if is_condition else transition_def.outputs
		if edit_index < 0 or edit_index >= entries.size():
			return false
		if is_condition:
			var condition := entries[edit_index] as StateTransitionConditionDef
			if condition == null:
				return false
			condition.target_state_path = StringName(str(edit.get("path", "")))
		else:
			var output_def := entries[edit_index] as StateTransitionOutputDef
			if output_def == null:
				return false
			output_def.target_state_path = StringName(str(edit.get("path", "")))
		return true
	return false


static func _result(old_path: String, new_path: String) -> Dictionary:
	return {"ok": true, "reason": "ok", "diagnostic": "", "old_path": old_path, "new_path": new_path, "state_edits": [], "condition_edits": [], "output_edits": [], "binding_edits": {}}


static func _failure(result: Dictionary, reason: String, diagnostic: String) -> Dictionary:
	result.ok = false
	result.reason = reason
	result.diagnostic = diagnostic
	return result


static func _normalize(path: String) -> String:
	return str(path).strip_edges().to_lower()


static func _is_valid_path(path: String) -> bool:
	if path.is_empty() or path.begins_with("/") or path.ends_with("/") or path.contains("//"):
		return false
	for character in path:
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") and character != "_" and character != "/":
			return false
	return true
