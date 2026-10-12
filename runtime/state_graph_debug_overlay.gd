extends CanvasLayer

const StateGraphViewScene = preload("../state_graph_view.tscn")
const _MODE_SHOWN := "shown"

var _state_store: Node = null
var _graph_view: Control = null
var _mode := "hidden"


func _ready() -> void:
	if _graph_view != null:
		return
	if _state_store != null:
		_bind_graph_view()
	else:
		set_mode(_mode)


func set_state_store(value: Node) -> void:
	_state_store = value
	_bind_graph_view()


func _bind_graph_view() -> void:
	if _state_store == null:
		return
	if _state_store.has_method("get_state_graph_debug_mode"):
		_mode = str(_state_store.call("get_state_graph_debug_mode"))
	_apply_mode()


func set_mode(mode: String) -> void:
	_mode = mode
	_apply_mode()


func _apply_mode() -> void:
	if _mode != _MODE_SHOWN:
		_destroy_graph_view()
		return
	_ensure_graph_view()
	if _graph_view == null:
		return
	if _graph_view.has_method("set_presentation_mode"):
		_graph_view.call("set_presentation_mode", _mode)
	if _graph_view.has_method("set"):
		_graph_view.set("persist_runtime_layout", true)
	if _graph_view.has_method("set_state_store"):
		_graph_view.call("set_state_store", _state_store)
	if _graph_view.has_method("set_database") and _state_store != null:
		_graph_view.call("set_database", _state_store.database)


func _ensure_graph_view() -> void:
	if _graph_view != null and is_instance_valid(_graph_view):
		return
	_graph_view = StateGraphViewScene.instantiate()
	_graph_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_graph_view)


func _destroy_graph_view() -> void:
	if _graph_view == null:
		return
	if is_instance_valid(_graph_view):
		_graph_view.queue_free()
	_graph_view = null
