@tool
extends PopupPanel
class_name StateGraphOutputPicker

signal target_selected(state_path: String)

@onready var _search_edit: LineEdit = %SearchEdit
@onready var _target_list: ItemList = %TargetList

var _targets: Array[Dictionary] = []


func _ready() -> void:
	_search_edit.text_changed.connect(_on_search_text_changed)
	_target_list.item_activated.connect(_on_target_activated)


func configure(targets: Array[Dictionary]) -> void:
	_targets = targets.duplicate(true)
	_targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("state_path", "")) < str(b.get("state_path", ""))
	)
	if _search_edit != null:
		_search_edit.clear()
	_rebuild_list("")


func show_at(screen_position: Vector2i) -> void:
	position = screen_position
	popup()
	if _search_edit != null:
		_search_edit.grab_focus()


func visible_target_paths() -> Array[String]:
	var paths: Array[String] = []
	if _target_list == null:
		return paths
	for index in range(_target_list.item_count):
		paths.append(str(_target_list.get_item_metadata(index)))
	return paths


func _on_search_text_changed(text: String) -> void:
	_rebuild_list(text)


func _rebuild_list(query: String) -> void:
	if _target_list == null:
		return
	_target_list.clear()
	var normalized_query := query.strip_edges().to_lower()
	for target in _targets:
		var state_path := str(target.get("state_path", ""))
		var label := str(target.get("label", state_path))
		if not normalized_query.is_empty() and not ("%s %s" % [state_path, label]).to_lower().contains(normalized_query):
			continue
		_target_list.add_item(label)
		_target_list.set_item_metadata(_target_list.item_count - 1, state_path)


func _on_target_activated(index: int) -> void:
	if _target_list == null or index < 0 or index >= _target_list.item_count:
		return
	var state_path := str(_target_list.get_item_metadata(index))
	hide()
	target_selected.emit(state_path)
