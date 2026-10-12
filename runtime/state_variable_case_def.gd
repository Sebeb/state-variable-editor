@tool
extends Resource
class_name StateVariableCaseDef

const StateVariableChangeDef = preload("state_variable_change_def.gd")

# Provides the outgoing changes configured for this component.
@export var outgoing_changes: Array[StateVariableChangeDef] = []
