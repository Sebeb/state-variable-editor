@tool
extends VBoxContainer

const StateGraphViewScene = preload("state_graph_view.tscn")

var database = null
var _graph_view: Control = null
var _undo_redo: EditorUndoRedoManager = null


func _ready() -> void:
	if _graph_view != null:
		return
	_graph_view = StateGraphViewScene.instantiate()
	_graph_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_graph_view)
	if database != null and _graph_view.has_method("set_database"):
		_graph_view.call("set_database", database)
	if _undo_redo != null and _graph_view.has_method("set_undo_redo"):
		_graph_view.call("set_undo_redo", _undo_redo)
	if _graph_view.has_method("set_presentation_mode"):
		_graph_view.call("set_presentation_mode", "fullscreen_focused")


func set_database(value) -> void:
	database = value
	if _graph_view != null and _graph_view.has_method("set_database"):
		_graph_view.call("set_database", database)


func set_undo_redo(value: EditorUndoRedoManager) -> void:
	_undo_redo = value
	if _graph_view != null and _graph_view.has_method("set_undo_redo"):
		_graph_view.call("set_undo_redo", _undo_redo)
