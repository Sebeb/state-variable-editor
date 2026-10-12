@tool
extends Resource
class_name StateTransitionDef

const StateTransitionConditionDef = preload("state_transition_condition_def.gd")
const StateTransitionOutputDef = preload("state_transition_output_def.gd")

# Sets the transition id used by this component.
@export var transition_id: int = 0
# Selects the display name.
@export var display_name: String = ""
# Provides the conditions configured for this component.
@export var conditions: Array[StateTransitionConditionDef] = []
# Provides the outputs configured for this component.
@export var outputs: Array[StateTransitionOutputDef] = []
# Sets the graph position used by this component.
@export var graph_position: Vector2 = Vector2.ZERO


func get_normalized_transition_id() -> int:
	return maxi(0, transition_id)


func get_display_name() -> String:
	if not display_name.strip_edges().is_empty():
		return display_name.strip_edges()
	return "Transition %d" % get_normalized_transition_id()


func ensure_valid_configuration() -> void:
	transition_id = get_normalized_transition_id()
	var normalized_conditions: Array[StateTransitionConditionDef] = []
	for condition in conditions:
		if condition == null:
			continue
		condition.target_state_path = condition.get_normalized_target_state_path()
		condition.binding_key = condition.get_normalized_binding_key()
		normalized_conditions.append(condition)
	conditions = normalized_conditions
	var normalized_outputs: Array[StateTransitionOutputDef] = []
	for output_def in outputs:
		if output_def == null:
			continue
		output_def.target_state_path = output_def.get_normalized_target_state_path()
		output_def.binding_key = output_def.get_normalized_binding_key()
		output_def.target_claim_slot_id = output_def.get_normalized_target_claim_slot_id()
		normalized_outputs.append(output_def)
	outputs = normalized_outputs
