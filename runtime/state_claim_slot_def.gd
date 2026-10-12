@tool
extends Resource
class_name StateClaimSlotDef

# Selects the slot id.
@export var slot_id: StringName = &""
# Selects the code key.
@export var code_key: StringName = &""
# Sets the transition id used by this component.
@export var transition_id: int = 0


func get_normalized_slot_id() -> StringName:
	return StringName(str(slot_id).strip_edges().to_lower())


func get_normalized_code_key() -> StringName:
	return StringName(str(code_key).strip_edges().to_lower())


func get_normalized_transition_id() -> int:
	return maxi(0, transition_id)


func is_code_claim() -> bool:
	return get_normalized_code_key() != &"" and get_normalized_transition_id() == 0


func is_transition_claim() -> bool:
	return get_normalized_transition_id() > 0 and get_normalized_code_key() == &""


func is_valid() -> bool:
	return get_normalized_slot_id() != &"" and (is_code_claim() or is_transition_claim())


func ensure_valid_configuration(fallback_slot_id: StringName = &"") -> void:
	slot_id = get_normalized_slot_id()
	code_key = get_normalized_code_key()
	transition_id = get_normalized_transition_id()
	if slot_id == &"":
		slot_id = fallback_slot_id
	if code_key != &"" and transition_id > 0:
		transition_id = 0
