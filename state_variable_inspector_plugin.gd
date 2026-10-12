@tool
extends EditorInspectorPlugin

const DatabaseEditorScript = preload("state_variable_database_editor.gd")
const StateVariableDatabaseScript = preload("runtime/state_variable_database.gd")
var undo_redo_ref: EditorUndoRedoManager


func _can_handle(object: Object) -> bool:
	return object is StateVariableDatabaseScript


func _parse_begin(object: Object) -> void:
	if not (object is StateVariableDatabaseScript):
		return
	var editor: Control = DatabaseEditorScript.new()
	editor.set_database(object)
	if editor.has_method("set_undo_redo"):
		editor.call("set_undo_redo", undo_redo_ref)
	add_custom_control(editor)


func _parse_property(
	object: Object,
	_type: int,
	path: String,
	_hint: int,
	_hint_text: String,
	_usage_flags: int,
	_wide: bool
) -> bool:
	if not (object is StateVariableDatabaseScript):
		return false
	return path == "entries" or path == "states" or path == "transitions"
