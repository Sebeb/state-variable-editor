@tool
extends Control
class_name StateGraphView

signal runtime_resync_requested()
signal runtime_scope_selected(scope_key: StringName)
## Emitted after any successful database commit (do or undo). External
## embedders (e.g. the pill Inspector) listen to know when to refresh rows
## they built via [method build_embedded_output_rows].
signal database_changed()

const StateClaimSlotDefScript = preload("runtime/state_claim_slot_def.gd")
const StateTransitionConditionDefScript = preload("runtime/state_transition_condition_def.gd")
const StateTransitionDefScript = preload("runtime/state_transition_def.gd")
const StateTransitionOutputDefScript = preload("runtime/state_transition_output_def.gd")
const StateVariableDefScript = preload("runtime/state_variable_def.gd")
const StateVariableRenameScript = preload("runtime/state_variable_rename.gd")
const StateBindingIndex = preload("runtime/state_binding_index.gd")
const StateGraphOutputPickerScene = preload("state_graph_output_picker.tscn")

const _STATE_NODE_PREFIX := "state:"
const _TRANSITION_NODE_PREFIX := "transition:"
const _LAYOUT_SAVE_PATH := "user://state_graph_layout.cfg"
const _STATE_VALUES_SAVE_PATH := "user://state_variables.cfg"
const _LAYOUT_SECTION := "positions"
const _VISIBILITY_SECTION := "visibility"
const _GLOBAL_SCOPE_KEY := "global"
const _AUTHORING_TEMPLATE_SCOPE_PREFIX := "template/"
# Roots scanned for authored EntityStateMachineTemplate resources so the
# authoring selector can list each entity type's default local machine.
const _AUTHORING_TEMPLATE_SCAN_ROOTS := ["res://data/"]
const EntityStateMachineTemplateScript = preload("runtime/entity_state_machine_template.gd")
const StateVariableDatabaseScript = preload("runtime/state_variable_database.gd")
const _PRESENTATION_MODE_SHOWN := "shown"
const _PRESENTATION_MODE_TRANSPARENT_OVERLAY := "transparent_overlay"
const _STATE_TO_TRANSITION_COLOR := Color(0.52, 0.52, 0.56, 0.72)
const _TRANSITION_TO_STATE_INACTIVE := Color(0.6, 0.6, 0.65, 0.65)
const _TRANSITION_TO_STATE_ACTIVE := Color(0.35, 0.55, 1.0, 0.95)
const _TRANSITION_TO_STATE_SUPPRESSED := Color(0.14, 0.23, 0.5, 0.95)
const _STATE_ACTIVE_COLOR := Color(0.35, 0.55, 1.0, 1.0)
const _STATE_OVERRIDE_COLOR := Color(0.8, 0.45, 1.0, 1.0)
const _STATE_SUPPRESSED_COLOR := Color(0.14, 0.23, 0.5, 1.0)
const _STATE_IDLE_COLOR := Color(0.7, 0.7, 0.7, 1.0)
const _TRANSITION_ACTIVE_COLOR := Color(0.3, 0.95, 0.45, 1.0)
const _TRANSITION_INVALID_COLOR := Color(1.0, 0.45, 0.45, 1.0)
const _TRANSITION_IDLE_COLOR := Color(0.65, 0.65, 0.72, 1.0)
const _COLUMN_NAME := 0
const _COLUMN_VALUE := 1
const _COLUMN_DEFAULT := 2
const _COLUMN_RESOLVER := 3
const _COLUMN_VISIBILITY := 4
const _SIDEBAR_BUTTON_ID_VISIBILITY := 1
const _SIDEBAR_CONTEXT_REMOVE_OVERRIDE := 1
const _SIDEBAR_CONTEXT_SET_DEFAULT_FROM_RESOLVED := 2
const _SIDEBAR_CONTEXT_HIDE := 3
const _SIDEBAR_CONTEXT_DELETE := 4
const _SIDEBAR_CONTEXT_SHOW_RELEVANT := 5
const _CANVAS_CREATE_STATE := 1
const _CANVAS_CREATE_TRANSITION := 2
const _NODE_HIDE := 1
const _NODE_DELETE := 2
const _NODE_SHOW_RELEVANT := 3
const _COLUMN_MENU_DEFAULT := 1
const _COLUMN_MENU_RESOLVER := 2
const _SIDEBAR_REQUIRED_COLUMNS := [_COLUMN_NAME, _COLUMN_VALUE]
const _SIDEBAR_OPTIONAL_COLUMNS := [_COLUMN_DEFAULT, _COLUMN_RESOLVER]
const _GRAPH_NODE_FIXED_WIDTH := 560.0
const _GRAPH_NODE_MIN_HEIGHT := 120.0
const _GRAPH_NODE_RADIUS := 18
const _GRAPH_ENTRY_RADIUS := 12
const _GRAPH_ENTRY_PORT_SPACER := Vector2(52.0, 52.0)
const _OUTPUT_PICKER_CLICK_DISTANCE := 8.0
const _OUTPUT_REVEAL_HORIZONTAL_GAP := 180.0
const _OUTPUT_REVEAL_VERTICAL_GAP := 180.0
const _OUTPUT_REVEAL_COLLISION_MARGIN := 32.0

## `StateStore.ValueLayer.DEFAULT`. Spelled as a literal because this view is an editor
## plugin and autoloads do not exist in the editor, so the store is only ever reached
## duck-typed through [member state_store].
const _STATE_STORE_DEFAULT_LAYER := 0

var database = null
var state_store: Node = null
var _graph_input_control_state: Dictionary = {}

var _undo_redo: Object = null
var runtime_snapshot: Dictionary = {}
var persist_runtime_layout := false
var presentation_mode := _PRESENTATION_MODE_SHOWN
var _graph_edit: GraphEdit = null
var _graph_panel: PanelContainer = null
var _graph_root: Control = null
var _overlay: Control = null
var _toolbar: HBoxContainer = null
var _auto_arrange_button: Button = null
var _scope_selector: MenuButton = null
var _scope_diagnostic_label: Label = null
var _scope_registry: Array[Dictionary] = []
# Maps a generated popup item id to its scope descriptor so nested submenu
# selections resolve back to a runtime scope key or an authoring template.
var _scope_menu_selection_by_id: Dictionary = {}
var _scope_menu_submenus: Array = []
var _authoring_scope_key := _GLOBAL_SCOPE_KEY
var _authoring_templates: Array[Dictionary] = []
var _authoring_templates_discovered := false
var _reset_visibility_button: Button = null
var _sidebar_filter_visible_button: Button = null
var _toggle_sidebar_button: Button = null
var _column_menu_button: MenuButton = null
var _background_dim: ColorRect = null
var _sidebar_tree: Tree = null
var _sidebar_search_edit: LineEdit = null
var _sidebar_split: HSplitContainer = null
var _sidebar_panel: Control = null
var _sidebar_context_menu: PopupMenu = null
var _canvas_context_menu: PopupMenu = null
var _node_context_menu: PopupMenu = null
var _output_picker: PopupPanel = null
var _override_dialog: ConfirmationDialog = null
var _override_editor_host: VBoxContainer = null
var _override_editor: Control = null
var _override_target_state_path := ""
var _sidebar_context_metadata: Dictionary = {}
var _rename_dialog: ConfirmationDialog = null
var _rename_leaf_edit: LineEdit = null
var _rename_path_edit: LineEdit = null
var _rename_display_name_edit: LineEdit = null
var _rename_target: Dictionary = {}
var _value_dialog: ConfirmationDialog = null
var _value_editor_host: VBoxContainer = null
var _value_editor: Control = null
var _value_edit_target: Dictionary = {}
var _canvas_context_graph_position := Vector2.ZERO
var _node_context_node_id := ""
var _node_positions: Dictionary = {}
var _node_visibility: Dictionary = {}
var _group_collapsed: Dictionary = {}
var _nodes_by_id: Dictionary = {}
var _state_header_ports: Dictionary = {}
var _state_claim_ports: Dictionary = {}
var _transition_condition_ports: Dictionary = {}
var _transition_output_ports: Dictionary = {}
var _connections: Array[Dictionary] = []
var _connection_visuals: Dictionary = {}
var _connected_semantic_endpoints: Dictionary = {}
var _preferences_loaded := false
var _visible_icon: Texture2D = null
var _hidden_icon: Texture2D = null
var _sidebar_visible := true
var _sidebar_filter_to_visible := false
var _sidebar_search_query := ""
var _sidebar_show_default_column := true
var _sidebar_show_resolver_column := true
var _compact_graph_mode := false
var _current_structure_signature := ""
var _drag_connection_origin: Dictionary = {}
var _drag_connection_hover: Dictionary = {}
var _drag_connection_mouse_graph_position := Vector2.ZERO
var _drag_connection_start_viewport_position := Vector2.ZERO
var _output_picker_context: Dictionary = {}
var _drag_claim_origin: Dictionary = {}
var _claim_row_panels: Dictionary = {}
var _pending_inline_title_node_id := ""
var _pending_claim_edit_state_path := ""
var _pending_claim_edit_slot_id := ""
var _sidebar_column_indices: Dictionary = {}
var _sidebar_items_by_state_path: Dictionary = {}
var _sidebar_items_by_transition_id: Dictionary = {}
var _sidebar_rename_request_revision := 0
var _sidebar_rename_request: Dictionary = {}
var _graph_update_dirty := false
var _last_graph_view_transform := Vector3(INF, INF, INF)
var _graph_transform_redraw_revision := 0


func _ready() -> void:
	if _graph_edit != null:
		return
	_build_ui()
	_rebuild_from_current_state()
	visibility_changed.connect(_sync_processing_state)
	_sync_processing_state()


func _process(delta: float) -> void:
	var needs_redraw := _advance_connection_visuals(delta)
	needs_redraw = _update_compact_graph_mode() or needs_redraw
	needs_redraw = _capture_graph_view_transform_change() or needs_redraw
	needs_redraw = _capture_node_position_changes() or needs_redraw
	if needs_redraw:
		_queue_overlay_redraw()


func _sync_processing_state() -> void:
	var graph_visible := _is_graph_update_visible()
	set_process(graph_visible)
	if graph_visible and is_node_ready():
		_flush_deferred_graph_update()


func _is_graph_update_visible() -> bool:
	return is_inside_tree() and is_visible_in_tree() and presentation_mode != "hidden"


func _mark_graph_update_dirty() -> void:
	_graph_update_dirty = true


func _flush_deferred_graph_update() -> void:
	if not _graph_update_dirty:
		if _nodes_by_id.is_empty() and not _get_effective_snapshot().is_empty():
			_rebuild_from_current_state()
		return
	_graph_update_dirty = false
	_apply_runtime_snapshot_to_graph()


func _queue_overlay_redraw() -> void:
	if _overlay != null and _is_graph_update_visible():
		_overlay.queue_redraw()


func _apply_runtime_snapshot_to_graph() -> void:
	var new_signature := _build_structure_signature(runtime_snapshot)
	if _graph_edit != null and new_signature == _current_structure_signature and not _nodes_by_id.is_empty():
		_refresh_from_snapshot(runtime_snapshot)
	else:
		_rebuild_from_current_state()


func _snapshot_dictionary_array(snapshot: Dictionary, key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_value: Variant = snapshot.get(key, [])
	var raw_array: Array = raw_value if raw_value is Array else []
	for item_variant in raw_array:
		if item_variant is Dictionary:
			result.append(item_variant)
	return result


func _as_bool(value: Variant) -> bool:
	if value is bool:
		return value
	if value is String:
		return value.strip_edges().to_lower() == "true"
	if value is int:
		return value != 0
	if value is float:
		return not is_zero_approx(value)
	return value != null


func _as_int(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		return int(round(value))
	if value is String:
		return value.strip_edges().to_int()
	if value is bool:
		return 1 if value else 0
	return 0


func _as_float(value: Variant) -> float:
	if value is float:
		return value
	if value is int:
		return value * 1.0
	if value is String:
		return value.strip_edges().to_float()
	if value is bool:
		return 1.0 if value else 0.0
	return 0.0


func _serialize_state_value_for_snapshot(definition: StateVariableDefScript, value: Variant) -> Variant:
	if definition != null and definition.value_type == StateVariableDefScript.ValueType.LIST:
		return definition.list_keys(value)
	return value


func set_database(value) -> void:
	database = value
	if database != null and database.has_method("ensure_valid_configuration"):
		database.ensure_valid_configuration()
	_current_structure_signature = ""
	_rebuild_from_current_state()
	_rebuild_scope_selector()


func set_undo_redo(value: Object) -> void:
	_undo_redo = value


func set_state_store(value: Node) -> void:
	if state_store != null and state_store.has_signal("state_graph_delta_ready"):
		if state_store.state_graph_delta_ready.is_connected(_on_state_graph_delta_ready):
			state_store.state_graph_delta_ready.disconnect(_on_state_graph_delta_ready)
	if state_store != null and state_store.has_signal("state_graph_scope_registry_changed"):
		if state_store.state_graph_scope_registry_changed.is_connected(
			_on_state_graph_scope_registry_changed
		):
			state_store.state_graph_scope_registry_changed.disconnect(
				_on_state_graph_scope_registry_changed
			)
	state_store = value
	if state_store != null and state_store.has_signal("state_graph_debug_mode_changed"):
		if not state_store.state_graph_debug_mode_changed.is_connected(_on_state_graph_debug_mode_changed):
			state_store.state_graph_debug_mode_changed.connect(_on_state_graph_debug_mode_changed)
	if state_store != null and state_store.has_signal("state_graph_delta_ready"):
		if not state_store.state_graph_delta_ready.is_connected(_on_state_graph_delta_ready):
			state_store.state_graph_delta_ready.connect(_on_state_graph_delta_ready)
	if state_store != null and state_store.has_signal("state_graph_scope_registry_changed"):
		if not state_store.state_graph_scope_registry_changed.is_connected(
			_on_state_graph_scope_registry_changed
		):
			state_store.state_graph_scope_registry_changed.connect(
				_on_state_graph_scope_registry_changed
			)
	if state_store != null and state_store.has_method("get_state_graph_debug_mode"):
		set_presentation_mode(state_store.call("get_state_graph_debug_mode"))
	if state_store != null and state_store.has_method("get_state_graph_snapshot"):
		var snapshot_variant: Variant = state_store.call("get_state_graph_snapshot")
		if snapshot_variant is Dictionary:
			set_runtime_snapshot(snapshot_variant as Dictionary)


func set_runtime_snapshot(snapshot: Dictionary) -> void:
	var previous_scope := String(runtime_snapshot.get("scope_key", "global"))
	runtime_snapshot = snapshot.duplicate(true)
	_scope_registry = _snapshot_dictionary_array(runtime_snapshot, "scope_registry")
	_rebuild_scope_selector()
	if previous_scope != String(runtime_snapshot.get("scope_key", "global")):
		_preferences_loaded = false
		_node_positions.clear()
		_node_visibility.clear()
		_group_collapsed.clear()
	if not _is_graph_update_visible() or _graph_edit == null:
		_mark_graph_update_dirty()
		return
	_apply_runtime_snapshot_to_graph()


func apply_runtime_delta(delta: Dictionary) -> bool:
	if runtime_snapshot.is_empty():
		runtime_resync_requested.emit()
		return false
	if int(delta.get("schema_version", -1)) != int(runtime_snapshot.get("schema_version", -2)):
		runtime_resync_requested.emit()
		return false
	if int(delta.get("topology_version", -1)) != int(runtime_snapshot.get("topology_version", -2)):
		runtime_resync_requested.emit()
		return false
	if String(delta.get("scope_key", "global")) != String(
		runtime_snapshot.get("scope_key", "global")
	):
		return true

	var previous_states: Dictionary = {}
	var state_indexes: Dictionary = {}
	var states: Array = runtime_snapshot.get("states", [])
	for state_index in range(states.size()):
		var state_data: Dictionary = states[state_index]
		state_indexes[str(state_data.get("path", ""))] = state_index
	var changed_state_paths: Array[String] = []
	for state_variant in delta.get("states", []):
		var state_data: Dictionary = state_variant
		var state_path := str(state_data.get("path", ""))
		if state_path.is_empty() or not state_indexes.has(state_path):
			runtime_resync_requested.emit()
			return false
		previous_states[state_path] = (states[int(state_indexes[state_path])] as Dictionary).duplicate(true)
		states[int(state_indexes[state_path])] = state_data.duplicate(true)
		changed_state_paths.append(state_path)
	runtime_snapshot["states"] = states

	var transition_indexes: Dictionary = {}
	var transitions: Array = runtime_snapshot.get("transitions", [])
	for transition_index in range(transitions.size()):
		var transition_data: Dictionary = transitions[transition_index]
		transition_indexes[str(transition_data.get("transition_id", ""))] = transition_index
	var changed_transition_ids: Array[String] = []
	for transition_variant in delta.get("transitions", []):
		var transition_data: Dictionary = transition_variant
		var transition_id := str(transition_data.get("transition_id", ""))
		if transition_id.is_empty() or not transition_indexes.has(transition_id):
			runtime_resync_requested.emit()
			return false
		transitions[int(transition_indexes[transition_id])] = transition_data.duplicate(true)
		changed_transition_ids.append(transition_id)
	runtime_snapshot["transitions"] = transitions
	if not _is_graph_update_visible() or _graph_edit == null:
		_mark_graph_update_dirty()
		return true

	for state_path in changed_state_paths:
		var state_data: Dictionary = states[int(state_indexes[state_path])]
		_refresh_sidebar_state_item(state_path, state_data)
		var node_id := "%s%s" % [_STATE_NODE_PREFIX, state_path]
		if _nodes_by_id.has(node_id):
			var membership_changed := _claim_membership_signature(previous_states[state_path]) != _claim_membership_signature(state_data)
			_refresh_state_node(_nodes_by_id[node_id] as GraphNode, state_data, membership_changed)
	for transition_id in changed_transition_ids:
		var transition_data: Dictionary = transitions[int(transition_indexes[transition_id])]
		_refresh_sidebar_transition_item(transition_id, transition_data)
		var node_id := "%s%s" % [_TRANSITION_NODE_PREFIX, transition_id]
		if _nodes_by_id.has(node_id):
			_refresh_transition_node(_nodes_by_id[node_id] as GraphNode, transition_data)
	_refresh_incremental_connections(transitions, changed_state_paths, changed_transition_ids)
	_sync_connection_visual_targets()
	_update_compact_graph_mode()
	_queue_overlay_redraw()
	return true


func _on_state_graph_delta_ready(delta: Dictionary) -> void:
	apply_runtime_delta(delta)


func _on_state_graph_scope_registry_changed(event: Dictionary) -> void:
	var action := String(event.get("action", ""))
	var removed_scope := String(event.get("scope_key", ""))
	var current_scope := String(runtime_snapshot.get("scope_key", _GLOBAL_SCOPE_KEY))
	_scope_registry = _snapshot_dictionary_array(event, "scope_registry")
	_rebuild_scope_selector()
	var selected_scope := String(event.get("selected_scope_key", ""))
	if (
		action == "unregistered"
		and removed_scope == current_scope
		and removed_scope != _GLOBAL_SCOPE_KEY
	):
		var fallback := selected_scope if not selected_scope.is_empty() else _GLOBAL_SCOPE_KEY
		_set_scope_diagnostic(
			"Live scope '%s' despawned — showing %s." % [
				_scope_display_for_key(removed_scope),
				_scope_display_for_key(fallback),
			]
		)
	if (
		not selected_scope.is_empty()
		and selected_scope != current_scope
	):
		# Server-driven fallback (e.g. despawn): apply without clearing the
		# diagnostic so the user still sees why the scope changed.
		_select_runtime_scope(StringName(selected_scope))


func apply_scope_registry_event(event: Dictionary) -> void:
	_on_state_graph_scope_registry_changed(event)


# Runtime debugging and authoring share one selector widget. Runtime mode is
# active whenever a live snapshot or in-process store is bound; otherwise the
# selector lists authored entity-type templates for editing.
func _is_runtime_scope_mode() -> bool:
	return state_store != null or not runtime_snapshot.is_empty()


func _rebuild_scope_selector() -> void:
	if _scope_selector == null:
		return
	if _is_runtime_scope_mode():
		_rebuild_runtime_scope_menu()
	else:
		_rebuild_authoring_scope_menu()
	_update_scope_button_text()


func _reset_scope_menu() -> PopupMenu:
	var popup := _scope_selector.get_popup()
	popup.clear()
	for submenu in _scope_menu_submenus:
		if is_instance_valid(submenu):
			submenu.queue_free()
	_scope_menu_submenus.clear()
	_scope_menu_selection_by_id.clear()
	return popup


func _rebuild_runtime_scope_menu() -> void:
	var popup := _reset_scope_menu()
	var selected_scope := String(runtime_snapshot.get("scope_key", _GLOBAL_SCOPE_KEY))
	var next_id := 1
	var global_display := "Global"
	var grouped: Dictionary = {}
	var template_order: Array[String] = []
	for entry in _scope_registry:
		var scope_key := String(entry.get("scope_key", ""))
		if scope_key.is_empty():
			continue
		if scope_key == _GLOBAL_SCOPE_KEY:
			global_display = String(entry.get("display_name", "Global"))
			continue
		var template_key := String(entry.get("template_key", ""))
		if template_key.is_empty():
			template_key = scope_key
		if not grouped.has(template_key):
			grouped[template_key] = []
			template_order.append(template_key)
		(grouped[template_key] as Array).append(entry)
	popup.add_item(global_display, next_id)
	_scope_menu_selection_by_id[next_id] = {"type": "runtime", "scope_key": _GLOBAL_SCOPE_KEY}
	_mark_scope_menu_checked(popup, _GLOBAL_SCOPE_KEY == selected_scope)
	next_id += 1
	for template_key in template_order:
		var entries: Array = grouped[template_key]
		var submenu := PopupMenu.new()
		submenu.id_pressed.connect(_on_scope_menu_id_pressed)
		for entry in entries:
			var scope_key := String(entry.get("scope_key", ""))
			submenu.add_item(_runtime_instance_label(entry), next_id)
			_scope_menu_selection_by_id[next_id] = {"type": "runtime", "scope_key": scope_key}
			var index := submenu.item_count - 1
			if scope_key == selected_scope:
				submenu.set_item_as_checkable(index, true)
				submenu.set_item_checked(index, true)
			next_id += 1
		popup.add_submenu_node_item(
			"%s (%d)" % [_humanize_scope_key(template_key), entries.size()],
			submenu
		)
		_scope_menu_submenus.append(submenu)


func _rebuild_authoring_scope_menu() -> void:
	_discover_authoring_templates()
	var popup := _reset_scope_menu()
	var next_id := 1
	popup.add_item("Global", next_id)
	_scope_menu_selection_by_id[next_id] = {"type": "authoring_global"}
	_mark_scope_menu_checked(popup, _authoring_scope_key == _GLOBAL_SCOPE_KEY)
	next_id += 1
	if not _authoring_templates.is_empty():
		popup.add_separator("Entity Templates")
		for template in _authoring_templates:
			var scope_key := String(template.get("scope_key", ""))
			popup.add_item(String(template.get("display_name", scope_key)), next_id)
			_scope_menu_selection_by_id[next_id] = {"type": "authoring_template", "scope_key": scope_key}
			_mark_scope_menu_checked(popup, scope_key == _authoring_scope_key)
			next_id += 1


func _mark_scope_menu_checked(popup: PopupMenu, checked: bool) -> void:
	var index := popup.item_count - 1
	if index < 0:
		return
	popup.set_item_as_checkable(index, true)
	popup.set_item_checked(index, checked)


func _runtime_instance_label(entry: Dictionary) -> String:
	var instance_key := String(entry.get("instance_key", ""))
	if not instance_key.is_empty():
		return "Instance %s" % instance_key
	return String(entry.get("display_name", entry.get("scope_key", "")))


func _humanize_scope_key(scope_key: String) -> String:
	var text := scope_key.replace("_", " ").replace("/", " / ").strip_edges()
	if text.is_empty():
		return scope_key
	return text.capitalize()


func _scope_display_for_key(scope_key: String) -> String:
	if scope_key == _GLOBAL_SCOPE_KEY or scope_key.is_empty():
		return "Global"
	for entry in _scope_registry:
		if String(entry.get("scope_key", "")) == scope_key:
			return String(entry.get("display_name", scope_key))
	return scope_key


func _on_scope_menu_id_pressed(id: int) -> void:
	var selection: Dictionary = _scope_menu_selection_by_id.get(id, {})
	if selection.is_empty():
		return
	match String(selection.get("type", "")):
		"runtime":
			_clear_scope_diagnostic()
			_select_runtime_scope(StringName(String(selection.get("scope_key", ""))))
		"authoring_global":
			_select_authoring_scope(_GLOBAL_SCOPE_KEY)
		"authoring_template":
			_select_authoring_scope(String(selection.get("scope_key", "")))


func _select_runtime_scope(scope_key: StringName) -> void:
	if String(scope_key).is_empty():
		return
	if (
		state_store != null
		and state_store.has_method("select_state_graph_scope")
		and state_store.has_method("get_state_graph_snapshot_for_scope")
	):
		if bool(state_store.call("select_state_graph_scope", scope_key)):
			var snapshot: Variant = state_store.call(
				"get_state_graph_snapshot_for_scope",
				scope_key
			)
			if snapshot is Dictionary and not (snapshot as Dictionary).is_empty():
				set_runtime_snapshot(snapshot as Dictionary)
		return
	runtime_scope_selected.emit(scope_key)


func _select_authoring_scope(scope_key: String) -> void:
	_clear_scope_diagnostic()
	var next_database = null
	if scope_key == _GLOBAL_SCOPE_KEY:
		next_database = StateVariableDatabaseScript.load_default_database()
	else:
		for template in _authoring_templates:
			if String(template.get("scope_key", "")) == scope_key:
				next_database = template.get("database")
				break
	if next_database == null:
		_set_scope_diagnostic("Could not load the selected template's database.")
		return
	_authoring_scope_key = scope_key
	# Reset per-scope view preferences so one template's layout never bleeds into
	# another; authored node positions live on each database's own definitions.
	_preferences_loaded = false
	_node_positions.clear()
	_node_visibility.clear()
	_group_collapsed.clear()
	set_database(next_database)


func _discover_authoring_templates() -> void:
	if _authoring_templates_discovered:
		return
	_authoring_templates_discovered = true
	_authoring_templates.clear()
	var seen: Dictionary = {}
	for root in _AUTHORING_TEMPLATE_SCAN_ROOTS:
		_scan_authoring_templates_in_dir(String(root), seen)
	_authoring_templates.sort_custom(
		func(a: Dictionary, b: Dictionary):
			return String(a.get("display_name", "")) < String(b.get("display_name", ""))
	)


func _scan_authoring_templates_in_dir(dir_path: String, seen: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if dir.current_is_dir():
			if not entry_name.begins_with("."):
				_scan_authoring_templates_in_dir(dir_path.path_join(entry_name), seen)
		elif entry_name.ends_with(".tres"):
			var res_path := dir_path.path_join(entry_name)
			# Peek the text-resource header so only actual template resources are
			# loaded; scanning every resource under res://data/ would be slow and
			# could surface unrelated load errors.
			if not seen.has(res_path) and _resource_declares_template(res_path):
				seen[res_path] = true
				var resource = load(res_path)
				if resource is EntityStateMachineTemplate and resource.database != null:
					var template_key := String(resource.get_normalized_template_key())
					if not template_key.is_empty():
						_authoring_templates.append({
							"template_key": template_key,
							"scope_key": _AUTHORING_TEMPLATE_SCOPE_PREFIX + template_key,
							"display_name": "%s (template)" % _humanize_scope_key(template_key),
							"database": resource.database,
						})
		entry_name = dir.get_next()
	dir.list_dir_end()


func _resource_declares_template(res_path: String) -> bool:
	var file := FileAccess.open(res_path, FileAccess.READ)
	if file == null:
		return false
	var header := file.get_buffer(512).get_string_from_utf8()
	file.close()
	return header.contains("EntityStateMachineTemplate")


func _update_scope_button_text() -> void:
	if _scope_selector == null:
		return
	var label := "Global"
	if _is_runtime_scope_mode():
		label = _scope_display_for_key(
			String(runtime_snapshot.get("scope_key", _GLOBAL_SCOPE_KEY))
		)
	elif _authoring_scope_key != _GLOBAL_SCOPE_KEY:
		for template in _authoring_templates:
			if String(template.get("scope_key", "")) == _authoring_scope_key:
				label = String(template.get("display_name", _authoring_scope_key))
				break
	_scope_selector.text = label


func _set_scope_diagnostic(text: String) -> void:
	if _scope_diagnostic_label == null:
		return
	_scope_diagnostic_label.text = text
	_scope_diagnostic_label.visible = not text.is_empty()


func _clear_scope_diagnostic() -> void:
	_set_scope_diagnostic("")


func set_presentation_mode(mode: String) -> void:
	presentation_mode = _normalize_presentation_mode(mode)
	if _background_dim == null:
		return
	if presentation_mode == "hidden" or presentation_mode == _PRESENTATION_MODE_TRANSPARENT_OVERLAY:
		_clear_active_pointer_state()
	match presentation_mode:
		"hidden":
			visible = false
			process_mode = Node.PROCESS_MODE_DISABLED
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			_background_dim.color = Color(0.0, 0.0, 0.0, 0.0)
			modulate = Color.WHITE
			_set_graph_input_enabled(false)
			_apply_graph_surface_visibility(true)
		_PRESENTATION_MODE_TRANSPARENT_OVERLAY:
			process_mode = Node.PROCESS_MODE_INHERIT
			visible = true
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			_background_dim.color = Color(0.0, 0.0, 0.0, 0.0)
			modulate = Color(1.0, 1.0, 1.0, 0.78)
			_set_graph_input_enabled(false)
			_apply_graph_surface_visibility(true)
		_:
			process_mode = Node.PROCESS_MODE_INHERIT
			visible = true
			mouse_filter = Control.MOUSE_FILTER_STOP
			_background_dim.color = Color(0.0, 0.0, 0.0, 0.45)
			modulate = Color.WHITE
			_set_graph_input_enabled(true)
			_apply_graph_surface_visibility(false)
	queue_redraw()


func _set_graph_input_enabled(enabled: bool) -> void:
	if enabled:
		_restore_graph_descendant_input_state()
		mouse_filter = Control.MOUSE_FILTER_STOP
	if _sidebar_split != null:
		_sidebar_split.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	if _graph_root != null:
		_graph_root.mouse_filter = Control.MOUSE_FILTER_PASS if enabled else Control.MOUSE_FILTER_IGNORE
	if _toolbar != null:
		_toolbar.visible = enabled
	if _graph_edit != null:
		_graph_edit.mouse_filter = Control.MOUSE_FILTER_PASS if enabled else Control.MOUSE_FILTER_IGNORE
		_graph_edit.minimap_enabled = enabled
		_graph_edit.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		if !enabled:
			_graph_edit.release_focus()
	if _sidebar_tree != null:
		_sidebar_tree.mouse_filter = Control.MOUSE_FILTER_PASS if enabled else Control.MOUSE_FILTER_IGNORE
		_sidebar_tree.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		if !enabled:
			_sidebar_tree.release_focus()
	if !enabled:
		_force_graph_descendant_input_inert()


func _force_graph_descendant_input_inert() -> void:
	for control in _collect_control_descendants(self):
		if not _graph_input_control_state.has(control):
			_graph_input_control_state[control] = {
				"mouse_filter": control.mouse_filter,
				"focus_mode": control.focus_mode,
			}
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.focus_mode = Control.FOCUS_NONE
		if control.has_focus():
			control.release_focus()


func _restore_graph_descendant_input_state() -> void:
	for control_variant in _graph_input_control_state.keys():
		var control := control_variant as Control
		if control == null or !is_instance_valid(control):
			continue
		var state: Dictionary = _graph_input_control_state.get(control, {})
		control.mouse_filter = int(state.get("mouse_filter", control.mouse_filter))
		control.focus_mode = int(state.get("focus_mode", control.focus_mode))
	_graph_input_control_state.clear()


func _collect_control_descendants(root: Node) -> Array[Control]:
	var controls: Array[Control] = []
	if root is Control:
		controls.append(root as Control)
	for child in root.get_children():
		controls.append_array(_collect_control_descendants(child))
	return controls


func _is_graph_input_enabled() -> bool:
	return presentation_mode != "hidden" and presentation_mode != _PRESENTATION_MODE_TRANSPARENT_OVERLAY and is_inside_tree() and is_visible_in_tree()


func _clear_active_pointer_state() -> void:
	_drag_connection_origin.clear()
	_drag_connection_hover.clear()
	_drag_claim_origin.clear()
	if _canvas_context_menu != null:
		_canvas_context_menu.hide()
	if _node_context_menu != null:
		_node_context_menu.hide()
	if _sidebar_context_menu != null:
		_sidebar_context_menu.hide()
	if _overlay != null:
		_overlay.queue_redraw()



func _apply_graph_surface_visibility(transparent: bool) -> void:
	if _graph_panel != null:
		if transparent:
			_graph_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		elif _graph_panel.has_theme_stylebox_override("panel"):
			_graph_panel.remove_theme_stylebox_override("panel")
	if _graph_edit != null:
		if transparent:
			_graph_edit.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			_graph_edit.add_theme_color_override("grid_major", Color(0.0, 0.0, 0.0, 0.0))
			_graph_edit.add_theme_color_override("grid_minor", Color(0.0, 0.0, 0.0, 0.0))
		else:
			if _graph_edit.has_theme_stylebox_override("panel"):
				_graph_edit.remove_theme_stylebox_override("panel")
			if _graph_edit.has_theme_color_override("grid_major"):
				_graph_edit.remove_theme_color_override("grid_major")
			if _graph_edit.has_theme_color_override("grid_minor"):
				_graph_edit.remove_theme_color_override("grid_minor")


func _toggle_sidebar_visibility() -> void:
	_sidebar_visible = not _sidebar_visible
	_apply_sidebar_visibility()


func _apply_sidebar_visibility() -> void:
	if _sidebar_panel != null:
		_sidebar_panel.visible = _sidebar_visible
		_sidebar_panel.custom_minimum_size = Vector2(720.0, 0.0) if _sidebar_visible else Vector2.ZERO
	if _sidebar_split != null and _sidebar_visible:
		_sidebar_split.split_offset = maxi(_sidebar_split.split_offset, 720)
	if _toggle_sidebar_button != null:
		_toggle_sidebar_button.text = "Hide Sidebar" if _sidebar_visible else "Show Sidebar"
	if _column_menu_button != null:
		_column_menu_button.visible = _sidebar_visible


func _apply_sidebar_column_visibility() -> void:
	if _sidebar_tree == null:
		return
	_rebuild_sidebar_column_layout()
	if _column_menu_button != null:
		var popup := _column_menu_button.get_popup()
		popup.set_item_checked(popup.get_item_index(_COLUMN_MENU_DEFAULT), _sidebar_show_default_column)
		popup.set_item_checked(popup.get_item_index(_COLUMN_MENU_RESOLVER), _sidebar_show_resolver_column)


func _rebuild_sidebar_column_layout() -> void:
	if _sidebar_tree == null:
		return
	var visible_columns: Array[int] = [_COLUMN_NAME, _COLUMN_VALUE]
	if _sidebar_show_default_column:
		visible_columns.append(_COLUMN_DEFAULT)
	if _sidebar_show_resolver_column:
		visible_columns.append(_COLUMN_RESOLVER)
	visible_columns.append(_COLUMN_VISIBILITY)
	_sidebar_column_indices.clear()
	_sidebar_tree.columns = visible_columns.size()
	for index in range(visible_columns.size()):
		_sidebar_column_indices[int(visible_columns[index])] = index
	for physical_index in range(_sidebar_tree.columns):
		_sidebar_tree.set_column_expand(physical_index, false)
		_sidebar_tree.set_column_custom_minimum_width(physical_index, 0)
		if _sidebar_tree.has_method("set_column_expand_ratio"):
			_sidebar_tree.call("set_column_expand_ratio", physical_index, 0)
	var name_column := _sidebar_column_index(_COLUMN_NAME)
	var value_column := _sidebar_column_index(_COLUMN_VALUE)
	_sidebar_tree.set_column_title(name_column, "State / Transition")
	_sidebar_tree.set_column_expand(name_column, true)
	_sidebar_tree.set_column_custom_minimum_width(name_column, 360)
	if _sidebar_tree.has_method("set_column_expand_ratio"):
		_sidebar_tree.call("set_column_expand_ratio", name_column, 5)
	_sidebar_tree.set_column_title(value_column, "Value")
	_sidebar_tree.set_column_expand(value_column, true)
	_sidebar_tree.set_column_custom_minimum_width(value_column, 180)
	if _sidebar_tree.has_method("set_column_expand_ratio"):
		_sidebar_tree.call("set_column_expand_ratio", value_column, 3)
	if _sidebar_has_column(_COLUMN_DEFAULT):
		var default_column := _sidebar_column_index(_COLUMN_DEFAULT)
		_sidebar_tree.set_column_title(default_column, "Default")
		_sidebar_tree.set_column_expand(default_column, true)
		_sidebar_tree.set_column_custom_minimum_width(default_column, 180)
		if _sidebar_tree.has_method("set_column_expand_ratio"):
			_sidebar_tree.call("set_column_expand_ratio", default_column, 3)
	if _sidebar_has_column(_COLUMN_RESOLVER):
		var resolver_column := _sidebar_column_index(_COLUMN_RESOLVER)
		_sidebar_tree.set_column_title(resolver_column, "Resolver")
		_sidebar_tree.set_column_expand(resolver_column, true)
		_sidebar_tree.set_column_custom_minimum_width(resolver_column, 120)
		if _sidebar_tree.has_method("set_column_expand_ratio"):
			_sidebar_tree.call("set_column_expand_ratio", resolver_column, 2)
	var visibility_column := _sidebar_column_index(_COLUMN_VISIBILITY)
	_sidebar_tree.set_column_title(visibility_column, "")
	_sidebar_tree.set_column_custom_minimum_width(visibility_column, 60)


func _sidebar_column_index(logical_column: int) -> int:
	return int(_sidebar_column_indices.get(logical_column, -1))


func _sidebar_has_column(logical_column: int) -> bool:
	return _sidebar_column_indices.has(logical_column)


func _visible_sidebar_columns() -> Array[int]:
	var columns: Array[int] = []
	for logical_column in [_COLUMN_NAME, _COLUMN_VALUE, _COLUMN_DEFAULT, _COLUMN_RESOLVER, _COLUMN_VISIBILITY]:
		if _sidebar_has_column(logical_column):
			columns.append(_sidebar_column_index(logical_column))
	return columns


func _logical_sidebar_column(physical_column: int) -> int:
	for logical_column_variant in _sidebar_column_indices.keys():
		var logical_column := int(logical_column_variant)
		if _sidebar_column_index(logical_column) == physical_column:
			return logical_column
	return -1


func _set_item_metadata_all_columns(item: TreeItem, metadata: Dictionary) -> void:
	for logical_column in [_COLUMN_NAME, _COLUMN_VALUE, _COLUMN_DEFAULT, _COLUMN_RESOLVER, _COLUMN_VISIBILITY]:
		if _sidebar_has_column(logical_column):
			item.set_metadata(_sidebar_column_index(logical_column), metadata)


func _set_item_tooltip_all_columns(item: TreeItem, tooltip: String) -> void:
	for logical_column in [_COLUMN_NAME, _COLUMN_VALUE, _COLUMN_DEFAULT, _COLUMN_RESOLVER, _COLUMN_VISIBILITY]:
		if _sidebar_has_column(logical_column):
			item.set_tooltip_text(_sidebar_column_index(logical_column), tooltip)


func _set_item_tooltip(item: TreeItem, logical_column: int, tooltip: String) -> void:
	if item != null and _sidebar_has_column(logical_column):
		item.set_tooltip_text(_sidebar_column_index(logical_column), tooltip)


func _reset_visibility_to_default() -> void:
	var snapshot := _get_effective_snapshot()
	if snapshot.is_empty():
		return
	var states := _snapshot_dictionary_array(snapshot, "states")
	var transitions := _snapshot_dictionary_array(snapshot, "transitions")
	var connected_state_paths := _collect_connected_state_paths(transitions)
	for state_data in states:
		var state_path := str(state_data.get("path", ""))
		var node_id := "%s%s" % [_STATE_NODE_PREFIX, state_path]
		_persist_visibility(node_id, connected_state_paths.has(state_path))
	for transition_data in transitions:
		var transition_id := str(transition_data.get("transition_id", ""))
		var node_id := "%s%s" % [_TRANSITION_NODE_PREFIX, transition_id]
		_persist_visibility(node_id, true)
	_rebuild_from_current_state()


func _toggle_sidebar_graph_visibility_filter() -> void:
	_sidebar_filter_to_visible = not _sidebar_filter_to_visible
	if _sidebar_filter_visible_button != null:
		_sidebar_filter_visible_button.text = "Show All" if _sidebar_filter_to_visible else "Show Visible"
	var snapshot := _get_effective_snapshot()
	_rebuild_sidebar(snapshot.get("states", []), snapshot.get("transitions", []))


func focus_node(node_id: String) -> bool:
	if _graph_edit == null or not _nodes_by_id.has(node_id):
		return false
	var node := _nodes_by_id.get(node_id) as GraphNode
	if node == null or not node.visible:
		return false
	var viewport_graph_size := _graph_edit.size / maxf(_graph_edit.zoom, 0.001)
	var node_center := node.position_offset + node.size * 0.5
	var desired_offset := node_center - viewport_graph_size * 0.5
	_graph_edit.scroll_offset = _clamp_graph_scroll_offset(desired_offset)
	_capture_graph_view_transform_change()
	_queue_overlay_redraw()
	return true


func _clamp_graph_scroll_offset(offset: Vector2) -> Vector2:
	var result := offset
	if _graph_edit != null and _graph_edit.has_method("get_h_scroll_bar"):
		var horizontal_scroll := _graph_edit.call("get_h_scroll_bar") as Range
		if horizontal_scroll != null:
			result.x = clampf(result.x, horizontal_scroll.min_value, horizontal_scroll.max_value - horizontal_scroll.page)
	if _graph_edit != null and _graph_edit.has_method("get_v_scroll_bar"):
		var vertical_scroll := _graph_edit.call("get_v_scroll_bar") as Range
		if vertical_scroll != null:
			result.y = clampf(result.y, vertical_scroll.min_value, vertical_scroll.max_value - vertical_scroll.page)
	return result


func show_relevant(start_node_id: String) -> bool:
	var snapshot := _get_effective_snapshot()
	var adjacency: Dictionary = {}
	for state_variant in snapshot.get("states", []):
		var state_data: Dictionary = state_variant
		adjacency["%s%s" % [_STATE_NODE_PREFIX, str(state_data.get("path", ""))]] = []
	for transition_variant in snapshot.get("transitions", []):
		var transition_data: Dictionary = transition_variant
		var transition_node_id := "%s%s" % [_TRANSITION_NODE_PREFIX, str(transition_data.get("transition_id", ""))]
		adjacency[transition_node_id] = []
		for condition_variant in transition_data.get("conditions", []):
			var condition_data: Dictionary = condition_variant
			_connect_relation_nodes(adjacency, "%s%s" % [_STATE_NODE_PREFIX, str(condition_data.get("target_state_path", ""))], transition_node_id)
		for output_variant in transition_data.get("outputs", []):
			var output_data: Dictionary = output_variant
			_connect_relation_nodes(adjacency, transition_node_id, "%s%s" % [_STATE_NODE_PREFIX, str(output_data.get("target_state_path", ""))])
	if not adjacency.has(start_node_id):
		return false
	var related: Dictionary = {start_node_id: true}
	var queue: Array[String] = [start_node_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor_variant in adjacency.get(current, []):
			var neighbor := str(neighbor_variant)
			if related.has(neighbor):
				continue
			related[neighbor] = true
			queue.append(neighbor)
	for node_id_variant in adjacency.keys():
		var node_id := str(node_id_variant)
		_persist_visibility(node_id, related.has(node_id))
	_sidebar_filter_to_visible = true
	if _sidebar_filter_visible_button != null:
		_sidebar_filter_visible_button.text = "Show All"
	_rebuild_from_current_state()
	_auto_arrange_all_nodes()
	return true


func _show_only_relations_for_node_id(start_node_id: String) -> void:
	show_relevant(start_node_id)


func _connect_relation_nodes(adjacency: Dictionary, first: String, second: String) -> void:
	if not adjacency.has(first) or not adjacency.has(second):
		return
	(adjacency[first] as Array).append(second)
	(adjacency[second] as Array).append(first)


## Prefixes a state path into the graph node id [method focus_node] and
## [method show_relevant] expect.
func state_node_id(state_path: String) -> String:
	return "%s%s" % [_STATE_NODE_PREFIX, state_path]


## Returns the effective snapshot Dictionary for one transition, or an empty
## Dictionary when it has no current transition with that id.
func find_transition_snapshot(transition_id: int) -> Dictionary:
	var snapshot := _get_effective_snapshot()
	for transition_variant in snapshot.get("transitions", []):
		var transition_data: Dictionary = transition_variant
		if int(transition_data.get("transition_id", -1)) == transition_id:
			return transition_data
	return {}


## Builds the Outputs section for one transition using the exact same
## row/value-editor/commit/undo/save code paths as the graph's own transition
## nodes, for embedding outside the graph canvas (e.g. an Inspector). Ports
## are omitted since embedded rows are not part of the connection canvas.
func build_embedded_output_rows(transition_id: int) -> Array[Control]:
	var rows: Array[Control] = []
	var transition_data := find_transition_snapshot(transition_id)
	if transition_data.is_empty():
		return rows
	var transition_id_str := str(transition_id)
	var output_index := 0
	for output_variant in transition_data.get("outputs", []):
		var output_data: Dictionary = output_variant
		rows.append(_build_transition_output_row(transition_id_str, output_index, output_data, false))
		output_index += 1
	return rows


## Opens the same searchable output-target picker the graph's drag-to-connect
## flow uses, for a click-driven "Add Output" entry point. Selecting a target
## appends a new output on [param transition_id] through the graph's own
## commit/undo/save path.
func open_output_picker_for_transition(transition_id: int, screen_position: Vector2i = Vector2i(-1, -1)) -> bool:
	if database == null or _output_picker == null:
		return false
	var targets := _build_output_picker_targets(transition_id)
	if targets.is_empty():
		return false
	_output_picker_context = {
		"transition_id": transition_id,
	}
	_output_picker.call("configure", targets)
	var position := screen_position if screen_position != Vector2i(-1, -1) else DisplayServer.mouse_get_position()
	_output_picker.call("show_at", position)
	return true


func _on_state_graph_debug_mode_changed(mode: StringName) -> void:
	set_presentation_mode(String(mode))


func _normalize_presentation_mode(mode: String) -> String:
	match mode:
		"fullscreen_focused":
			return _PRESENTATION_MODE_SHOWN
		"fullscreen_overlay":
			return _PRESENTATION_MODE_TRANSPARENT_OVERLAY
		_:
			return mode


func _build_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_visible_icon = _make_eye_icon(true)
	_hidden_icon = _make_eye_icon(false)

	_background_dim = ColorRect.new()
	_background_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_background_dim)

	_graph_root = VBoxContainer.new()
	_graph_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_graph_root.add_theme_constant_override("separation", 8)
	add_child(_graph_root)

	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 8)
	_graph_root.add_child(_toolbar)

	var scope_label := Label.new()
	scope_label.text = "Scope"
	_toolbar.add_child(scope_label)
	_scope_selector = MenuButton.new()
	_scope_selector.custom_minimum_size.x = 220.0
	_scope_selector.flat = false
	_scope_selector.tooltip_text = "Choose which state machine the graph shows: the global machine, an entity type's authored template, or a live entity instance."
	_scope_selector.get_popup().id_pressed.connect(_on_scope_menu_id_pressed)
	_toolbar.add_child(_scope_selector)
	_scope_diagnostic_label = Label.new()
	_scope_diagnostic_label.add_theme_color_override("font_color", _TRANSITION_INVALID_COLOR)
	_scope_diagnostic_label.visible = false
	_toolbar.add_child(_scope_diagnostic_label)
	_rebuild_scope_selector()

	_toggle_sidebar_button = Button.new()
	_toggle_sidebar_button.pressed.connect(_toggle_sidebar_visibility)
	_toggle_sidebar_button.tooltip_text = "Show or hide the State Graph sidebar."
	_toolbar.add_child(_toggle_sidebar_button)

	_column_menu_button = MenuButton.new()
	_column_menu_button.text = "Columns"
	_column_menu_button.tooltip_text = "Choose which state metadata columns are shown in the sidebar."
	var column_popup := _column_menu_button.get_popup()
	column_popup.add_check_item("Default", _COLUMN_MENU_DEFAULT)
	column_popup.add_check_item("Resolver", _COLUMN_MENU_RESOLVER)
	column_popup.id_pressed.connect(_on_column_menu_id_pressed)
	_toolbar.add_child(_column_menu_button)

	_auto_arrange_button = Button.new()
	_auto_arrange_button.text = "Auto Arrange"
	_auto_arrange_button.tooltip_text = "Arrange visible states and transitions into a readable left-to-right graph."
	_auto_arrange_button.pressed.connect(_auto_arrange_all_nodes)
	_toolbar.add_child(_auto_arrange_button)

	_reset_visibility_button = Button.new()
	_reset_visibility_button.text = "Revert Shown"
	_reset_visibility_button.tooltip_text = "Restore default graph visibility: transitions and their connected states are shown."
	_reset_visibility_button.pressed.connect(_reset_visibility_to_default)
	_toolbar.add_child(_reset_visibility_button)

	_sidebar_filter_visible_button = Button.new()
	_sidebar_filter_visible_button.text = "Show Visible"
	_sidebar_filter_visible_button.tooltip_text = "Toggle the sidebar between every item and only graph-visible items. Search still checks all names."
	_sidebar_filter_visible_button.pressed.connect(_toggle_sidebar_graph_visibility_filter)
	_toolbar.add_child(_sidebar_filter_visible_button)

	var toolbar_spacer := Control.new()
	toolbar_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar.add_child(toolbar_spacer)

	_sidebar_split = HSplitContainer.new()
	_sidebar_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sidebar_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_root.add_child(_sidebar_split)

	_sidebar_panel = PanelContainer.new()
	_sidebar_panel.custom_minimum_size = Vector2(720.0, 0.0)
	_sidebar_split.add_child(_sidebar_panel)

	var sidebar_margin := MarginContainer.new()
	sidebar_margin.add_theme_constant_override("margin_left", 8)
	sidebar_margin.add_theme_constant_override("margin_top", 8)
	sidebar_margin.add_theme_constant_override("margin_right", 8)
	sidebar_margin.add_theme_constant_override("margin_bottom", 8)
	_sidebar_panel.add_child(sidebar_margin)

	var sidebar_content := VBoxContainer.new()
	sidebar_content.add_theme_constant_override("separation", 8)
	sidebar_margin.add_child(sidebar_content)

	_sidebar_search_edit = LineEdit.new()
	_sidebar_search_edit.placeholder_text = "Search states and transitions"
	_sidebar_search_edit.clear_button_enabled = true
	_sidebar_search_edit.tooltip_text = "Filter state paths/names and transition names without changing graph visibility."
	_sidebar_search_edit.text_changed.connect(_on_sidebar_search_text_changed)
	sidebar_content.add_child(_sidebar_search_edit)

	_sidebar_tree = Tree.new()
	_sidebar_tree.columns = 3
	_sidebar_tree.hide_root = true
	_sidebar_tree.select_mode = Tree.SELECT_ROW
	_sidebar_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sidebar_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sidebar_tree.custom_minimum_size = Vector2(680.0, 0.0)
	_sidebar_tree.set_column_titles_visible(true)
	_sidebar_tree.item_activated.connect(_on_sidebar_item_activated)
	_sidebar_tree.item_edited.connect(_on_sidebar_item_edited)
	_sidebar_tree.button_clicked.connect(_on_sidebar_button_clicked)
	_sidebar_tree.gui_input.connect(_on_sidebar_gui_input)
	sidebar_content.add_child(_sidebar_tree)

	_graph_panel = PanelContainer.new()
	_sidebar_split.add_child(_graph_panel)

	var graph_margin := MarginContainer.new()
	graph_margin.add_theme_constant_override("margin_left", 4)
	graph_margin.add_theme_constant_override("margin_top", 4)
	graph_margin.add_theme_constant_override("margin_right", 4)
	graph_margin.add_theme_constant_override("margin_bottom", 4)
	_graph_panel.add_child(graph_margin)

	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_edit.minimap_enabled = true
	_graph_edit.show_menu = false
	_graph_edit.gui_input.connect(_on_graph_edit_gui_input)
	_graph_edit.scroll_offset_changed.connect(_on_graph_view_transform_changed)
	if _graph_edit.has_signal("viewport_changed"):
		_graph_edit.connect("viewport_changed", _on_graph_viewport_changed)
	graph_margin.add_child(_graph_edit)
	_last_graph_view_transform = _graph_view_transform()

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_connections)
	_graph_edit.add_child(_overlay)

	_sidebar_context_menu = PopupMenu.new()
	_sidebar_context_menu.add_item("Remove Override", _SIDEBAR_CONTEXT_REMOVE_OVERRIDE)
	_sidebar_context_menu.add_item("Set Default From Resolved", _SIDEBAR_CONTEXT_SET_DEFAULT_FROM_RESOLVED)
	_sidebar_context_menu.add_separator()
	_sidebar_context_menu.add_item("Show Relevant", _SIDEBAR_CONTEXT_SHOW_RELEVANT)
	_sidebar_context_menu.add_item("Hide", _SIDEBAR_CONTEXT_HIDE)
	_sidebar_context_menu.add_item("Delete", _SIDEBAR_CONTEXT_DELETE)
	_sidebar_context_menu.id_pressed.connect(_on_sidebar_context_menu_id_pressed)
	add_child(_sidebar_context_menu)

	_canvas_context_menu = PopupMenu.new()
	_canvas_context_menu.add_item("New State", _CANVAS_CREATE_STATE)
	_canvas_context_menu.add_item("New Transition", _CANVAS_CREATE_TRANSITION)
	_canvas_context_menu.id_pressed.connect(_on_canvas_context_menu_id_pressed)
	add_child(_canvas_context_menu)

	_node_context_menu = PopupMenu.new()
	_node_context_menu.add_item("Show Relevant", _NODE_SHOW_RELEVANT)
	_node_context_menu.add_item("Hide", _NODE_HIDE)
	_node_context_menu.add_item("Delete", _NODE_DELETE)
	_node_context_menu.id_pressed.connect(_on_node_context_menu_id_pressed)
	add_child(_node_context_menu)

	_output_picker = StateGraphOutputPickerScene.instantiate() as PopupPanel
	_output_picker.connect("target_selected", _on_output_picker_target_selected)
	add_child(_output_picker)

	_override_dialog = ConfirmationDialog.new()
	_override_dialog.title = "Override State"
	_override_dialog.confirmed.connect(_apply_override_from_dialog)
	add_child(_override_dialog)

	_override_editor_host = VBoxContainer.new()
	_override_editor_host.custom_minimum_size = Vector2(260.0, 0.0)
	_override_dialog.add_child(_override_editor_host)

	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "Rename"
	_rename_dialog.confirmed.connect(_apply_rename_dialog)
	add_child(_rename_dialog)
	var rename_host := VBoxContainer.new()
	rename_host.custom_minimum_size = Vector2(320.0, 0.0)
	_rename_dialog.add_child(rename_host)
	var leaf_label := Label.new()
	leaf_label.text = "Name"
	rename_host.add_child(leaf_label)
	_rename_leaf_edit = LineEdit.new()
	rename_host.add_child(_rename_leaf_edit)
	var path_label := Label.new()
	path_label.text = "Full Path"
	rename_host.add_child(path_label)
	_rename_path_edit = LineEdit.new()
	rename_host.add_child(_rename_path_edit)
	var display_label := Label.new()
	display_label.text = "Display Name"
	rename_host.add_child(display_label)
	_rename_display_name_edit = LineEdit.new()
	rename_host.add_child(_rename_display_name_edit)

	_value_dialog = ConfirmationDialog.new()
	_value_dialog.title = "Edit Value"
	_value_dialog.confirmed.connect(_apply_value_dialog)
	add_child(_value_dialog)
	_value_editor_host = VBoxContainer.new()
	_value_editor_host.custom_minimum_size = Vector2(320.0, 0.0)
	_value_dialog.add_child(_value_editor_host)

	_apply_sidebar_visibility()
	_apply_sidebar_column_visibility()
	set_presentation_mode(presentation_mode)


func _rebuild_from_current_state() -> void:
	if _graph_edit == null or _sidebar_tree == null:
		return
	if not _is_graph_update_visible():
		_mark_graph_update_dirty()
		return
	_capture_sidebar_group_state()
	_clear_graph_nodes()
	_state_header_ports.clear()
	_state_claim_ports.clear()
	_transition_condition_ports.clear()
	_transition_output_ports.clear()
	_connections.clear()
	_connected_semantic_endpoints.clear()
	_ensure_preferences_loaded()
	_load_persisted_positions()

	var snapshot := _get_effective_snapshot()
	if snapshot.is_empty():
		_sidebar_tree.clear()
		_current_structure_signature = ""
		return

	var states := _snapshot_dictionary_array(snapshot, "states")
	var transitions := _snapshot_dictionary_array(snapshot, "transitions")
	var connected_state_paths := _collect_connected_state_paths(transitions)
	_initialize_default_visibility(states, transitions, connected_state_paths)
	_rebuild_sidebar(states, transitions)
	_rebuild_graph(states, transitions)
	_current_structure_signature = _build_structure_signature(snapshot)
	_sync_connection_visual_targets()
	_update_compact_graph_mode()
	_queue_overlay_redraw()


func _build_structure_signature(snapshot: Dictionary) -> String:
	var state_signatures: Array[String] = []
	for state_variant in snapshot.get("states", []):
		var state_data: Dictionary = state_variant
		# Runtime claim identifiers are deliberately excluded. Claims are local
		# state content, not database topology.
		state_signatures.append(str(state_data.get("path", "")))
	state_signatures.sort()
	var transition_signatures: Array[String] = []
	for transition_variant in snapshot.get("transitions", []):
		var transition_data: Dictionary = transition_variant
		var condition_parts: Array[String] = []
		for condition_variant in transition_data.get("conditions", []):
			var condition_data: Dictionary = condition_variant
			condition_parts.append("%s|%s" % [
				str(condition_data.get("target_state_path", "")),
				str(condition_data.get("operator", ""))
			])
		var output_parts: Array[String] = []
		for output_variant in transition_data.get("outputs", []):
			var output_data: Dictionary = output_variant
			output_parts.append("%s|%s|%s" % [
				str(output_data.get("target_state_path", "")),
				str(output_data.get("target_claim_slot_id", "")),
				str(output_data.get("operation", 0))
			])
		transition_signatures.append("%s::%s::%s" % [
			str(transition_data.get("transition_id", "")),
			",".join(condition_parts),
			",".join(output_parts)
		])
	transition_signatures.sort()
	return JSON.stringify({
		"states": state_signatures,
		"transitions": transition_signatures,
	})


func _refresh_from_snapshot(snapshot: Dictionary) -> void:
	if not _is_graph_update_visible():
		_mark_graph_update_dirty()
		return
	var states := _snapshot_dictionary_array(snapshot, "states")
	var transitions := _snapshot_dictionary_array(snapshot, "transitions")
	var connected_state_paths := _collect_connected_state_paths(transitions)
	_initialize_default_visibility(states, transitions, connected_state_paths)
	_rebuild_sidebar(states, transitions)
	_refresh_graph_visuals(states, transitions)
	_sync_connection_visual_targets()
	_update_compact_graph_mode()
	_queue_overlay_redraw()


func _get_effective_snapshot() -> Dictionary:
	if not runtime_snapshot.is_empty():
		return runtime_snapshot
	return _build_snapshot_from_database()


func _build_snapshot_from_database() -> Dictionary:
	if database == null:
		return {}
	var states: Array[Dictionary] = []
	var definitions: Array = database.get_state_definitions() if database.has_method("get_state_definitions") else []
	for definition_variant in definitions:
		var definition = definition_variant
		if definition == null:
			continue
		var claim_snapshots: Array[Dictionary] = []
		for claim_slot_variant in definition.get_claim_slot_definitions():
			var claim_slot = claim_slot_variant
			if claim_slot == null:
				continue
			claim_snapshots.append({
				"slot_id": String(claim_slot.get_normalized_slot_id()),
				"code_key": String(claim_slot.get_normalized_code_key()),
				"transition_id": claim_slot.get_normalized_transition_id(),
				"value": null,
				"active": false,
			})
		states.append({
			"path": String(definition.get_normalized_path()),
			"group": definition.get_group_name(),
			"name": definition.get_leaf_name(),
			"value_type": int(definition.value_type),
			"value_type_name": definition.get_value_type_name(),
			"resolver": int(definition.resolver),
			"resolver_name": definition.get_resolver_name(),
			"resolved_value": _serialize_state_value_for_snapshot(definition, definition.default_value),
			"default_value": _serialize_state_value_for_snapshot(definition, definition.default_value),
			"override_enabled": false,
			"override_value": null,
			"possible_values": definition.possible_values.duplicate(),
			"tags": definition.get_normalized_tags(),
			"graph_position": definition.graph_position,
			"claim_slots": claim_snapshots,
		})
	var transitions: Array[Dictionary] = []
	var transition_definitions: Array = database.get_transition_definitions() if database.has_method("get_transition_definitions") else []
	for transition_variant in transition_definitions:
		var transition_def = transition_variant
		if transition_def == null:
			continue
		var condition_snapshots: Array[Dictionary] = []
		for condition_variant in transition_def.conditions:
			var condition = condition_variant
			if condition == null:
				continue
			var target_definition = database.get_state_definition_by_path(String(condition.get_normalized_target_state_path()))
			condition_snapshots.append({
				"target_state_path": String(condition.get_normalized_target_state_path()),
				"operator": int(condition.operator),
				"expected_value": condition.get_expected_value(target_definition),
				"active": false,
			})
		var output_snapshots: Array[Dictionary] = []
		for output_variant in transition_def.outputs:
			var output_def = output_variant
			if output_def == null:
				continue
			var output_target_definition = database.get_state_definition_by_path(String(output_def.get_normalized_target_state_path()))
			output_snapshots.append({
				"target_state_path": String(output_def.get_normalized_target_state_path()),
				"target_claim_slot_id": String(output_def.get_normalized_target_claim_slot_id()),
				"operation": int(output_def.operation),
				"value": output_def.get_target_value(output_target_definition),
				"active": false,
			})
		transitions.append({
			"transition_id": transition_def.get_normalized_transition_id(),
			"display_name": transition_def.get_display_name(),
			"graph_position": transition_def.graph_position,
			"active": false,
			"invalid_reason": "",
			"conditions": condition_snapshots,
			"outputs": output_snapshots,
		})
	return {
		"mode": presentation_mode,
		"states": states,
		"transitions": transitions,
	}


func _collect_connected_state_paths(transitions: Array[Dictionary]) -> Dictionary:
	var connected: Dictionary = {}
	for transition_data in transitions:
		for condition_variant in transition_data.get("conditions", []):
			var condition_data: Dictionary = condition_variant
			var target_state_path := str(condition_data.get("target_state_path", ""))
			if not target_state_path.is_empty():
				connected[target_state_path] = true
		for output_variant in transition_data.get("outputs", []):
			var output_data: Dictionary = output_variant
			var output_state_path := str(output_data.get("target_state_path", ""))
			if not output_state_path.is_empty():
				connected[output_state_path] = true
	return connected


func _initialize_default_visibility(states: Array[Dictionary], transitions: Array[Dictionary], connected_state_paths: Dictionary) -> void:
	for state_data in states:
		var state_path := str(state_data.get("path", ""))
		var node_id := "%s%s" % [_STATE_NODE_PREFIX, state_path]
		if _node_visibility.has(node_id):
			continue
		_node_visibility[node_id] = connected_state_paths.has(state_path)
	for transition_data in transitions:
		var transition_id := str(transition_data.get("transition_id", ""))
		var node_id := "%s%s" % [_TRANSITION_NODE_PREFIX, transition_id]
		if not _node_visibility.has(node_id):
			_node_visibility[node_id] = true


func _rebuild_sidebar(states: Array[Dictionary], transitions: Array[Dictionary]) -> void:
	_sidebar_items_by_state_path.clear()
	_sidebar_items_by_transition_id.clear()
	_sidebar_tree.clear()
	var root := _sidebar_tree.create_item()
	var states_root := _sidebar_tree.create_item(root)
	_set_group_item_visual(states_root, "States", "root:states")
	var state_group_items: Dictionary = {}
	var sorted_states := states.duplicate()
	sorted_states.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("path", "")) < str(b.get("path", "")))
	for state_variant in sorted_states:
		var state_data: Dictionary = state_variant
		var state_node_id := "%s%s" % [_STATE_NODE_PREFIX, str(state_data.get("path", ""))]
		if _sidebar_search_query.is_empty() and _sidebar_filter_to_visible and not _as_bool(_node_visibility.get(state_node_id, false)):
			continue
		if not _sidebar_search_query.is_empty() and not _sidebar_search_matches_state(state_data):
			continue
		var path_parts: PackedStringArray = str(state_data.get("path", "")).split("/")
		var parent := states_root
		if path_parts.size() > 1:
			parent = _ensure_sidebar_group_path(states_root, state_group_items, path_parts.slice(0, path_parts.size() - 1), "states")
		_add_sidebar_state_item(parent, state_data)

	var transitions_item := _sidebar_tree.create_item(root)
	_set_group_item_visual(transitions_item, "Transitions", "root:transitions")
	var sorted_transitions := transitions.duplicate()
	sorted_transitions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _as_int(a.get("transition_id", 0)) < _as_int(b.get("transition_id", 0)))
	for transition_variant in sorted_transitions:
		var transition_data: Dictionary = transition_variant
		var transition_node_id := "%s%s" % [_TRANSITION_NODE_PREFIX, str(transition_data.get("transition_id", ""))]
		if _sidebar_search_query.is_empty() and _sidebar_filter_to_visible and not _as_bool(_node_visibility.get(transition_node_id, true)):
			continue
		if not _sidebar_search_query.is_empty() and not _sidebar_search_matches_transition(transition_data):
			continue
		_add_sidebar_transition_item(transitions_item, transition_data)


func _on_sidebar_search_text_changed(text: String) -> void:
	_sidebar_search_query = text.strip_edges().to_lower()
	var snapshot := _get_effective_snapshot()
	_rebuild_sidebar(
		_snapshot_dictionary_array(snapshot, "states"),
		_snapshot_dictionary_array(snapshot, "transitions")
	)


func _sidebar_search_matches_state(state_data: Dictionary) -> bool:
	var searchable := "%s %s" % [
		str(state_data.get("path", "")),
		str(state_data.get("name", "")),
	]
	return searchable.to_lower().contains(_sidebar_search_query)


func _sidebar_search_matches_transition(transition_data: Dictionary) -> bool:
	var searchable := "%s %s" % [
		str(transition_data.get("transition_id", "")),
		str(transition_data.get("display_name", "")),
	]
	return searchable.to_lower().contains(_sidebar_search_query)


func _ensure_sidebar_group_path(parent_root: TreeItem, group_items: Dictionary, group_parts: Array, group_namespace: String) -> TreeItem:
	var parent := parent_root
	var group_key := group_namespace
	for group_part_variant in group_parts:
		var group_part := str(group_part_variant)
		group_key = "%s/%s" % [group_key, group_part]
		if not group_items.has(group_key):
			var group_item := _sidebar_tree.create_item(parent)
			_set_group_item_visual(group_item, group_part, group_key)
			group_items[group_key] = group_item
		parent = group_items[group_key]
	return parent


func _set_group_item_visual(item: TreeItem, label: String, group_key: String) -> void:
	item.set_text(_sidebar_column_index(_COLUMN_NAME), label)
	for logical_column in [_COLUMN_VALUE, _COLUMN_DEFAULT, _COLUMN_RESOLVER, _COLUMN_VISIBILITY]:
		if _sidebar_has_column(logical_column):
			item.set_text(_sidebar_column_index(logical_column), "")
	_set_item_metadata_all_columns(item, {"kind": "group", "group_key": group_key})
	item.collapsed = _as_bool(_group_collapsed.get("group:%s" % group_key, false))
	_apply_tree_row_style(item, _neutral_tree_row_background(), Color(0.88, 0.88, 0.92, 1.0))


func _add_sidebar_state_item(parent: TreeItem, state_data: Dictionary) -> void:
	var item := _sidebar_tree.create_item(parent)
	var state_path := str(state_data.get("path", ""))
	var node_id := "%s%s" % [_STATE_NODE_PREFIX, state_path]
	item.set_text(_sidebar_column_index(_COLUMN_NAME), str(state_data.get("name", state_path)))
	item.set_editable(_sidebar_column_index(_COLUMN_NAME), true)
	_set_item_metadata_all_columns(item, {"kind": "state", "path": state_path, "data": state_data})
	_configure_state_sidebar_cells(item, state_data)
	_configure_state_sidebar_tooltips(item, state_data)
	_apply_tree_row_style(item, _state_row_background_color(state_data), Color(0.95, 0.95, 0.98, 1.0), Color.WHITE)
	item.add_button(_sidebar_column_index(_COLUMN_VISIBILITY), _visible_icon if _as_bool(_node_visibility.get(node_id, false)) else _hidden_icon, _SIDEBAR_BUTTON_ID_VISIBILITY, false, "Toggle graph visibility")
	_sidebar_items_by_state_path[state_path] = item


func _add_sidebar_transition_item(parent: TreeItem, transition_data: Dictionary) -> void:
	var item := _sidebar_tree.create_item(parent)
	var transition_id := str(transition_data.get("transition_id", ""))
	var node_id := "%s%s" % [_TRANSITION_NODE_PREFIX, transition_id]
	var display_name := str(transition_data.get("display_name", transition_id))
	item.set_text(_sidebar_column_index(_COLUMN_NAME), display_name)
	item.set_editable(_sidebar_column_index(_COLUMN_NAME), true)
	item.set_text(_sidebar_column_index(_COLUMN_VALUE), _transition_status_text(transition_data))
	for logical_column in [_COLUMN_DEFAULT, _COLUMN_RESOLVER]:
		if _sidebar_has_column(logical_column):
			item.set_text(_sidebar_column_index(logical_column), "")
	_set_item_metadata_all_columns(item, {"kind": "transition", "transition_id": transition_id, "data": transition_data})
	_configure_transition_sidebar_tooltips(item, transition_data)
	_apply_tree_row_style(item, _transition_row_background_color(transition_data), Color.WHITE, Color.WHITE)
	item.add_button(_sidebar_column_index(_COLUMN_VISIBILITY), _visible_icon if _as_bool(_node_visibility.get(node_id, true)) else _hidden_icon, _SIDEBAR_BUTTON_ID_VISIBILITY, false, "Toggle graph visibility")
	_sidebar_items_by_transition_id[transition_id] = item


func _refresh_sidebar_state_item(state_path: String, state_data: Dictionary) -> void:
	var item := _sidebar_items_by_state_path.get(state_path) as TreeItem
	if item == null:
		return
	_set_item_metadata_all_columns(item, {"kind": "state", "path": state_path, "data": state_data})
	_configure_state_sidebar_cells(item, state_data)
	_configure_state_sidebar_tooltips(item, state_data)
	_apply_tree_row_style(item, _state_row_background_color(state_data), Color(0.95, 0.95, 0.98, 1.0), Color.WHITE)


func _refresh_sidebar_transition_item(transition_id: String, transition_data: Dictionary) -> void:
	var item := _sidebar_items_by_transition_id.get(transition_id) as TreeItem
	if item == null:
		return
	item.set_text(_sidebar_column_index(_COLUMN_VALUE), _transition_status_text(transition_data))
	_set_item_metadata_all_columns(item, {"kind": "transition", "transition_id": transition_id, "data": transition_data})
	_configure_transition_sidebar_tooltips(item, transition_data)
	_apply_tree_row_style(item, _transition_row_background_color(transition_data), Color.WHITE, Color.WHITE)


func _rebuild_graph(states: Array[Dictionary], transitions: Array[Dictionary]) -> void:
	var visible_states: Array[Dictionary] = []
	var visible_transitions: Array[Dictionary] = []
	for state_data in states:
		var state_path := str(state_data.get("path", ""))
		if _as_bool(_node_visibility.get("%s%s" % [_STATE_NODE_PREFIX, state_path], false)):
			visible_states.append(state_data)
	for transition_data in transitions:
		var transition_id := str(transition_data.get("transition_id", ""))
		if _as_bool(_node_visibility.get("%s%s" % [_TRANSITION_NODE_PREFIX, transition_id], true)):
			visible_transitions.append(transition_data)

	for state_data in visible_states:
		_add_state_node(state_data)
	for transition_data in visible_transitions:
		_add_transition_node(transition_data)
	for transition_data in visible_transitions:
		_build_connections_for_transition(transition_data)

	if _has_missing_positions(visible_states, visible_transitions):
		_auto_arrange_missing_nodes(visible_states, visible_transitions)
	if _graph_edit != null and _overlay != null:
		_graph_edit.move_child(_overlay, _graph_edit.get_child_count() - 1)
	_sync_connection_visual_targets()


func _refresh_graph_visuals(states: Array[Dictionary], transitions: Array[Dictionary]) -> void:
	_connections.clear()
	_state_header_ports.clear()
	_state_claim_ports.clear()
	_transition_condition_ports.clear()
	_transition_output_ports.clear()
	_claim_row_panels.clear()
	var states_by_path: Dictionary = {}
	for state_data in states:
		states_by_path[str(state_data.get("path", ""))] = state_data
	var transitions_by_id: Dictionary = {}
	for transition_data in transitions:
		transitions_by_id[str(transition_data.get("transition_id", ""))] = transition_data
	for node_id_variant in _nodes_by_id.keys():
		var node_id := str(node_id_variant)
		if node_id.begins_with(_STATE_NODE_PREFIX):
			var state_path := node_id.trim_prefix(_STATE_NODE_PREFIX)
			if states_by_path.has(state_path):
				_refresh_state_node(_nodes_by_id[node_id] as GraphNode, states_by_path[state_path])
		elif node_id.begins_with(_TRANSITION_NODE_PREFIX):
			var transition_id := node_id.trim_prefix(_TRANSITION_NODE_PREFIX)
			if transitions_by_id.has(transition_id):
				_refresh_transition_node(_nodes_by_id[node_id] as GraphNode, transitions_by_id[transition_id])
	for transition_data in _filtered_visible_transitions(transitions):
		_build_connections_for_transition(transition_data)
	if _graph_edit != null and _overlay != null:
		_graph_edit.move_child(_overlay, _graph_edit.get_child_count() - 1)


func _refresh_state_node(node: GraphNode, state_data: Dictionary, rebuild_claim_rows: bool = true) -> void:
	if node == null:
		return
	var state_path := str(state_data.get("path", ""))
	_set_graph_node_title(node, str(state_data.get("name", "State")))
	var compact_title := node.get_node_or_null("CompactTitle") as Label
	if compact_title != null:
		compact_title.text = str(state_data.get("name", "State"))
		_fit_compact_title(compact_title, node, compact_title.text)
	_sync_state_titlebar_controls(node, state_data)
	var header_port := node.get_node_or_null("Body/HeaderRow/HeaderPort") as Control
	if header_port != null:
		_state_header_ports[state_path] = header_port
		_assign_port_metadata(header_port, {
			"role": "state_header",
			"state_path": state_path,
		})
	var resolved_label := node.get_node_or_null("Body/ResolvedRow/ResolvedValueLabel") as Label
	if resolved_label != null:
		resolved_label.text = str(state_data.get("resolved_value", ""))
		resolved_label.modulate = _resolved_value_color(state_data)
		resolved_label.add_theme_font_size_override("font_size", 56)
	var resolver_editor := node.get_node_or_null("Body/ResolvedRow/ResolverEditor") as OptionButton
	if resolver_editor != null:
		_populate_resolver_option_button(resolver_editor, state_data)
	var override_editor_host := node.get_node_or_null("Body/OverrideRow/Content/EditorHost") as Control
	if override_editor_host != null:
		_rebuild_value_editor_host(override_editor_host, _build_state_override_editor(state_path, state_data))
	var default_editor_host := node.get_node_or_null("Body/DefaultRow/Content/EditorHost") as Control
	if default_editor_host != null:
		_rebuild_value_editor_host(
			default_editor_host,
			_build_inline_value_editor(
				_database_state_definition(state_path),
				state_data.get("default_value", null),
				Callable(self, "_commit_state_default_value").bind(state_path)
			)
		)
	var claims_container := node.get_node_or_null("Body/ClaimsContainer") as VBoxContainer
	if claims_container != null:
		if rebuild_claim_rows:
			for key_variant in _claim_row_panels.keys():
				if str(key_variant).begins_with("%s::" % state_path):
					_claim_row_panels.erase(key_variant)
			_clear_container_children(claims_container)
			for claim_variant in state_data.get("claim_slots", []):
				claims_container.add_child(_build_claim_row(state_path, claim_variant))
			claims_container.add_child(_build_claim_plus_row(state_path))
		else:
			_refresh_existing_claim_rows(state_path, state_data)
	_apply_state_node_style(node, state_data)
	var body := node.get_node_or_null("Body") as Control
	if body != null:
		_finalize_node_width(node, body, _GRAPH_NODE_FIXED_WIDTH)


func _claim_membership_signature(state_data: Dictionary) -> String:
	var claim_keys: Array[String] = []
	for claim_variant in state_data.get("claim_slots", []):
		var claim_data: Dictionary = claim_variant
		claim_keys.append("%s|%s|%s" % [
			str(claim_data.get("slot_id", "")),
			str(claim_data.get("code_key", "")),
			str(claim_data.get("transition_id", 0)),
		])
	return ",".join(claim_keys)


func _refresh_existing_claim_rows(state_path: String, state_data: Dictionary) -> void:
	for claim_variant in state_data.get("claim_slots", []):
		var claim_data: Dictionary = claim_variant
		var slot_id := str(claim_data.get("slot_id", ""))
		var panel := _claim_row_panels.get("%s::%s" % [state_path, slot_id]) as PanelContainer
		if panel == null:
			continue
		var value_label := panel.get_node_or_null("Content/EntryContent/ValueRow/ValueLabel") as Label
		var active := _as_bool(claim_data.get("active", false))
		if value_label != null:
			value_label.text = str(claim_data.get("value", "")) if active else ""
			value_label.modulate = Color.WHITE if active else Color(0.72, 0.72, 0.76, 0.5)
		var current_style := panel.get_theme_stylebox("panel") as StyleBoxFlat
		if current_style != null:
			var next_style := current_style.duplicate() as StyleBoxFlat
			next_style.bg_color = _claim_row_background_color(claim_data)
			panel.add_theme_stylebox_override("panel", next_style)


func _refresh_incremental_connections(
	transitions: Array,
	changed_state_paths: Array[String],
	changed_transition_ids: Array[String]
) -> void:
	var affected_transition_ids: Dictionary = {}
	for transition_id in changed_transition_ids:
		affected_transition_ids[transition_id] = true
	for transition_variant in transitions:
		var transition_data: Dictionary = transition_variant
		var transition_id := str(transition_data.get("transition_id", ""))
		for condition_variant in transition_data.get("conditions", []):
			var condition_data: Dictionary = condition_variant
			if changed_state_paths.has(str(condition_data.get("target_state_path", ""))):
				affected_transition_ids[transition_id] = true
		for output_variant in transition_data.get("outputs", []):
			var output_data: Dictionary = output_variant
			if changed_state_paths.has(str(output_data.get("target_state_path", ""))):
				affected_transition_ids[transition_id] = true
	var retained_connections: Array[Dictionary] = []
	for connection_variant in _connections:
		var connection: Dictionary = connection_variant
		if not affected_transition_ids.has(str(connection.get("transition_id", ""))):
			retained_connections.append(connection)
	_connections = retained_connections
	for transition_data in _filtered_visible_transitions(transitions):
		if affected_transition_ids.has(str(transition_data.get("transition_id", ""))):
			_build_connections_for_transition(transition_data)
	_rebuild_connected_semantic_endpoints()


func _refresh_transition_node(node: GraphNode, transition_data: Dictionary) -> void:
	if node == null:
		return
	var transition_id := str(transition_data.get("transition_id", ""))
	_set_graph_node_title(node, str(transition_data.get("display_name", transition_id)))
	var compact_title := node.get_node_or_null("CompactTitle") as Label
	if compact_title != null:
		compact_title.text = str(transition_data.get("display_name", transition_id))
		_fit_compact_title(compact_title, node, compact_title.text)
	var body := node.get_node_or_null("Body") as VBoxContainer
	if body == null:
		return
	var invalid_label := body.get_node_or_null("InvalidLabel") as Label
	var invalid_reason := str(transition_data.get("invalid_reason", ""))
	if invalid_reason.is_empty():
		if invalid_label != null:
			invalid_label.visible = false
	else:
		if invalid_label == null:
			invalid_label = Label.new()
			invalid_label.name = "InvalidLabel"
			body.add_child(invalid_label)
			body.move_child(invalid_label, 0)
		invalid_label.visible = true
		invalid_label.text = "Invalid: %s" % invalid_reason
		invalid_label.modulate = _TRANSITION_INVALID_COLOR
	var conditions_container := body.get_node_or_null("ConditionsContainer") as VBoxContainer
	if conditions_container != null:
		_clear_container_children(conditions_container)
		var condition_index := 0
		for condition_variant in transition_data.get("conditions", []):
			conditions_container.add_child(_build_transition_condition_row(transition_id, condition_index, condition_variant))
			condition_index += 1
		conditions_container.add_child(_build_transition_condition_plus_row(transition_id))
	var outputs_container := body.get_node_or_null("OutputsContainer") as VBoxContainer
	if outputs_container != null:
		_clear_container_children(outputs_container)
		var output_index := 0
		for output_variant in transition_data.get("outputs", []):
			outputs_container.add_child(_build_transition_output_row(transition_id, output_index, output_variant))
			output_index += 1
		outputs_container.add_child(_build_transition_output_plus_row(transition_id))
	_apply_transition_node_style(node, _as_bool(transition_data.get("active", false)))
	_finalize_node_width(node, body, _GRAPH_NODE_FIXED_WIDTH)


func _clear_graph_nodes() -> void:
	if _graph_edit == null:
		return
	for child in _graph_edit.get_children():
		if child == _overlay:
			continue
		if child is GraphNode:
			child.queue_free()
	_nodes_by_id.clear()
	_claim_row_panels.clear()


func _create_graph_node_shell(node_id: String, title_text: String, authored_position: Variant) -> Dictionary:
	var node := GraphNode.new()
	node.name = node_id
	node.gui_input.connect(_on_graph_node_gui_input.bind(node_id))
	_set_graph_node_title(node, title_text)
	node.position_offset = _position_for_node(node_id, authored_position)
	node.resizable = false
	node.custom_minimum_size = Vector2(_GRAPH_NODE_FIXED_WIDTH, _GRAPH_NODE_MIN_HEIGHT)
	node.size = node.custom_minimum_size

	var compact_title := Label.new()
	compact_title.name = "CompactTitle"
	compact_title.text = title_text
	compact_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	compact_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	compact_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	compact_title.size_flags_vertical = Control.SIZE_EXPAND_FILL
	compact_title.add_theme_font_size_override("font_size", 42)
	compact_title.visible = false
	node.add_child(compact_title)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	body.custom_minimum_size.x = _GRAPH_NODE_FIXED_WIDTH - 26.0
	node.add_child(body)
	return {
		"node": node,
		"body": body,
		"compact_title": compact_title,
	}


func _build_node_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.modulate = Color(0.83, 0.84, 0.88, 0.94)
	return label


func _build_graph_entry_row(entry_name: String, config: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = entry_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = config.get("background_color", Color(0.16, 0.16, 0.18, 0.96))
	style.border_color = config.get("border_color", Color(0.28, 0.28, 0.32, 0.95))
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = _GRAPH_ENTRY_RADIUS
	style.corner_radius_top_right = _GRAPH_ENTRY_RADIUS
	style.corner_radius_bottom_left = _GRAPH_ENTRY_RADIUS
	style.corner_radius_bottom_right = _GRAPH_ENTRY_RADIUS
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.name = "Content"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var left_port_info_variant: Variant = config.get("left_port_info", {})
	var left_port_info: Dictionary = left_port_info_variant if left_port_info_variant is Dictionary else {}
	if not left_port_info.is_empty():
		var left_port_color: Color = config.get("left_port_color", Color(0.92, 0.92, 0.97, 1.0))
		var left_port := _make_port(left_port_color, left_port_info)
		left_port.name = "LeftPort"
		row.add_child(left_port)
		var register_left: Callable = config.get("register_left_port", Callable())
		if register_left.is_valid():
			register_left.call(left_port)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = _GRAPH_ENTRY_PORT_SPACER
		row.add_child(spacer)

	var content := VBoxContainer.new()
	content.name = "EntryContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	row.add_child(content)

	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_theme_constant_override("separation", 6)
	content.add_child(name_row)

	var name_editor := config.get("name_editor") as Control
	if name_editor != null:
		name_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_row.add_child(name_editor)
	else:
		var name_label := Label.new()
		name_label.name = "NameLabel"
		name_label.text = str(config.get("name_text", ""))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", int(config.get("name_font_size", 18)))
		name_label.modulate = config.get("name_color", Color(0.95, 0.95, 0.98, 1.0))
		name_row.add_child(name_label)

	var value_row := HBoxContainer.new()
	value_row.name = "ValueRow"
	value_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_row.add_theme_constant_override("separation", 6)
	content.add_child(value_row)

	var value_editor := config.get("value_editor") as Control
	if value_editor != null:
		value_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_row.add_child(value_editor)
	else:
		var value_label := Label.new()
		value_label.name = "ValueLabel"
		value_label.text = str(config.get("value_text", ""))
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.add_theme_font_size_override("font_size", int(config.get("value_font_size", 17)))
		value_label.modulate = config.get("value_color", Color(0.83, 0.84, 0.9, 0.96))
		value_row.add_child(value_label)

	var actions_variant: Variant = config.get("buttons", [])
	var actions: Array = actions_variant if actions_variant is Array else []
	if not actions.is_empty():
		var actions_box := HBoxContainer.new()
		actions_box.name = "Actions"
		actions_box.add_theme_constant_override("separation", 4)
		row.add_child(actions_box)
		for action_variant in actions:
			if not (action_variant is Dictionary):
				continue
			var action: Dictionary = action_variant
			var button := Button.new()
			button.flat = false
			button.focus_mode = Control.FOCUS_CLICK
			button.text = str(action.get("text", ""))
			button.tooltip_text = str(action.get("tooltip", ""))
			button.custom_minimum_size = Vector2(30.0, 28.0)
			var pressed_callable: Callable = action.get("pressed", Callable())
			if pressed_callable.is_valid():
				button.pressed.connect(pressed_callable)
			var gui_input_callable: Callable = action.get("gui_input", Callable())
			if gui_input_callable.is_valid():
				button.gui_input.connect(gui_input_callable)
			actions_box.add_child(button)

	var right_port_info_variant: Variant = config.get("right_port_info", {})
	var right_port_info: Dictionary = right_port_info_variant if right_port_info_variant is Dictionary else {}
	if not right_port_info.is_empty():
		var right_port_color: Color = config.get("right_port_color", Color(0.92, 0.92, 0.97, 1.0))
		var right_port := _make_port(right_port_color, right_port_info)
		right_port.name = "RightPort"
		row.add_child(right_port)
		var register_right: Callable = config.get("register_right_port", Callable())
		if register_right.is_valid():
			register_right.call(right_port)
	elif _as_bool(config.get("reserve_right_port_space", false)):
		var right_spacer := Control.new()
		right_spacer.custom_minimum_size = _GRAPH_ENTRY_PORT_SPACER
		row.add_child(right_spacer)

	return panel


func _add_state_node(state_data: Dictionary) -> void:
	var state_path := str(state_data.get("path", ""))
	var node_id := "%s%s" % [_STATE_NODE_PREFIX, state_path]
	var shell := _create_graph_node_shell(node_id, str(state_data.get("name", "State")), state_data.get("graph_position", Vector2.ZERO))
	var node := shell.get("node") as GraphNode
	var body := shell.get("body") as VBoxContainer
	_apply_state_node_style(node, state_data)

	var header := HBoxContainer.new()
	header.name = "HeaderRow"
	header.add_theme_constant_override("separation", 6)
	body.add_child(header)
	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)
	var header_port := _make_port(Color(0.95, 0.95, 1.0, 1.0), {
		"role": "state_header",
		"state_path": state_path,
	})
	header_port.name = "HeaderPort"
	header.add_child(header_port)
	_state_header_ports[state_path] = header_port

	var resolved_row := HBoxContainer.new()
	resolved_row.name = "ResolvedRow"
	resolved_row.add_theme_constant_override("separation", 10)
	body.add_child(resolved_row)
	var resolved_label := Label.new()
	resolved_label.name = "ResolvedValueLabel"
	resolved_label.text = str(state_data.get("resolved_value", ""))
	resolved_label.modulate = _resolved_value_color(state_data)
	resolved_label.add_theme_font_size_override("font_size", 56)
	resolved_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resolved_row.add_child(resolved_label)
	var resolver_editor := OptionButton.new()
	resolver_editor.name = "ResolverEditor"
	_populate_resolver_option_button(resolver_editor, state_data)
	resolver_editor.item_selected.connect(_on_state_resolver_selected.bind(state_path, resolver_editor))
	resolved_row.add_child(resolver_editor)

	body.add_child(_build_named_state_value_row("OverrideRow", state_path, "override", _build_state_override_editor(state_path, state_data), _as_bool(state_data.get("override_enabled", false))))

	body.add_child(_build_node_section_label("Claims"))
	var claims_container := VBoxContainer.new()
	claims_container.name = "ClaimsContainer"
	claims_container.add_theme_constant_override("separation", 6)
	body.add_child(claims_container)
	for claim_variant in state_data.get("claim_slots", []):
		var claim_snapshot: Dictionary = claim_variant
		claims_container.add_child(_build_claim_row(state_path, claim_snapshot))
	claims_container.add_child(_build_claim_plus_row(state_path))

	body.add_child(_build_named_state_value_row("DefaultRow", state_path, "default", _build_inline_value_editor(
		_database_state_definition(state_path),
		state_data.get("default_value", null),
		Callable(self, "_commit_state_default_value").bind(state_path)
	), false))
	body.add_child(_build_named_state_value_row("TagsRow", state_path, "tags", _build_state_tags_editor(state_path, state_data), false))

	_finalize_node_width(node, body, _GRAPH_NODE_FIXED_WIDTH)
	_graph_edit.add_child(node)
	_nodes_by_id[node_id] = node
	_sync_state_titlebar_controls(node, state_data)
	_apply_compact_mode_to_node(node)


func _build_claim_row(state_path: String, claim_snapshot: Dictionary) -> Control:
	var source_name := _claim_source_name(claim_snapshot)
	var slot_id := str(claim_snapshot.get("slot_id", ""))
	var has_transition_binding := not (str(claim_snapshot.get("transition_id", 0)) in ["", "0"])
	var name_editor: Control = null
	if not has_transition_binding:
		var inline_name_editor := LineEdit.new()
		inline_name_editor.name = "ClaimNameEditor"
		inline_name_editor.flat = false
		inline_name_editor.text = source_name
		inline_name_editor.text_submitted.connect(_on_claim_name_submitted.bind(state_path, slot_id, inline_name_editor))
		inline_name_editor.focus_exited.connect(_on_claim_name_focus_exited.bind(state_path, slot_id, inline_name_editor))
		name_editor = inline_name_editor
		if _pending_claim_edit_state_path == state_path and _pending_claim_edit_slot_id == slot_id:
			call_deferred("_focus_claim_name_editor", inline_name_editor)
	var buttons: Array = []
	var state_snapshot := _find_state_snapshot(state_path)
	var is_ordered := _as_bool(state_snapshot.get("resolver", -1) == int(StateVariableDefScript.Resolver.ORDERED))
	if is_ordered:
		buttons.append({
			"text": "≡",
			"tooltip": "Drag to reorder claim",
			"gui_input": Callable(self, "_on_claim_handle_gui_input").bind(state_path, slot_id),
		})
	buttons.append({
		"text": "×",
		"tooltip": "Delete claim",
		"pressed": _delete_claim_slot.bind(state_path, slot_id),
	})
	var panel := _build_graph_entry_row(slot_id, {
		"background_color": _claim_row_background_color(claim_snapshot),
		"border_color": Color(0.3, 0.3, 0.34, 0.9),
		"left_port_info": {
			"role": "state_claim",
			"state_path": state_path,
			"slot_id": slot_id,
		},
		"register_left_port": func(port: Control) -> void:
			_state_claim_ports["%s::%s" % [state_path, slot_id]] = port,
		"name_text": source_name,
		"name_editor": name_editor,
		"value_text": str(claim_snapshot.get("value", "")) if _as_bool(claim_snapshot.get("active", false)) else "",
		"value_color": Color.WHITE if _as_bool(claim_snapshot.get("active", false)) else Color(0.72, 0.72, 0.76, 0.5),
		"buttons": buttons,
	})
	_claim_row_panels["%s::%s" % [state_path, slot_id]] = panel
	return panel


func _claim_row_background_color(claim_snapshot: Dictionary) -> Color:
	if not _as_bool(claim_snapshot.get("active", false)):
		return Color(0.16, 0.16, 0.18, 0.95)
	if _as_bool(claim_snapshot.get("suppressed_by_resolution", false)):
		return Color(_STATE_SUPPRESSED_COLOR.r, _STATE_SUPPRESSED_COLOR.g, _STATE_SUPPRESSED_COLOR.b, 0.95)
	return Color(0.1, 0.22, 0.45, 0.95)


func _build_claim_plus_row(state_path: String) -> Control:
	var panel := _build_graph_entry_row("ClaimPlus", {
		"background_color": Color(0.16, 0.16, 0.18, 0.82),
		"left_port_info": {
			"role": "state_claim_new",
			"state_path": state_path,
		},
		"register_left_port": func(port: Control) -> void:
			_state_claim_ports["%s::new" % state_path] = port,
		"name_text": "+",
		"value_text": "Add claim",
		"buttons": [{
			"text": "+",
			"tooltip": "Create claim",
			"pressed": _create_new_code_claim.bind(state_path),
		}],
	})
	return panel


func _build_named_state_value_row(row_name: String, state_path: String, label_text: String, editor: Control, show_clear_button: bool) -> Control:
	var buttons: Array = []
	if show_clear_button:
		buttons.append({
			"text": "×",
			"tooltip": "Clear override",
			"pressed": _clear_state_override.bind(state_path),
		})
	return _build_graph_entry_row(row_name, {
		"background_color": Color(0.16, 0.16, 0.18, 0.95),
		"border_color": Color(0.3, 0.3, 0.34, 0.9),
		"name_text": label_text,
		"value_editor": editor,
		"buttons": buttons,
	})


func _add_transition_node(transition_data: Dictionary) -> void:
	var transition_id := str(transition_data.get("transition_id", ""))
	var node_id := "%s%s" % [_TRANSITION_NODE_PREFIX, transition_id]
	var shell := _create_graph_node_shell(node_id, str(transition_data.get("display_name", transition_id)), transition_data.get("graph_position", Vector2.ZERO))
	var node := shell.get("node") as GraphNode
	var body := shell.get("body") as VBoxContainer
	_apply_transition_node_style(node, _as_bool(transition_data.get("active", false)))

	var invalid_reason := str(transition_data.get("invalid_reason", ""))
	if not invalid_reason.is_empty():
		var invalid_label := Label.new()
		invalid_label.name = "InvalidLabel"
		invalid_label.text = "Invalid: %s" % invalid_reason
		invalid_label.modulate = _TRANSITION_INVALID_COLOR
		body.add_child(invalid_label)

	body.add_child(_build_node_section_label("Conditions"))
	var conditions_container := VBoxContainer.new()
	conditions_container.name = "ConditionsContainer"
	conditions_container.add_theme_constant_override("separation", 6)
	body.add_child(conditions_container)
	var condition_index := 0
	for condition_variant in transition_data.get("conditions", []):
		var condition_data: Dictionary = condition_variant
		conditions_container.add_child(_build_transition_condition_row(transition_id, condition_index, condition_data))
		condition_index += 1
	conditions_container.add_child(_build_transition_condition_plus_row(transition_id))

	body.add_child(_build_node_section_label("Outputs"))
	var outputs_container := VBoxContainer.new()
	outputs_container.name = "OutputsContainer"
	outputs_container.add_theme_constant_override("separation", 6)
	body.add_child(outputs_container)
	var output_index := 0
	for output_variant in transition_data.get("outputs", []):
		var output_data: Dictionary = output_variant
		outputs_container.add_child(_build_transition_output_row(transition_id, output_index, output_data))
		output_index += 1
	outputs_container.add_child(_build_transition_output_plus_row(transition_id))

	_finalize_node_width(node, body, _GRAPH_NODE_FIXED_WIDTH)
	_graph_edit.add_child(node)
	_nodes_by_id[node_id] = node
	_apply_compact_mode_to_node(node)


func _build_transition_condition_row(transition_id: String, condition_index: int, condition_data: Dictionary) -> Control:
	var target_state_path := str(condition_data.get("target_state_path", ""))
	var target_definition: StateVariableDefScript = database.get_state_definition_by_path(target_state_path) if database != null else null
	var editor := _build_transition_condition_value_editor(
		int(transition_id),
		condition_index,
		target_definition,
		condition_data
	)
	var operator_label := _condition_operator_label(int(condition_data.get("operator", 0)))
	return _build_graph_entry_row("Condition_%d" % condition_index, {
		"background_color": Color(0.15, 0.35, 0.18, 0.95) if _as_bool(condition_data.get("active", false)) else Color(0.18, 0.18, 0.2, 0.95),
		"left_port_info": {
			"role": "transition_condition",
			"transition_id": transition_id,
			"condition_index": condition_index,
		},
		"register_left_port": func(port: Control) -> void:
			_transition_condition_ports["%s::%d" % [transition_id, condition_index]] = port,
		"name_text": "%s %s" % [target_state_path, operator_label],
		"value_editor": editor,
	})


func _build_transition_condition_plus_row(transition_id: String) -> Control:
	return _build_graph_entry_row("ConditionPlus", {
		"background_color": Color(0.16, 0.16, 0.18, 0.8),
		"left_port_info": {
			"role": "transition_condition_new",
			"transition_id": int(transition_id),
		},
		"register_left_port": func(port: Control) -> void:
			_transition_condition_ports["%s::new" % transition_id] = port,
		"name_text": "+",
		"value_text": "Add condition",
	})


func _build_transition_output_row(transition_id: String, output_index: int, output_data: Dictionary, show_port: bool = true) -> Control:
	var target_state_path := str(output_data.get("target_state_path", ""))
	var target_definition: StateVariableDefScript = database.get_state_definition_by_path(target_state_path) if database != null else null
	var editor := _build_transition_output_value_editor(
		int(transition_id),
		output_index,
		target_definition,
		output_data
	)
	var operation_label := _transition_output_operation_label(int(output_data.get("operation", 0)))
	var config := {
		"background_color": Color(0.1, 0.24, 0.42, 0.95) if _as_bool(output_data.get("active", false)) else Color(0.18, 0.18, 0.2, 0.95),
		"name_text": "%s %s" % [target_state_path, operation_label],
		"value_editor": editor,
		"buttons": [{
			"text": "×",
			"tooltip": "Delete this output and its unshared transition-owned claim",
			"pressed": _delete_transition_output.bind(int(transition_id), output_index),
		}],
	}
	if show_port:
		config["right_port_info"] = {
			"role": "transition_output",
			"transition_id": transition_id,
			"output_index": output_index,
		}
		config["register_right_port"] = func(port: Control) -> void:
			_transition_output_ports["%s::%d" % [transition_id, output_index]] = port
	return _build_graph_entry_row("Output_%d" % output_index, config)


func _build_transition_output_plus_row(transition_id: String) -> Control:
	return _build_graph_entry_row("OutputPlus", {
		"background_color": Color(0.16, 0.16, 0.18, 0.8),
		"name_text": "+",
		"value_text": "Add output",
		"right_port_info": {
			"role": "transition_output_new",
			"transition_id": int(transition_id),
		},
		"register_right_port": func(port: Control) -> void:
			_transition_output_ports["%s::new" % transition_id] = port,
		"buttons": [{
			"text": "+",
			"tooltip": "Create output by dragging or connecting",
		}],
	})


func _make_port(color: Color, port_info: Dictionary = {}) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(52, 52)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.18)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 26
	style.corner_radius_top_right = 26
	style.corner_radius_bottom_left = 26
	style.corner_radius_bottom_right = 26
	panel.add_theme_stylebox_override("panel", style)
	_assign_port_metadata(panel, port_info)
	panel.gui_input.connect(_on_port_gui_input.bind(panel))
	return panel


func _build_inline_value_editor(definition: StateVariableDefScript, current_value: Variant, commit_callable: Callable) -> Control:
	if definition == null:
		var label := Label.new()
		label.text = "-"
		return label
	var coerced_value: Variant = definition.coerce_value(current_value)
	match definition.value_type:
		StateVariableDefScript.ValueType.BOOL:
			var checkbox := CheckBox.new()
			checkbox.button_pressed = _as_bool(coerced_value)
			checkbox.text = ""
			checkbox.toggled.connect(_on_inline_bool_toggled.bind(commit_callable))
			return checkbox
		StateVariableDefScript.ValueType.ENUM:
			var container := VBoxContainer.new()
			container.add_theme_constant_override("separation", 4)
			var option := OptionButton.new()
			var selected_index := 0
			for index in range(definition.possible_values.size()):
				var option_value: Variant = definition.possible_values[index]
				option.add_item(str(option_value), index)
				if definition.values_equal(option_value, coerced_value):
					selected_index = index
			if option.item_count > 0:
				option.select(selected_index)
			option.item_selected.connect(_on_inline_enum_selected.bind(option, definition, commit_callable))
			container.add_child(option)
			var code_editor := LineEdit.new()
			code_editor.placeholder_text = "Custom resolution code, e.g. =random_enum_excluding_default()"
			code_editor.tooltip_text = "An optional expression beginning with = is resolved when this claim is set. It may use possible_values, base_value, and random_enum_excluding_default()."
			if current_value is String and (current_value as String).strip_edges().begins_with("="):
				code_editor.text = current_value
			code_editor.text_submitted.connect(_on_inline_custom_resolution_submitted.bind(code_editor, commit_callable))
			container.add_child(code_editor)
			return container
		StateVariableDefScript.ValueType.INT:
			var int_editor := SpinBox.new()
			int_editor.allow_greater = true
			int_editor.allow_lesser = true
			int_editor.step = 1.0
			int_editor.rounded = true
			int_editor.value = _as_float(_as_int(coerced_value))
			int_editor.value_changed.connect(_on_inline_spinbox_value_changed.bind(commit_callable, true))
			return int_editor
		StateVariableDefScript.ValueType.FLOAT:
			var float_editor := SpinBox.new()
			float_editor.allow_greater = true
			float_editor.allow_lesser = true
			float_editor.step = 0.05
			float_editor.value = _as_float(coerced_value)
			float_editor.value_changed.connect(_on_inline_spinbox_value_changed.bind(commit_callable, false))
			return float_editor
		StateVariableDefScript.ValueType.VECTOR2:
			var box := HBoxContainer.new()
			var vector_value: Vector2 = coerced_value if coerced_value is Vector2 else Vector2.ZERO
			var x_editor := SpinBox.new()
			x_editor.allow_greater = true
			x_editor.allow_lesser = true
			x_editor.step = 0.05
			x_editor.value = vector_value.x
			var y_editor := SpinBox.new()
			y_editor.allow_greater = true
			y_editor.allow_lesser = true
			y_editor.step = 0.05
			y_editor.value = vector_value.y
			x_editor.value_changed.connect(_on_inline_vector2_value_changed.bind(x_editor, y_editor, commit_callable))
			y_editor.value_changed.connect(_on_inline_vector2_value_changed.bind(x_editor, y_editor, commit_callable))
			box.add_child(x_editor)
			box.add_child(y_editor)
			return box
		StateVariableDefScript.ValueType.VECTOR3:
			var vector3_box := HBoxContainer.new()
			var vector3_value: Vector3 = coerced_value if coerced_value is Vector3 else Vector3.ZERO
			var axis_editors: Array[SpinBox] = []
			for axis_value in [vector3_value.x, vector3_value.y, vector3_value.z]:
				var axis_editor := SpinBox.new()
				axis_editor.allow_greater = true
				axis_editor.allow_lesser = true
				axis_editor.step = 0.05
				axis_editor.value = float(axis_value)
				axis_editors.append(axis_editor)
				vector3_box.add_child(axis_editor)
			for axis_editor in axis_editors:
				axis_editor.value_changed.connect(
					_on_inline_vector3_value_changed.bind(axis_editors[0], axis_editors[1], axis_editors[2], commit_callable)
				)
			return vector3_box
		StateVariableDefScript.ValueType.LIST:
			var read_only := LineEdit.new()
			read_only.editable = false
			read_only.text = definition.describe_value(coerced_value)
			return read_only
		_:
			var line_edit := LineEdit.new()
			line_edit.text = str(coerced_value)
			line_edit.text_submitted.connect(_on_inline_text_submitted.bind(line_edit, commit_callable))
			line_edit.focus_exited.connect(_on_inline_text_focus_exited.bind(line_edit, commit_callable))
			return line_edit


func _build_transition_condition_value_editor(transition_id: int, condition_index: int, definition: StateVariableDefScript, condition_data: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var operator_button := _build_condition_operator_button(transition_id, condition_index, definition, int(condition_data.get("operator", 0)))
	box.add_child(operator_button)
	var operator_value := int(condition_data.get("operator", 0))
	var value_editor := _build_transition_condition_operand_editor(
		definition,
		operator_value,
		condition_data.get("expected_value", null),
		Callable(self, "_commit_transition_condition_value").bind(transition_id, condition_index)
	)
	if value_editor != null:
		value_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(value_editor)
	return box


func _build_transition_output_value_editor(transition_id: int, output_index: int, definition: StateVariableDefScript, output_data: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var operation_button := OptionButton.new()
	operation_button.custom_minimum_size = Vector2(96.0, 0.0)
	if definition != null:
		for operation_value in StateTransitionOutputDefScript.new().get_supported_operations(definition):
			var operation_int := int(operation_value)
			operation_button.add_item(_transition_output_operation_label(operation_int), operation_int)
		var selected_operation := int(output_data.get("operation", 0))
		for item_index in range(operation_button.item_count):
			if operation_button.get_item_id(item_index) == selected_operation:
				operation_button.select(item_index)
				break
	operation_button.item_selected.connect(_on_transition_output_operation_selected.bind(transition_id, output_index, operation_button))
	box.add_child(operation_button)
	var value_editor := _build_transition_output_operand_editor(
		definition,
		int(output_data.get("operation", 0)),
		output_data.get("value", null),
		# Not Callable(...).bind(transition_id, output_index): bound args are
		# appended after the caller-supplied value, not prepended, which would
		# scramble _commit_transition_output_value's (transition_id,
		# output_index, value) parameter order.
		func(value: Variant) -> void: _commit_transition_output_value(transition_id, output_index, value)
	)
	if value_editor != null:
		value_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(value_editor)
	return box


func _build_transition_condition_operand_editor(definition: StateVariableDefScript, operator_value: int, current_value: Variant, commit_callable: Callable) -> Control:
	if definition == null:
		return null
	if definition.value_type == StateVariableDefScript.ValueType.LIST:
		if _condition_operator_uses_list_count(operator_value):
			var count_editor := SpinBox.new()
			count_editor.allow_greater = true
			count_editor.allow_lesser = false
			count_editor.step = 1.0
			count_editor.rounded = true
			count_editor.value = _as_float(_as_int(current_value))
			count_editor.value_changed.connect(_on_inline_spinbox_value_changed.bind(commit_callable, true))
			return count_editor
		var line_edit := LineEdit.new()
		line_edit.placeholder_text = "item key"
		line_edit.text = str(current_value)
		line_edit.text_submitted.connect(_on_inline_text_submitted.bind(line_edit, commit_callable))
		line_edit.focus_exited.connect(_on_inline_text_focus_exited.bind(line_edit, commit_callable))
		return line_edit
	return _build_inline_value_editor(definition, current_value, commit_callable)


func _build_transition_output_operand_editor(definition: StateVariableDefScript, _operation_value: int, current_value: Variant, commit_callable: Callable) -> Control:
	if definition == null:
		return null
	if definition.value_type == StateVariableDefScript.ValueType.LIST:
		var line_edit := LineEdit.new()
		line_edit.placeholder_text = "item key"
		line_edit.text = str(current_value)
		line_edit.text_submitted.connect(_on_inline_text_submitted.bind(line_edit, commit_callable))
		line_edit.focus_exited.connect(_on_inline_text_focus_exited.bind(line_edit, commit_callable))
		return line_edit
	return _build_inline_value_editor(definition, current_value, commit_callable)


func _build_condition_operator_button(transition_id: int, condition_index: int, definition: StateVariableDefScript, selected_operator: int) -> MenuButton:
	var button := MenuButton.new()
	button.custom_minimum_size = Vector2(130.0, 0.0)
	button.text = _condition_operator_label(selected_operator)
	var popup := button.get_popup()
	popup.clear()
	popup.id_pressed.connect(_on_condition_operator_menu_id_pressed.bind(transition_id, condition_index))
	if definition != null and definition.value_type == StateVariableDefScript.ValueType.LIST:
		popup.add_item("has", int(StateTransitionConditionDefScript.Operator.LIST_HAS))
		popup.add_item("does not have", int(StateTransitionConditionDefScript.Operator.LIST_NOT_HAS))
		popup.add_separator()
		var submenu := PopupMenu.new()
		submenu.name = "CountMenu"
		submenu.add_item("==", int(StateTransitionConditionDefScript.Operator.COUNT_EQUALS))
		submenu.add_item(">=", int(StateTransitionConditionDefScript.Operator.COUNT_GREATER_EQUAL))
		submenu.add_item(">", int(StateTransitionConditionDefScript.Operator.COUNT_GREATER_THAN))
		submenu.add_item("<", int(StateTransitionConditionDefScript.Operator.COUNT_LESS_THAN))
		submenu.add_item("<=", int(StateTransitionConditionDefScript.Operator.COUNT_LESS_EQUAL))
		submenu.id_pressed.connect(_on_condition_operator_menu_id_pressed.bind(transition_id, condition_index))
		button.add_child(submenu)
		popup.add_submenu_item("count", "CountMenu")
	else:
		var supported: Array[int] = StateTransitionConditionDefScript.new().get_supported_operators(definition)
		for operator_entry in supported:
			var operator_int := int(operator_entry)
			popup.add_item(_condition_operator_label(operator_int), operator_int)
	return button


func _condition_operator_label(operator_value: int) -> String:
	var helper := StateTransitionConditionDefScript.new()
	helper.operator = operator_value
	return helper.get_operator_label()


func _transition_output_operation_label(operation_value: int) -> String:
	var helper := StateTransitionOutputDefScript.new()
	helper.operation = operation_value
	return helper.get_operation_label()


func _condition_operator_uses_list_count(operator_value: int) -> bool:
	return operator_value in [
		int(StateTransitionConditionDefScript.Operator.COUNT_EQUALS),
		int(StateTransitionConditionDefScript.Operator.COUNT_GREATER_EQUAL),
		int(StateTransitionConditionDefScript.Operator.COUNT_GREATER_THAN),
		int(StateTransitionConditionDefScript.Operator.COUNT_LESS_THAN),
		int(StateTransitionConditionDefScript.Operator.COUNT_LESS_EQUAL),
	]


func _build_connections_for_transition(transition_data: Dictionary) -> void:
	var transition_id := str(transition_data.get("transition_id", ""))
	var condition_index := 0
	for condition_variant in transition_data.get("conditions", []):
		var condition_data: Dictionary = condition_variant
		var state_path := str(condition_data.get("target_state_path", ""))
		var from_port: Variant = _state_header_ports.get(state_path)
		var to_port: Variant = _transition_condition_ports.get("%s::%d" % [transition_id, condition_index])
		if from_port != null and to_port != null:
			_connections.append({
				"id": "condition:%s:%s:%d" % [state_path, transition_id, condition_index],
				"transition_id": transition_id,
				"from": from_port,
				"to": to_port,
				"from_endpoint": _state_header_endpoint_key(state_path),
				"to_endpoint": _transition_condition_endpoint_key(transition_id, condition_index),
				"active": _as_bool(condition_data.get("active", false)),
				"active_color": _STATE_TO_TRANSITION_COLOR,
				"inactive_color": _STATE_TO_TRANSITION_COLOR,
				"direction": 1.0,
				"active_width": 2.0,
				"inactive_width": 2.0,
				"show_pulse": false,
			})
		condition_index += 1
	var output_index := 0
	for output_variant in transition_data.get("outputs", []):
		var output_data: Dictionary = output_variant
		var target_state_path := str(output_data.get("target_state_path", ""))
		var target_key := "%s::%s" % [target_state_path, str(output_data.get("target_claim_slot_id", ""))]
		var from_output_port: Variant = _transition_output_ports.get("%s::%d" % [transition_id, output_index])
		var to_state_port: Variant = _state_claim_ports.get(target_key)
		var target_endpoint := _state_claim_endpoint_key(target_state_path, str(output_data.get("target_claim_slot_id", "")))
		if to_state_port == null:
			to_state_port = _state_header_ports.get(target_state_path)
			target_endpoint = _state_header_endpoint_key(target_state_path)
		if from_output_port != null and to_state_port != null:
			var is_active := _as_bool(output_data.get("active", false))
			var target_claim_snapshot := _find_claim_snapshot(target_state_path, str(output_data.get("target_claim_slot_id", "")))
			var is_suppressed := _as_bool(target_claim_snapshot.get("suppressed_by_resolution", false))
			_connections.append({
				"id": "output:%s:%s:%d" % [transition_id, target_key, output_index],
				"transition_id": transition_id,
				"from": from_output_port,
				"to": to_state_port,
				"from_endpoint": _transition_output_endpoint_key(transition_id, output_index),
				"to_endpoint": target_endpoint,
				"active": is_active,
				"active_color": _TRANSITION_TO_STATE_SUPPRESSED if is_suppressed else _TRANSITION_TO_STATE_ACTIVE,
				"inactive_color": _TRANSITION_TO_STATE_INACTIVE,
				"direction": -1.0,
				"active_width": 5.0,
				"inactive_width": 2.0,
			})
		output_index += 1
	_rebuild_connected_semantic_endpoints()


func _find_claim_snapshot(state_path: String, slot_id: String) -> Dictionary:
	var state_snapshot := _find_state_snapshot(state_path)
	for claim_variant in state_snapshot.get("claim_slots", []):
		var claim_snapshot: Dictionary = claim_variant
		if str(claim_snapshot.get("slot_id", "")) == slot_id:
			return claim_snapshot
	return {}


func _rebuild_connected_semantic_endpoints() -> void:
	_connected_semantic_endpoints.clear()
	for connection_variant in _connections:
		var connection: Dictionary = connection_variant
		var from_endpoint := str(connection.get("from_endpoint", ""))
		var to_endpoint := str(connection.get("to_endpoint", ""))
		if not from_endpoint.is_empty():
			_connected_semantic_endpoints[from_endpoint] = true
		if not to_endpoint.is_empty():
			_connected_semantic_endpoints[to_endpoint] = true


func _draw_connections() -> void:
	if _graph_edit == null:
		return
	var time: float = _as_float(Time.get_ticks_msec()) / 1000.0
	for connection_variant in _connections:
		var connection: Dictionary = connection_variant
		var from_port := connection.get("from") as Control
		var to_port := connection.get("to") as Control
		if from_port == null or to_port == null:
			continue
		var visual_state: Dictionary = _connection_visuals.get(str(connection.get("id", "")), {})
		var from_pos: Vector2 = _control_point_to_overlay_local(_overlay, _port_anchor_global_position(from_port))
		var to_pos: Vector2 = _control_point_to_overlay_local(_overlay, _port_anchor_global_position(to_port))
		var base_color: Color = visual_state.get("current_color", connection.get("inactive_color", Color.WHITE))
		var flash_amount := _as_float(visual_state.get("flash", 0.0))
		var color := base_color.lerp(Color.WHITE, clampf(flash_amount, 0.0, 1.0))
		var width: float = _as_float(visual_state.get("current_width", connection.get("inactive_width", 2.0)))
		var tangent: float = maxf(90.0, absf(to_pos.x - from_pos.x) * 0.55)
		var control_a: Vector2 = from_pos + Vector2(tangent * _port_curve_direction(from_port), 0.0)
		var control_b: Vector2 = to_pos + Vector2(tangent * _port_curve_direction(to_port), 0.0)
		var points: PackedVector2Array = PackedVector2Array()
		for step in range(28):
			var t: float = _as_float(step) / 27.0
			points.append(_bezier_point(from_pos, control_a, control_b, to_pos, t))
		_overlay.draw_polyline(points, color, width, true)
		if _as_bool(connection.get("active", false)) and _as_bool(connection.get("show_pulse", true)):
			var pulse_t: float = fposmod(time * 0.45 + (0.0 if _as_float(connection.get("direction", 1.0)) > 0.0 else 0.5), 1.0)
			var pulse_pos: Vector2 = _bezier_point(from_pos, control_a, control_b, to_pos, pulse_t)
			_overlay.draw_circle(pulse_pos, width + 1.2, Color(1.0, 1.0, 1.0, 0.85))
	if not _drag_connection_origin.is_empty():
		var drag_port := _drag_connection_origin.get("port") as Control
		if drag_port != null:
			var drag_from := _control_point_to_overlay_local(_overlay, _port_anchor_global_position(drag_port))
			var drag_to := _control_point_to_overlay_local(_overlay, _graph_point_to_canvas_global(_drag_connection_mouse_graph_position))
			var drag_tangent := maxf(90.0, absf(drag_to.x - drag_from.x) * 0.55)
			var drag_control_a := drag_from + Vector2(drag_tangent * _port_curve_direction(drag_port), 0.0)
			var drag_control_b := drag_to + Vector2(drag_tangent * signf(drag_to.x - drag_from.x if absf(drag_to.x - drag_from.x) > 0.001 else 1.0), 0.0)
			var drag_points: PackedVector2Array = PackedVector2Array()
			for step in range(28):
				var t: float = _as_float(step) / 27.0
				drag_points.append(_bezier_point(drag_from, drag_control_a, drag_control_b, drag_to, t))
			_overlay.draw_polyline(drag_points, Color(1.0, 1.0, 1.0, 0.75), 3.0, true)
	_draw_connected_port_indicators()


func _draw_connected_port_indicators() -> void:
	for port_group in [_state_header_ports, _transition_condition_ports, _transition_output_ports, _state_claim_ports]:
		for port_variant in port_group.values():
			var port := port_variant as Control
			if port == null:
				continue
			var port_info_variant: Variant = port.get_meta("port_info", {})
			var port_info: Dictionary = port_info_variant if port_info_variant is Dictionary else {}
			if not _connected_semantic_endpoints.has(_semantic_endpoint_key(port_info)):
				continue
			var center := _control_point_to_overlay_local(_overlay, _port_anchor_global_position(port))
			_overlay.draw_circle(center, 8.0, Color(0.02, 0.02, 0.03, 0.95))


func _semantic_endpoint_key(port_info: Dictionary) -> String:
	match str(port_info.get("role", "")):
		"state_header":
			return _state_header_endpoint_key(str(port_info.get("state_path", "")))
		"state_claim":
			return _state_claim_endpoint_key(
				str(port_info.get("state_path", "")),
				str(port_info.get("slot_id", ""))
			)
		"transition_condition":
			return _transition_condition_endpoint_key(
				str(port_info.get("transition_id", "")),
				int(port_info.get("condition_index", -1))
			)
		"transition_output":
			return _transition_output_endpoint_key(
				str(port_info.get("transition_id", "")),
				int(port_info.get("output_index", -1))
			)
		_:
			return ""


func _state_header_endpoint_key(state_path: String) -> String:
	return "state_header:%s" % state_path


func _state_claim_endpoint_key(state_path: String, slot_id: String) -> String:
	return "state_claim:%s:%s" % [state_path, slot_id]


func _transition_condition_endpoint_key(transition_id: String, condition_index: int) -> String:
	return "transition_condition:%s:%d" % [transition_id, condition_index]


func _transition_output_endpoint_key(transition_id: String, output_index: int) -> String:
	return "transition_output:%s:%d" % [transition_id, output_index]


func _port_anchor_global_position(port: Control) -> Vector2:
	if port == null:
		return Vector2.ZERO
	if not _compact_graph_mode:
		return port.get_global_rect().get_center()
	var node := _graph_node_for_control(port)
	if node == null:
		return port.get_global_rect().get_center()
	var port_info_variant: Variant = port.get_meta("port_info", {})
	var port_info: Dictionary = port_info_variant if port_info_variant is Dictionary else {}
	var role := str(port_info.get("role", ""))
	var node_rect := node.get_global_rect()
	var center_y := node_rect.position.y + node_rect.size.y * 0.5
	match role:
		"state_header", "transition_output", "transition_output_new":
			return Vector2(node_rect.position.x + node_rect.size.x, center_y)
		"transition_condition", "transition_condition_new", "state_claim", "state_claim_new":
			return Vector2(node_rect.position.x, center_y)
		_:
			return port.get_global_rect().get_center()


func _port_curve_direction(port: Control) -> float:
	if port == null:
		return 1.0
	var port_info_variant: Variant = port.get_meta("port_info", {})
	var port_info: Dictionary = port_info_variant if port_info_variant is Dictionary else {}
	match str(port_info.get("role", "")):
		"transition_condition", "transition_condition_new", "state_claim", "state_claim_new":
			return -1.0
		_:
			return 1.0


func _graph_node_for_control(control: Control) -> GraphNode:
	var current: Node = control
	while current != null:
		if current is GraphNode:
			return current as GraphNode
		current = current.get_parent()
	return null


func _control_point_to_overlay_local(target: Control, global_point: Vector2) -> Vector2:
	if target == null:
		return global_point
	return target.get_global_transform_with_canvas().affine_inverse() * global_point


func _sync_connection_visual_targets() -> void:
	var active_connection_ids: Dictionary = {}
	for connection_variant in _connections:
		var connection: Dictionary = connection_variant
		var connection_id := str(connection.get("id", ""))
		active_connection_ids[connection_id] = true
		var target_active := _as_bool(connection.get("active", false))
		var target_color: Color = connection.get("active_color", Color.WHITE) if target_active else connection.get("inactive_color", Color.WHITE)
		var target_width: float = _as_float(connection.get("active_width", 5.0)) if target_active else _as_float(connection.get("inactive_width", 2.0))
		if not _connection_visuals.has(connection_id):
			_connection_visuals[connection_id] = {
				"current_color": connection.get("inactive_color", Color.WHITE),
				"current_width": _as_float(connection.get("inactive_width", 2.0)),
				"target_color": target_color,
				"target_width": target_width,
				"active": target_active,
				"flash": 1.0 if target_active else 0.0,
			}
			continue
		var visual_state: Dictionary = _connection_visuals[connection_id]
		var previous_active := _as_bool(visual_state.get("active", false))
		visual_state["target_color"] = target_color
		visual_state["target_width"] = target_width
		visual_state["active"] = target_active
		if target_active and not previous_active:
			visual_state["flash"] = 1.0
		_connection_visuals[connection_id] = visual_state
	for connection_id_variant in _connection_visuals.keys():
		var connection_id := str(connection_id_variant)
		if active_connection_ids.has(connection_id):
			continue
		_connection_visuals.erase(connection_id)


func _advance_connection_visuals(delta: float) -> bool:
	var needs_redraw := not _drag_connection_origin.is_empty()
	for connection_id_variant in _connection_visuals.keys():
		var connection_id := str(connection_id_variant)
		var visual_state: Dictionary = _connection_visuals.get(connection_id, {})
		var current_color: Color = visual_state.get("current_color", Color.WHITE)
		var target_color: Color = visual_state.get("target_color", current_color)
		var current_width := _as_float(visual_state.get("current_width", 2.0))
		var target_width := _as_float(visual_state.get("target_width", current_width))
		var current_flash := _as_float(visual_state.get("flash", 0.0))
		var lerp_weight := clampf(delta * 8.0, 0.0, 1.0)
		var next_color := current_color.lerp(target_color, lerp_weight)
		var next_width := lerpf(current_width, target_width, lerp_weight)
		var next_flash := maxf(0.0, current_flash - delta * 3.2)
		visual_state["current_color"] = next_color
		visual_state["current_width"] = next_width
		visual_state["flash"] = next_flash
		_connection_visuals[connection_id] = visual_state
		if _as_bool(visual_state.get("active", false)):
			needs_redraw = true
		elif next_flash > 0.001 or current_flash > 0.001:
			needs_redraw = true
		elif (
			absf(next_color.r - target_color.r) > 0.002
			or absf(next_color.g - target_color.g) > 0.002
			or absf(next_color.b - target_color.b) > 0.002
			or absf(next_color.a - target_color.a) > 0.002
			or absf(next_width - target_width) > 0.01
		):
			needs_redraw = true
	return needs_redraw


func _bezier_point(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var inv := 1.0 - t
	return (
		a * inv * inv * inv
		+ b * 3.0 * inv * inv * t
		+ c * 3.0 * inv * t * t
		+ d * t * t * t
	)


func _resolved_value_color(state_data: Dictionary) -> Color:
	if _as_bool(state_data.get("override_enabled", false)):
		return _STATE_OVERRIDE_COLOR
	for claim_variant in state_data.get("claim_slots", []):
		var claim_snapshot: Dictionary = claim_variant
		if _as_bool(claim_snapshot.get("active", false)):
			return _STATE_ACTIVE_COLOR
	return _STATE_IDLE_COLOR


func _transition_value_color(transition_data: Dictionary) -> Color:
	if not str(transition_data.get("invalid_reason", "")).is_empty():
		return _TRANSITION_INVALID_COLOR
	if _as_bool(transition_data.get("active", false)):
		return _TRANSITION_ACTIVE_COLOR
	return _TRANSITION_IDLE_COLOR


func _transition_status_text(transition_data: Dictionary) -> String:
	var invalid_reason := str(transition_data.get("invalid_reason", ""))
	if not invalid_reason.is_empty():
		return "invalid"
	return "active" if _as_bool(transition_data.get("active", false)) else "inactive"


func _row_background_color(accent: Color) -> Color:
	return Color(
		lerpf(0.12, accent.r, 0.35),
		lerpf(0.12, accent.g, 0.35),
		lerpf(0.14, accent.b, 0.35),
		0.96
	)


func _neutral_tree_row_background() -> Color:
	return Color(0.0, 0.0, 0.0, 0.0)


func _state_row_background_color(state_data: Dictionary) -> Color:
	if _as_bool(state_data.get("override_enabled", false)):
		return _row_background_color(_STATE_OVERRIDE_COLOR)
	for claim_variant in state_data.get("claim_slots", []):
		var claim_snapshot: Dictionary = claim_variant
		if _as_bool(claim_snapshot.get("active", false)):
			return _row_background_color(_STATE_ACTIVE_COLOR)
	return _neutral_tree_row_background()


func _transition_row_background_color(transition_data: Dictionary) -> Color:
	var invalid_reason := str(transition_data.get("invalid_reason", ""))
	if not invalid_reason.is_empty():
		return _row_background_color(_TRANSITION_INVALID_COLOR)
	if _as_bool(transition_data.get("active", false)):
		return _row_background_color(_TRANSITION_ACTIVE_COLOR)
	return _neutral_tree_row_background()


func _apply_tree_row_style(item: TreeItem, background_color: Color, name_color: Color, value_color: Color = Color.WHITE) -> void:
	for column in _visible_sidebar_columns():
		item.set_custom_bg_color(column, background_color)
	item.set_custom_color(_sidebar_column_index(_COLUMN_NAME), name_color)
	item.set_custom_color(_sidebar_column_index(_COLUMN_VALUE), value_color)
	if _sidebar_has_column(_COLUMN_DEFAULT):
		item.set_custom_color(_sidebar_column_index(_COLUMN_DEFAULT), value_color)
	if _sidebar_has_column(_COLUMN_RESOLVER):
		item.set_custom_color(_sidebar_column_index(_COLUMN_RESOLVER), value_color)
	item.set_custom_color(_sidebar_column_index(_COLUMN_VISIBILITY), name_color)


func _configure_state_sidebar_cells(item: TreeItem, state_data: Dictionary) -> void:
	_configure_tree_value_cell(item, _sidebar_column_index(_COLUMN_VALUE), state_data, state_data.get("resolved_value", null))
	if _sidebar_has_column(_COLUMN_DEFAULT):
		_configure_tree_value_cell(item, _sidebar_column_index(_COLUMN_DEFAULT), state_data, state_data.get("default_value", null))
	if _sidebar_has_column(_COLUMN_RESOLVER):
		_configure_tree_resolver_cell(item, state_data)


func _configure_state_sidebar_tooltips(item: TreeItem, state_data: Dictionary) -> void:
	var state_path := str(state_data.get("path", ""))
	var type_name := str(state_data.get("value_type_name", "value"))
	var resolver_name := str(state_data.get("resolver_name", "ordered"))
	var value_source := "default"
	if _as_bool(state_data.get("override_enabled", false)):
		value_source = "override"
	else:
		for claim_variant in state_data.get("claim_slots", []):
			var claim_data: Dictionary = claim_variant
			if _as_bool(claim_data.get("active", false)):
				value_source = "active claim contribution"
				break
	_set_item_tooltip(item, _COLUMN_NAME, "State %s (%s). Single-click to focus; double-click to rename." % [state_path, type_name])
	_set_item_tooltip(item, _COLUMN_VALUE, "Resolved %s value from %s, using the %s resolver." % [type_name, value_source, resolver_name])
	_set_item_tooltip(item, _COLUMN_DEFAULT, "Authored default %s value used when no override or claim resolves." % type_name)
	_set_item_tooltip(item, _COLUMN_RESOLVER, "Resolver: %s. Controls how overrides and claim contributions produce the resolved value." % resolver_name)
	_set_item_tooltip(item, _COLUMN_VISIBILITY, "Graph visibility for %s. This changes authoring presentation, not runtime state." % state_path)


func _configure_transition_sidebar_tooltips(item: TreeItem, transition_data: Dictionary) -> void:
	var transition_id := str(transition_data.get("transition_id", ""))
	var display_name := str(transition_data.get("display_name", transition_id))
	var status := _transition_status_text(transition_data)
	var invalid_reason := str(transition_data.get("invalid_reason", ""))
	_set_item_tooltip(item, _COLUMN_NAME, "Transition %s (%s). Single-click to focus; double-click to rename." % [display_name, transition_id])
	_set_item_tooltip(item, _COLUMN_VALUE, "Runtime transition status: %s%s" % [status, "" if invalid_reason.is_empty() else " — %s" % invalid_reason])
	_set_item_tooltip(item, _COLUMN_DEFAULT, "Defaults do not apply to transitions.")
	_set_item_tooltip(item, _COLUMN_RESOLVER, "Resolvers do not apply to transitions.")
	_set_item_tooltip(item, _COLUMN_VISIBILITY, "Graph visibility for transition %s. This does not change runtime evaluation." % display_name)


func _configure_tree_value_cell(item: TreeItem, column: int, state_data: Dictionary, current_value: Variant) -> void:
	var value_type := int(state_data.get("value_type", int(StateVariableDefScript.ValueType.STRING)))
	match value_type:
		StateVariableDefScript.ValueType.BOOL:
			item.set_editable(column, true)
			item.set_cell_mode(column, TreeItem.CELL_MODE_CHECK)
			item.set_checked(column, _as_bool(current_value))
			item.set_text(column, "")
		StateVariableDefScript.ValueType.ENUM:
			item.set_editable(column, true)
			var possible_values: Array = state_data.get("possible_values", [])
			var labels: Array[String] = []
			var selected_index := 0
			for index in range(possible_values.size()):
				var option_value: Variant = possible_values[index]
				labels.append(str(option_value))
				if option_value == current_value:
					selected_index = index
			item.set_cell_mode(column, TreeItem.CELL_MODE_RANGE)
			item.set_range_config(column, 0, maxi(0, labels.size() - 1), 1, false)
			item.set_text(column, ",".join(labels))
			item.set_range(column, selected_index)
		StateVariableDefScript.ValueType.LIST:
			item.set_editable(column, false)
			item.set_cell_mode(column, TreeItem.CELL_MODE_STRING)
			item.set_text(column, _describe_state_value_for_tree(state_data, current_value))
		_:
			item.set_editable(column, true)
			item.set_cell_mode(column, TreeItem.CELL_MODE_STRING)
			item.set_text(column, _describe_state_value_for_tree(state_data, current_value))


func _configure_tree_resolver_cell(item: TreeItem, state_data: Dictionary) -> void:
	var column := _sidebar_column_index(_COLUMN_RESOLVER)
	if column < 0:
		return
	var supported_resolvers: Array = _supported_resolvers_for_state(state_data)
	var selected_index := 0
	var labels: Array[String] = []
	for index in range(supported_resolvers.size()):
		var resolver_value := int(supported_resolvers[index])
		labels.append(_resolver_name_from_value(resolver_value))
		if resolver_value == int(state_data.get("resolver", 0)):
			selected_index = index
	item.set_editable(column, true)
	item.set_cell_mode(column, TreeItem.CELL_MODE_RANGE)
	item.set_range_config(column, 0, maxi(0, labels.size() - 1), 1, false)
	item.set_text(column, ",".join(labels))
	item.set_range(column, selected_index)


func _describe_state_value_for_tree(state_data: Dictionary, value: Variant) -> String:
	var value_type := int(state_data.get("value_type", int(StateVariableDefScript.ValueType.STRING)))
	if value_type == int(StateVariableDefScript.ValueType.LIST):
		return "[%s]" % ", ".join(value if value is Array else [])
	if value_type == int(StateVariableDefScript.ValueType.VECTOR2):
		if value is Vector2:
			var vector_value := value as Vector2
			return "%s, %s" % [vector_value.x, vector_value.y]
	if value_type == int(StateVariableDefScript.ValueType.VECTOR3):
		if value is Vector3:
			var vector3_value := value as Vector3
			return "%s, %s, %s" % [vector3_value.x, vector3_value.y, vector3_value.z]
	return str(value)


func _apply_state_node_style(node: GraphNode, state_data: Dictionary) -> void:
	var state_color := _resolved_value_color(state_data)
	var panel := StyleBoxFlat.new()
	panel.bg_color = _state_node_background_color(state_color)
	panel.border_color = state_color.lightened(0.12)
	panel.border_width_left = 1
	panel.border_width_top = 1
	panel.border_width_right = 1
	panel.border_width_bottom = 1
	panel.corner_radius_top_left = _GRAPH_NODE_RADIUS
	panel.corner_radius_top_right = _GRAPH_NODE_RADIUS
	panel.corner_radius_bottom_left = _GRAPH_NODE_RADIUS
	panel.corner_radius_bottom_right = _GRAPH_NODE_RADIUS
	node.add_theme_stylebox_override("panel", panel)
	var titlebar := StyleBoxFlat.new()
	titlebar.bg_color = Color(0.04, 0.04, 0.05, 1.0)
	titlebar.border_color = Color(0.18, 0.18, 0.2, 1.0)
	titlebar.border_width_left = 1
	titlebar.border_width_top = 1
	titlebar.border_width_right = 1
	titlebar.border_width_bottom = 1
	titlebar.corner_radius_top_left = _GRAPH_NODE_RADIUS
	titlebar.corner_radius_top_right = _GRAPH_NODE_RADIUS
	titlebar.content_margin_left = 16.0
	titlebar.content_margin_top = 14.0
	titlebar.content_margin_right = 18.0
	titlebar.content_margin_bottom = 14.0
	node.add_theme_stylebox_override("titlebar", titlebar)
	node.add_theme_stylebox_override("titlebar_selected", titlebar)
	node.add_theme_color_override("title_color", Color(0.97, 0.98, 1.0, 1.0))
	node.add_theme_font_size_override("title_font_size", 40)
	_style_graph_node_titlebar(node, Color(0.97, 0.98, 1.0, 1.0))


func _apply_transition_node_style(node: GraphNode, active: bool) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.11, 0.16, 0.12, 0.96) if active else Color(0.14, 0.14, 0.16, 0.95)
	panel.border_color = Color(0.35, 1.0, 0.45, 0.95) if active else Color(0.28, 0.28, 0.34, 1.0)
	panel.border_width_left = 1
	panel.border_width_top = 1
	panel.border_width_right = 1
	panel.border_width_bottom = 1
	panel.corner_radius_top_left = _GRAPH_NODE_RADIUS
	panel.corner_radius_top_right = _GRAPH_NODE_RADIUS
	panel.corner_radius_bottom_left = _GRAPH_NODE_RADIUS
	panel.corner_radius_bottom_right = _GRAPH_NODE_RADIUS
	node.add_theme_stylebox_override("panel", panel)
	var titlebar := StyleBoxFlat.new()
	titlebar.bg_color = Color(0.95, 0.95, 0.97, 1.0)
	titlebar.border_color = Color(0.42, 0.44, 0.48, 1.0)
	titlebar.border_width_left = 1
	titlebar.border_width_top = 1
	titlebar.border_width_right = 1
	titlebar.border_width_bottom = 1
	titlebar.corner_radius_top_left = _GRAPH_NODE_RADIUS
	titlebar.corner_radius_top_right = _GRAPH_NODE_RADIUS
	titlebar.content_margin_left = 18.0
	titlebar.content_margin_top = 14.0
	titlebar.content_margin_right = 18.0
	titlebar.content_margin_bottom = 14.0
	node.add_theme_stylebox_override("titlebar", titlebar)
	node.add_theme_stylebox_override("titlebar_selected", titlebar)
	node.add_theme_color_override("title_color", Color(0.08, 0.09, 0.11, 1.0))
	node.add_theme_font_size_override("title_font_size", 40)
	_style_graph_node_titlebar(node, Color(0.08, 0.09, 0.11, 1.0))


func _state_node_background_color(state_color: Color) -> Color:
	return Color(
		lerpf(0.12, state_color.r, 0.18),
		lerpf(0.12, state_color.g, 0.18),
		lerpf(0.14, state_color.b, 0.18),
		0.98
	)


func _finalize_node_width(node: GraphNode, body: Control, min_width: float) -> void:
	if node == null or body == null:
		return
	var target_width := maxf(_GRAPH_NODE_FIXED_WIDTH, min_width)
	var target_height := maxf(_GRAPH_NODE_MIN_HEIGHT, body.get_combined_minimum_size().y + 48.0)
	node.custom_minimum_size = Vector2(target_width, target_height)
	node.size = Vector2(target_width, target_height)


func _position_for_node(node_id: String, authored_position: Variant) -> Vector2:
	if _node_positions.has(node_id):
		return _node_positions[node_id]
	if authored_position is Vector2 and (authored_position as Vector2) != Vector2.ZERO:
		return authored_position
	return Vector2.ZERO


func _has_missing_positions(states: Array[Dictionary], transitions: Array[Dictionary]) -> bool:
	for state_data in states:
		var node_id := "%s%s" % [_STATE_NODE_PREFIX, str(state_data.get("path", ""))]
		if not _node_positions.has(node_id) and Vector2(state_data.get("graph_position", Vector2.ZERO)) == Vector2.ZERO:
			return true
	for transition_data in transitions:
		var node_id := "%s%s" % [_TRANSITION_NODE_PREFIX, str(transition_data.get("transition_id", ""))]
		if not _node_positions.has(node_id) and Vector2(transition_data.get("graph_position", Vector2.ZERO)) == Vector2.ZERO:
			return true
	return false


func _auto_arrange_all_nodes() -> void:
	var snapshot := _get_effective_snapshot()
	_auto_arrange_ranked_nodes(
		_filtered_visible_states(snapshot.get("states", [])),
		_filtered_visible_transitions(snapshot.get("transitions", []))
	)
	_queue_overlay_redraw()


func _auto_arrange_ranked_nodes(states: Array[Dictionary], transitions: Array[Dictionary]) -> void:
	var adjacency: Dictionary = {}
	var indegree: Dictionary = {}
	var ranks: Dictionary = {}
	var seed_y: Dictionary = {}
	for state_data in states:
		var node_id := "%s%s" % [_STATE_NODE_PREFIX, str(state_data.get("path", ""))]
		adjacency[node_id] = []
		indegree[node_id] = 0
		ranks[node_id] = 0
		seed_y[node_id] = (state_data.get("graph_position", Vector2.ZERO) as Vector2).y
	for transition_data in transitions:
		var node_id := "%s%s" % [_TRANSITION_NODE_PREFIX, str(transition_data.get("transition_id", ""))]
		adjacency[node_id] = []
		indegree[node_id] = 0
		ranks[node_id] = 0
		var neighbor_seed_total := 0.0
		var neighbor_seed_count := 0
		for condition_variant in transition_data.get("conditions", []):
			var condition_data: Dictionary = condition_variant
			var state_path := str(condition_data.get("target_state_path", ""))
			var state_data := _find_snapshot_state_in(states, state_path)
			if not state_data.is_empty():
				neighbor_seed_total += (state_data.get("graph_position", Vector2.ZERO) as Vector2).y
				neighbor_seed_count += 1
		for output_variant in transition_data.get("outputs", []):
			var output_data: Dictionary = output_variant
			var state_path := str(output_data.get("target_state_path", ""))
			var state_data := _find_snapshot_state_in(states, state_path)
			if not state_data.is_empty():
				neighbor_seed_total += (state_data.get("graph_position", Vector2.ZERO) as Vector2).y
				neighbor_seed_count += 1
		seed_y[node_id] = neighbor_seed_total / neighbor_seed_count if neighbor_seed_count > 0 else 0.0
	for transition_data in transitions:
		var transition_node_id := "%s%s" % [_TRANSITION_NODE_PREFIX, str(transition_data.get("transition_id", ""))]
		for condition_variant in transition_data.get("conditions", []):
			var condition_data: Dictionary = condition_variant
			_add_layout_edge(adjacency, indegree, "%s%s" % [_STATE_NODE_PREFIX, str(condition_data.get("target_state_path", ""))], transition_node_id)
		for output_variant in transition_data.get("outputs", []):
			var output_data: Dictionary = output_variant
			_add_layout_edge(adjacency, indegree, transition_node_id, "%s%s" % [_STATE_NODE_PREFIX, str(output_data.get("target_state_path", ""))])
	var queue: Array[String] = []
	for node_id_variant in indegree.keys():
		if int(indegree[node_id_variant]) == 0:
			queue.append(str(node_id_variant))
	queue.sort_custom(func(a: String, b: String): return float(seed_y.get(a, 0.0)) < float(seed_y.get(b, 0.0)))
	var visited: Dictionary = {}
	while not queue.is_empty():
		var node_id: String = queue.pop_front()
		visited[node_id] = true
		for target_variant in adjacency.get(node_id, []):
			var target := str(target_variant)
			ranks[target] = maxi(int(ranks.get(target, 0)), int(ranks.get(node_id, 0)) + 1)
			indegree[target] = int(indegree.get(target, 0)) - 1
			if int(indegree[target]) == 0:
				queue.append(target)
	for node_id_variant in adjacency.keys():
		var node_id := str(node_id_variant)
		if not visited.has(node_id):
			ranks[node_id] = 1 if node_id.begins_with(_TRANSITION_NODE_PREFIX) else 0
	var columns: Dictionary = {}
	for node_id_variant in ranks.keys():
		var rank := int(ranks[node_id_variant])
		if not columns.has(rank):
			columns[rank] = []
		(columns[rank] as Array).append(str(node_id_variant))
	var rank_values: Array[int] = []
	for rank_variant in columns.keys():
		rank_values.append(int(rank_variant))
	rank_values.sort()
	for rank in rank_values:
		var node_ids: Array[String] = []
		for node_id_variant in columns[rank]:
			node_ids.append(str(node_id_variant))
		node_ids.sort_custom(func(a, b):
			var a_seed := float(seed_y.get(str(a), 0.0))
			var b_seed := float(seed_y.get(str(b), 0.0))
			return str(a) < str(b) if is_equal_approx(a_seed, b_seed) else a_seed < b_seed
		)
		_place_node_column(node_ids, float(rank) * 1180.0, 120.0, 180.0, true, 240.0)
	_persist_all_visible_positions()


func _find_snapshot_state_in(states: Array[Dictionary], state_path: String) -> Dictionary:
	for state_data in states:
		if str(state_data.get("path", "")) == state_path:
			return state_data
	return {}


func _add_layout_edge(adjacency: Dictionary, indegree: Dictionary, source: String, target: String) -> void:
	if not adjacency.has(source) or not adjacency.has(target) or (adjacency[source] as Array).has(target):
		return
	(adjacency[source] as Array).append(target)
	indegree[target] = int(indegree.get(target, 0)) + 1


func _filtered_visible_states(states: Array) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for state_variant in states:
		var state_data: Dictionary = state_variant
		var node_id := "%s%s" % [_STATE_NODE_PREFIX, str(state_data.get("path", ""))]
		if _as_bool(_node_visibility.get(node_id, false)):
			filtered.append(state_data)
	return filtered


func _filtered_visible_transitions(transitions: Array) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for transition_variant in transitions:
		var transition_data: Dictionary = transition_variant
		var node_id := "%s%s" % [_TRANSITION_NODE_PREFIX, str(transition_data.get("transition_id", ""))]
		if _as_bool(_node_visibility.get(node_id, true)):
			filtered.append(transition_data)
	return filtered


func _auto_arrange_missing_nodes(states: Array[Dictionary], transitions: Array[Dictionary], include_existing: bool = false) -> void:
	if states.is_empty() and transitions.is_empty():
		return
	var incoming_by_state: Dictionary = {}
	var outgoing_by_state: Dictionary = {}
	var transitions_by_id: Dictionary = {}
	for state_data in states:
		var state_path := str(state_data.get("path", ""))
		incoming_by_state[state_path] = []
		outgoing_by_state[state_path] = []
	for transition_data in transitions:
		var transition_id := str(transition_data.get("transition_id", ""))
		transitions_by_id[transition_id] = transition_data
		for condition_variant in transition_data.get("conditions", []):
			var condition_data: Dictionary = condition_variant
			var condition_state := str(condition_data.get("target_state_path", ""))
			if outgoing_by_state.has(condition_state):
				(outgoing_by_state[condition_state] as Array).append(transition_id)
		for output_variant in transition_data.get("outputs", []):
			var output_data: Dictionary = output_variant
			var output_state := str(output_data.get("target_state_path", ""))
			if incoming_by_state.has(output_state):
				(incoming_by_state[output_state] as Array).append(transition_id)

	var left_far: Array[Dictionary] = []
	var left_near: Array[Dictionary] = []
	var right_near: Array[Dictionary] = []
	var right_far: Array[Dictionary] = []
	for state_data in states:
		var state_path := str(state_data.get("path", ""))
		var incoming_count := (incoming_by_state.get(state_path, []) as Array).size()
		var outgoing_count := (outgoing_by_state.get(state_path, []) as Array).size()
		if outgoing_count > 0 and incoming_count == 0:
			left_far.append(state_data)
		elif outgoing_count >= incoming_count:
			left_near.append(state_data)
		elif incoming_count > 0 and outgoing_count == 0:
			right_far.append(state_data)
		else:
			right_near.append(state_data)

	var transition_ids := _initial_transition_order(transitions, incoming_by_state, outgoing_by_state)
	var transition_order := _order_map_from_ids(transition_ids)
	for _sweep_index in range(6):
		_sort_states_by_transition_barycenter(left_far, outgoing_by_state, incoming_by_state, transition_order)
		_sort_states_by_transition_barycenter(left_near, outgoing_by_state, incoming_by_state, transition_order)
		var state_order := _build_state_order_map(left_far, left_near, right_near, right_far)
		transition_ids = _reorder_transition_ids(transition_ids, transitions_by_id, state_order)
		transition_order = _order_map_from_ids(transition_ids)
		_sort_states_by_transition_barycenter(right_near, outgoing_by_state, incoming_by_state, transition_order)
		_sort_states_by_transition_barycenter(right_far, outgoing_by_state, incoming_by_state, transition_order)
		state_order = _build_state_order_map(left_far, left_near, right_near, right_far)
		transition_ids = _reorder_transition_ids(transition_ids, transitions_by_id, state_order)
		transition_order = _order_map_from_ids(transition_ids)

	var column_gap := 620.0
	var row_gap := 180.0
	var y_origin := 120.0
	var transition_x := 0.0
	var left_far_width := _max_state_column_width(left_far)
	var left_near_width := _max_state_column_width(left_near)
	var right_near_width := _max_state_column_width(right_near)
	var transition_width := _max_transition_column_width(transitions)

	var left_near_x := transition_x - column_gap - left_near_width
	var left_far_x := left_near_x - column_gap - left_far_width
	var right_near_x := transition_x + transition_width + column_gap
	var right_far_x := right_near_x + right_near_width + column_gap

	var transition_height := _column_total_height(_node_ids_from_transition_ids(transition_ids), 260.0, row_gap)
	var left_far_height := _column_total_height(_node_ids_for_states(left_far), 240.0, row_gap)
	var left_near_height := _column_total_height(_node_ids_for_states(left_near), 240.0, row_gap)
	var right_near_height := _column_total_height(_node_ids_for_states(right_near), 240.0, row_gap)
	var right_far_height := _column_total_height(_node_ids_for_states(right_far), 240.0, row_gap)
	var max_column_height := maxf(transition_height, maxf(left_far_height, maxf(left_near_height, maxf(right_near_height, right_far_height))))

	_place_node_column(
		_node_ids_from_transition_ids(transition_ids),
		transition_x,
		y_origin + ((max_column_height - transition_height) * 0.5),
		row_gap,
		include_existing,
		260.0
	)
	_place_node_column(
		_node_ids_for_states(left_far),
		left_far_x,
		y_origin + ((max_column_height - left_far_height) * 0.5),
		row_gap,
		include_existing,
		240.0
	)
	_place_node_column(
		_node_ids_for_states(left_near),
		left_near_x,
		y_origin + ((max_column_height - left_near_height) * 0.5),
		row_gap,
		include_existing,
		240.0
	)
	_place_node_column(
		_node_ids_for_states(right_near),
		right_near_x,
		y_origin + ((max_column_height - right_near_height) * 0.5),
		row_gap,
		include_existing,
		240.0
	)
	_place_node_column(
		_node_ids_for_states(right_far),
		right_far_x,
		y_origin + ((max_column_height - right_far_height) * 0.5),
		row_gap,
		include_existing,
		240.0
	)
	_persist_all_visible_positions()


func _sort_states_by_transition_barycenter(states: Array[Dictionary], outgoing_by_state: Dictionary, incoming_by_state: Dictionary, transition_order: Dictionary) -> void:
	states.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _state_barycenter(a, outgoing_by_state, incoming_by_state, transition_order) < _state_barycenter(b, outgoing_by_state, incoming_by_state, transition_order)
	)


func _state_barycenter(state_data: Dictionary, outgoing_by_state: Dictionary, incoming_by_state: Dictionary, transition_order: Dictionary) -> float:
	var state_path := str(state_data.get("path", ""))
	var all_transition_ids: Array = []
	all_transition_ids.append_array(outgoing_by_state.get(state_path, []))
	all_transition_ids.append_array(incoming_by_state.get(state_path, []))
	if all_transition_ids.is_empty():
		return 0.0
	var total := 0.0
	var count := 0.0
	for transition_id_variant in all_transition_ids:
		var transition_id := str(transition_id_variant)
		if not transition_order.has(transition_id):
			continue
		total += _as_float(transition_order[transition_id])
		count += 1.0
	if count <= 0.0:
		return 1000000.0
	return total / count


func _initial_transition_order(transitions: Array[Dictionary], incoming_by_state: Dictionary, outgoing_by_state: Dictionary) -> Array[String]:
	var ordered := transitions.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score := _transition_initial_score(a, incoming_by_state, outgoing_by_state)
		var b_score := _transition_initial_score(b, incoming_by_state, outgoing_by_state)
		if is_equal_approx(a_score, b_score):
			return str(a.get("transition_id", "")) < str(b.get("transition_id", ""))
		return a_score < b_score
	)
	var transition_ids: Array[String] = []
	for transition_data in ordered:
		transition_ids.append(str(transition_data.get("transition_id", "")))
	return transition_ids


func _transition_initial_score(transition_data: Dictionary, incoming_by_state: Dictionary, outgoing_by_state: Dictionary) -> float:
	var total := 0.0
	var count := 0.0
	for condition_variant in transition_data.get("conditions", []):
		var condition_data: Dictionary = condition_variant
		var state_path := str(condition_data.get("target_state_path", ""))
		total += _state_path_rank_seed(state_path, outgoing_by_state, incoming_by_state)
		count += 1.0
	for output_variant in transition_data.get("outputs", []):
		var output_data: Dictionary = output_variant
		var state_path := str(output_data.get("target_state_path", ""))
		total += _state_path_rank_seed(state_path, outgoing_by_state, incoming_by_state)
		count += 1.0
	return (total / count) if count > 0.0 else 1000000.0


func _state_path_rank_seed(state_path: String, outgoing_by_state: Dictionary, incoming_by_state: Dictionary) -> float:
	var outgoing_count := (outgoing_by_state.get(state_path, []) as Array).size()
	var incoming_count := (incoming_by_state.get(state_path, []) as Array).size()
	var column_weight := 0.0
	if outgoing_count > 0 and incoming_count == 0:
		column_weight = 0.0
	elif outgoing_count >= incoming_count:
		column_weight = 1.0
	elif incoming_count > 0 and outgoing_count == 0:
		column_weight = 3.0
	else:
		column_weight = 2.0
	return column_weight * 1000.0 + _as_float(abs(state_path.hash()) % 1000)


func _build_state_order_map(
	left_far: Array[Dictionary],
	left_near: Array[Dictionary],
	right_near: Array[Dictionary],
	right_far: Array[Dictionary]
) -> Dictionary:
	var state_order: Dictionary = {}
	_assign_state_order_for_column(state_order, left_far, 0)
	_assign_state_order_for_column(state_order, left_near, 1)
	_assign_state_order_for_column(state_order, right_near, 2)
	_assign_state_order_for_column(state_order, right_far, 3)
	return state_order


func _assign_state_order_for_column(state_order: Dictionary, states: Array[Dictionary], column_index: int) -> void:
	for row_index in range(states.size()):
		var state_data: Dictionary = states[row_index]
		state_order[str(state_data.get("path", ""))] = _as_float(column_index) * 10000.0 + _as_float(row_index)


func _reorder_transition_ids(transition_ids: Array[String], transitions_by_id: Dictionary, state_order: Dictionary) -> Array[String]:
	var scored_ids: Array[Dictionary] = []
	for transition_id in transition_ids:
		var transition_data: Dictionary = transitions_by_id.get(transition_id, {})
		scored_ids.append({
			"id": transition_id,
			"score": _transition_barycenter(transition_data, state_order),
			"spread": _transition_neighbor_spread(transition_data, state_order),
		})
	scored_ids.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score := _as_float(a.get("score", 0.0))
		var b_score := _as_float(b.get("score", 0.0))
		if is_equal_approx(a_score, b_score):
			var a_spread := _as_float(a.get("spread", 0.0))
			var b_spread := _as_float(b.get("spread", 0.0))
			if is_equal_approx(a_spread, b_spread):
				return str(a.get("id", "")) < str(b.get("id", ""))
			return a_spread < b_spread
		return a_score < b_score
	)
	var reordered: Array[String] = []
	for scored in scored_ids:
		reordered.append(str(scored.get("id", "")))
	return reordered


func _order_map_from_ids(ids: Array[String]) -> Dictionary:
	var order: Dictionary = {}
	for index in range(ids.size()):
		order[ids[index]] = index
	return order


func _transition_barycenter(transition_data: Dictionary, state_order: Dictionary) -> float:
	var total := 0.0
	var count := 0.0
	for condition_variant in transition_data.get("conditions", []):
		var condition_data: Dictionary = condition_variant
		var state_path := str(condition_data.get("target_state_path", ""))
		if state_order.has(state_path):
			total += _as_float(state_order[state_path])
			count += 1.0
	for output_variant in transition_data.get("outputs", []):
		var output_data: Dictionary = output_variant
		var state_path := str(output_data.get("target_state_path", ""))
		if state_order.has(state_path):
			total += _as_float(state_order[state_path])
			count += 1.0
	return (total / count) if count > 0.0 else 1000000.0


func _transition_neighbor_spread(transition_data: Dictionary, state_order: Dictionary) -> float:
	var min_order := INF
	var max_order := -INF
	for condition_variant in transition_data.get("conditions", []):
		var condition_data: Dictionary = condition_variant
		var state_path := str(condition_data.get("target_state_path", ""))
		if not state_order.has(state_path):
			continue
		var state_value := _as_float(state_order[state_path])
		min_order = minf(min_order, state_value)
		max_order = maxf(max_order, state_value)
	for output_variant in transition_data.get("outputs", []):
		var output_data: Dictionary = output_variant
		var state_path := str(output_data.get("target_state_path", ""))
		if not state_order.has(state_path):
			continue
		var state_value := _as_float(state_order[state_path])
		min_order = minf(min_order, state_value)
		max_order = maxf(max_order, state_value)
	if min_order == INF or max_order == -INF:
		return 0.0
	return max_order - min_order


func _node_ids_for_states(states: Array[Dictionary]) -> Array[String]:
	var node_ids: Array[String] = []
	for state_data in states:
		node_ids.append("%s%s" % [_STATE_NODE_PREFIX, str(state_data.get("path", ""))])
	return node_ids


func _node_ids_for_transitions(transitions: Array[Dictionary]) -> Array[String]:
	var node_ids: Array[String] = []
	for transition_data in transitions:
		node_ids.append("%s%s" % [_TRANSITION_NODE_PREFIX, str(transition_data.get("transition_id", ""))])
	return node_ids


func _node_ids_from_transition_ids(transition_ids: Array[String]) -> Array[String]:
	var node_ids: Array[String] = []
	for transition_id in transition_ids:
		node_ids.append("%s%s" % [_TRANSITION_NODE_PREFIX, transition_id])
	return node_ids


func _place_node_column(
	node_ids: Array[String],
	x: float,
	y_origin: float,
	spacing: float,
	include_existing: bool,
	fallback_height: float
) -> void:
	var cursor_y := y_origin
	for node_id in node_ids:
		_set_node_position_if_needed(node_id, Vector2(x, cursor_y), include_existing)
		cursor_y += _node_height(node_id, fallback_height) + spacing


func _column_total_height(node_ids: Array[String], fallback_height: float, spacing: float) -> float:
	if node_ids.is_empty():
		return 0.0
	var total := 0.0
	for index in range(node_ids.size()):
		total += _node_height(node_ids[index], fallback_height)
		if index < node_ids.size() - 1:
			total += spacing
	return total


func _max_state_column_width(states: Array[Dictionary]) -> float:
	var max_width := 520.0
	for node_id in _node_ids_for_states(states):
		max_width = maxf(max_width, _node_width(node_id, 520.0))
	return max_width


func _max_transition_column_width(transitions: Array[Dictionary]) -> float:
	var max_width := 420.0
	for node_id in _node_ids_for_transitions(transitions):
		max_width = maxf(max_width, _node_width(node_id, 420.0))
	return max_width


func _node_width(node_id: String, fallback_width: float) -> float:
	var node := _nodes_by_id.get(node_id) as Control
	if node == null:
		return fallback_width
	var minimum_size := node.get_combined_minimum_size()
	return maxf(fallback_width, maxf(minimum_size.x, node.size.x))


func _node_height(node_id: String, fallback_height: float) -> float:
	var node := _nodes_by_id.get(node_id) as Control
	if node == null:
		return fallback_height
	var minimum_size := node.get_combined_minimum_size()
	return maxf(fallback_height, maxf(minimum_size.y, node.size.y))


func _update_compact_graph_mode() -> bool:
	if _graph_edit == null:
		return false
	var target_compact_mode := _graph_edit.zoom <= 0.7
	if _compact_graph_mode == target_compact_mode:
		return false
	_compact_graph_mode = target_compact_mode
	for node_variant in _nodes_by_id.values():
		var node := node_variant as GraphNode
		if node == null:
			continue
		_apply_compact_mode_to_node(node)
	return true


func _apply_compact_mode_to_node(node: GraphNode) -> void:
	var compact_title := node.get_node_or_null("CompactTitle") as Label
	var body := node.get_node_or_null("Body") as Control
	var full_title := str(node.get_meta("full_title", node.title.strip_edges()))
	if compact_title != null:
		compact_title.text = full_title
		_fit_compact_title(compact_title, node, full_title)
		compact_title.visible = _compact_graph_mode
	if body != null:
		body.visible = not _compact_graph_mode
	node.title = "" if _compact_graph_mode else "  %s" % full_title
	var type_button := node.get_node_or_null("TypeButton") as OptionButton
	if type_button != null:
		type_button.visible = not _compact_graph_mode


func _set_node_position_if_needed(node_id: String, position: Vector2, include_existing: bool) -> void:
	var node := _nodes_by_id.get(node_id) as GraphNode
	if node == null:
		return
	if not include_existing and node.position_offset != Vector2.ZERO:
		return
	node.position_offset = position
	_node_positions[node_id] = position


func _capture_node_position_changes() -> bool:
	var changed := false
	for node_id_variant in _nodes_by_id.keys():
		var node_id := str(node_id_variant)
		var node := _nodes_by_id[node_id] as GraphNode
		if node == null:
			continue
		var old_position: Vector2 = _node_positions.get(node_id, Vector2.INF)
		if old_position == node.position_offset:
			continue
		_node_positions[node_id] = node.position_offset
		_persist_node_position(node_id, node.position_offset)
		changed = true
	return changed


func _graph_view_transform() -> Vector3:
	if _graph_edit == null:
		return Vector3.ZERO
	return Vector3(_graph_edit.scroll_offset.x, _graph_edit.scroll_offset.y, _graph_edit.zoom)


func _capture_graph_view_transform_change() -> bool:
	var next_transform := _graph_view_transform()
	if next_transform == _last_graph_view_transform:
		return false
	_last_graph_view_transform = next_transform
	_graph_transform_redraw_revision += 1
	return true


func _on_graph_view_transform_changed(_scroll_offset: Vector2) -> void:
	_capture_graph_view_transform_change()
	_queue_overlay_redraw()


func _on_graph_viewport_changed() -> void:
	_capture_graph_view_transform_change()
	_queue_overlay_redraw()


func _clear_container_children(container: Control) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.free()


func _assign_port_metadata(port: Control, port_info: Dictionary) -> void:
	if port == null:
		return
	port.set_meta("port_info", port_info.duplicate(true))


func _set_graph_node_title(node: GraphNode, title_text: String) -> void:
	if node == null:
		return
	node.set_meta("full_title", title_text)
	node.title = "" if _compact_graph_mode else "  %s" % title_text


func _style_graph_node_titlebar(node: GraphNode, text_color: Color) -> void:
	if node == null or not node.has_method("get_titlebar_hbox"):
		return
	var titlebar_hbox := node.call("get_titlebar_hbox") as HBoxContainer
	if titlebar_hbox == null:
		return
	for child in titlebar_hbox.get_children():
		if child is Label:
			var label := child as Label
			label.text = "  %s" % str(node.get_meta("full_title", label.text))
			label.add_theme_color_override("font_color", text_color)
			label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.0))
			label.add_theme_font_size_override("font_size", 40)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _fit_compact_title(compact_title: Label, node: GraphNode, title_text: String) -> void:
	if compact_title == null or node == null:
		return
	var available_width := maxf(180.0, maxf(node.size.x, node.custom_minimum_size.x) - 28.0)
	var length := maxf(4.0, _as_float(title_text.length()))
	var font_size := clampf((available_width * 1.45) / length, 26.0, 56.0)
	compact_title.add_theme_font_size_override("font_size", int(round(font_size)))


func _graph_point_to_canvas_global(graph_point: Vector2) -> Vector2:
	if _graph_edit == null:
		return graph_point
	var canvas_point := (graph_point - _graph_edit.scroll_offset) * _graph_edit.zoom
	return _graph_edit.get_global_transform_with_canvas() * canvas_point


func _graph_edit_local_to_graph_position(local_position: Vector2) -> Vector2:
	if _graph_edit == null:
		return local_position
	return _graph_edit.scroll_offset + (local_position / maxf(_graph_edit.zoom, 0.001))


func _viewport_to_graph_position(viewport_position: Vector2) -> Vector2:
	if _graph_edit == null:
		return viewport_position
	var local_position := _graph_edit.get_global_transform_with_canvas().affine_inverse() * viewport_position
	return _graph_edit_local_to_graph_position(local_position)


func _find_port_at_viewport_position(viewport_position: Vector2) -> Dictionary:
	for port_variant in _state_header_ports.values():
		var port := port_variant as Control
		if port != null and port.get_global_rect().has_point(viewport_position):
			return {"port": port, "info": port.get_meta("port_info", {})}
	for port_variant in _transition_condition_ports.values():
		var port := port_variant as Control
		if port != null and port.get_global_rect().has_point(viewport_position):
			return {"port": port, "info": port.get_meta("port_info", {})}
	for port_variant in _transition_output_ports.values():
		var port := port_variant as Control
		if port != null and port.get_global_rect().has_point(viewport_position):
			return {"port": port, "info": port.get_meta("port_info", {})}
	for port_variant in _state_claim_ports.values():
		var port := port_variant as Control
		if port != null and port.get_global_rect().has_point(viewport_position):
			return {"port": port, "info": port.get_meta("port_info", {})}
	return {}


func _on_port_gui_input(event: InputEvent, port: Control) -> void:
	if !_is_graph_input_enabled():
		return
	if presentation_mode == _PRESENTATION_MODE_TRANSPARENT_OVERLAY or database == null or port == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button.button_index != MOUSE_BUTTON_LEFT or not mouse_button.pressed:
		return
	_begin_drag_connection({
		"port": port,
		"info": port.get_meta("port_info", {}),
	}, port.get_global_rect().get_center())
	get_viewport().set_input_as_handled()


func _begin_drag_connection(origin: Dictionary, viewport_position: Vector2) -> void:
	_drag_connection_origin = origin
	_drag_connection_hover = {}
	_drag_connection_start_viewport_position = viewport_position
	_drag_connection_mouse_graph_position = _viewport_to_graph_position(viewport_position)
	_queue_overlay_redraw()


func _on_claim_handle_gui_input(event: InputEvent, state_path: String, slot_id: String) -> void:
	if !_is_graph_input_enabled():
		return
	if presentation_mode == _PRESENTATION_MODE_TRANSPARENT_OVERLAY or database == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button.button_index != MOUSE_BUTTON_LEFT or not mouse_button.pressed:
		return
	_drag_claim_origin = {
		"state_path": state_path,
		"slot_id": slot_id,
	}
	get_viewport().set_input_as_handled()


func _find_claim_drop_target_at_viewport_position(viewport_position: Vector2) -> Dictionary:
	for key_variant in _claim_row_panels.keys():
		var key := str(key_variant)
		var panel := _claim_row_panels.get(key) as Control
		if panel == null or not panel.get_global_rect().has_point(viewport_position):
			continue
		var split := key.split("::")
		if split.size() < 2:
			continue
		return {
			"state_path": split[0],
			"slot_id": split[1],
			"before": viewport_position.y < panel.get_global_rect().get_center().y,
		}
	return {}


func _on_graph_edit_gui_input(event: InputEvent) -> void:
	if !_is_graph_input_enabled():
		return
	if presentation_mode == _PRESENTATION_MODE_TRANSPARENT_OVERLAY or database == null:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_BACKSPACE:
			var selected_node_ids := _selected_node_ids()
			for node_id in selected_node_ids:
				_persist_visibility(node_id, false)
			if not selected_node_ids.is_empty():
				_rebuild_from_current_state()
				accept_event()
			return
	if not (event is InputEventMouseButton):
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
		var node_id := _node_id_at_viewport_position(get_viewport().get_mouse_position())
		if node_id.is_empty():
			_canvas_context_graph_position = _graph_edit_local_to_graph_position(mouse_button.position)
			_canvas_context_menu.position = DisplayServer.mouse_get_position()
			_canvas_context_menu.popup()
		return


func _input(event: InputEvent) -> void:
	if !_is_graph_input_enabled():
		return
	if not _drag_claim_origin.is_empty():
		if presentation_mode == _PRESENTATION_MODE_TRANSPARENT_OVERLAY:
			_drag_claim_origin.clear()
			return
		if event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			var claim_mouse_button := event as InputEventMouseButton
			if claim_mouse_button.button_index == MOUSE_BUTTON_LEFT and not claim_mouse_button.pressed:
				var claim_target := _find_claim_drop_target_at_viewport_position(claim_mouse_button.position)
				if not claim_target.is_empty() and str(claim_target.get("state_path", "")) == str(_drag_claim_origin.get("state_path", "")):
					var target_state_path := str(claim_target.get("state_path", ""))
					var target_slot_id := str(claim_target.get("slot_id", ""))
					var before := _as_bool(claim_target.get("before", true))
					_move_claim_slot_to_slot(target_state_path, str(_drag_claim_origin.get("slot_id", "")), target_slot_id, before)
				_drag_claim_origin.clear()
				get_viewport().set_input_as_handled()
			return
	if _drag_connection_origin.is_empty():
		return
	if presentation_mode == _PRESENTATION_MODE_TRANSPARENT_OVERLAY:
		_drag_connection_origin.clear()
		_drag_connection_hover.clear()
		_queue_overlay_redraw()
		return
	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		_drag_connection_mouse_graph_position = _viewport_to_graph_position(mouse_motion.position)
		_drag_connection_hover = _find_port_at_viewport_position(mouse_motion.position)
		_queue_overlay_redraw()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button.button_index != MOUSE_BUTTON_LEFT or mouse_button.pressed:
		return
	var target_port := _find_port_at_viewport_position(mouse_button.position)
	var dragged_distance := mouse_button.position.distance_to(_drag_connection_start_viewport_position)
	if not target_port.is_empty() and dragged_distance > _OUTPUT_PICKER_CLICK_DISTANCE:
		_apply_drag_connection(_drag_connection_origin, target_port)
	elif dragged_distance <= _OUTPUT_PICKER_CLICK_DISTANCE:
		_open_output_picker_for_origin(_drag_connection_origin)
	_drag_connection_origin.clear()
	_drag_connection_hover.clear()
	_queue_overlay_redraw()
	get_viewport().set_input_as_handled()


func _open_output_picker_for_origin(origin: Dictionary) -> bool:
	if database == null or _output_picker == null:
		return false
	var info_variant: Variant = origin.get("info", {})
	var info: Dictionary = info_variant if info_variant is Dictionary else {}
	if not str(info.get("role", "")) in ["transition_output", "transition_output_new"]:
		return false
	var transition_id := int(info.get("transition_id", 0))
	var targets := _build_output_picker_targets(transition_id)
	if targets.is_empty():
		return false
	_output_picker_context = {
		"transition_id": transition_id,
	}
	_output_picker.call("configure", targets)
	_output_picker.call("show_at", DisplayServer.mouse_get_position())
	return true


func _build_output_picker_targets(transition_id: int) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if database == null or database.get_transition_by_id(transition_id) == null:
		return targets
	for state_variant in database.get_state_definitions():
		var state_def := state_variant as StateVariableDefScript
		if state_def == null or state_def.get_normalized_path() == &"":
			continue
		targets.append({
			"state_path": String(state_def.get_normalized_path()),
			"label": "%s  (%s)" % [state_def.get_leaf_name(), String(state_def.get_normalized_path())],
		})
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("state_path", "")) < str(b.get("state_path", ""))
	)
	return targets


func _on_output_picker_target_selected(state_path: String) -> void:
	if database == null or _output_picker_context.is_empty():
		return
	var transition_id := int(_output_picker_context.get("transition_id", 0))
	_output_picker_context.clear()
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	if not _apply_output_connection_to_snapshot(states, transitions, transition_id, -1, state_path, "", true):
		return
	var target_node_id := "%s%s" % [_STATE_NODE_PREFIX, state_path]
	if not _as_bool(_node_visibility.get(target_node_id, false)):
		var target_state := _find_state_def_in_array(states, state_path)
		if target_state == null:
			return
		target_state.graph_position = _find_output_reveal_position(transition_id, target_state)
		_persist_visibility(target_node_id, true)
	_commit_database_snapshot_change("Create Transition Output", states, transitions)


func _apply_drag_connection(origin: Dictionary, target: Dictionary) -> void:
	if database == null:
		return
	var action := _resolve_drag_connection_action(origin.get("info", {}), target.get("info", {}))
	if action.is_empty():
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var transition_id := int(action.get("transition_id", 0))
	var transition_def := _find_transition_def_in_array(transitions, transition_id)
	if transition_def == null:
		return
	match str(action.get("type", "")):
		"condition":
			var condition_index := int(action.get("condition_index", -1))
			var state_path := str(action.get("state_path", ""))
			var target_state := _find_state_def_in_array(states, state_path)
			if target_state == null:
				return
			if condition_index >= 0 and condition_index < transition_def.conditions.size():
				var existing_condition := transition_def.conditions[condition_index]
				if existing_condition == null:
					return
				existing_condition.target_state_path = StringName(state_path)
			else:
				var new_condition := StateTransitionConditionDefScript.new()
				new_condition.target_state_path = StringName(state_path)
				new_condition.set_expected_value(target_state, target_state.default_value)
				transition_def.conditions.append(new_condition)
		"output":
			var output_index := int(action.get("output_index", -1))
			var target_state_path := str(action.get("state_path", ""))
			if not _apply_output_connection_to_snapshot(
				states,
				transitions,
				transition_id,
				output_index,
				target_state_path,
				str(action.get("slot_id", "")),
				_as_bool(action.get("force_new_slot", false))
			):
				return
		_:
			return
	_commit_database_snapshot_change("Edit Transition Connection", states, transitions)


func _apply_output_connection_to_snapshot(
	states: Array,
	transitions: Array,
	transition_id: int,
	output_index: int,
	target_state_path: String,
	preferred_slot_id: String = "",
	force_new_slot: bool = false
) -> bool:
	var transition_def := _find_transition_def_in_array(transitions, transition_id)
	var target_state := _find_state_def_in_array(states, target_state_path)
	if transition_def == null or target_state == null:
		return false
	var slot_id := _ensure_transition_claim_slot_in_snapshot(
		states,
		target_state_path,
		transition_id,
		preferred_slot_id,
		force_new_slot
	)
	if slot_id == &"":
		return false
	if output_index >= 0 and output_index < transition_def.outputs.size():
		var existing_output := transition_def.outputs[output_index] as StateTransitionOutputDefScript
		if existing_output == null:
			return false
		existing_output.target_state_path = StringName(target_state_path)
		existing_output.target_claim_slot_id = slot_id
		existing_output.operation = int(StateTransitionOutputDefScript.Operation.ADD) if target_state.value_type == StateVariableDefScript.ValueType.LIST else int(StateTransitionOutputDefScript.Operation.SET)
	else:
		var new_output := StateTransitionOutputDefScript.new()
		new_output.target_state_path = StringName(target_state_path)
		new_output.target_claim_slot_id = slot_id
		new_output.operation = int(StateTransitionOutputDefScript.Operation.ADD) if target_state.value_type == StateVariableDefScript.ValueType.LIST else int(StateTransitionOutputDefScript.Operation.SET)
		new_output.set_target_value(target_state, "" if target_state.value_type == StateVariableDefScript.ValueType.LIST else target_state.default_value)
		transition_def.outputs.append(new_output)
	return true


func _delete_transition_output(transition_id: int, output_index: int) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	if not _delete_transition_output_from_snapshot(states, transitions, transition_id, output_index):
		return
	_commit_database_snapshot_change("Delete Transition Output", states, transitions)


func _delete_transition_output_from_snapshot(
	states: Array,
	transitions: Array,
	transition_id: int,
	output_index: int
) -> bool:
	var transition_def := _find_transition_def_in_array(transitions, transition_id)
	if transition_def == null or output_index < 0 or output_index >= transition_def.outputs.size():
		return false
	var output_def := transition_def.outputs[output_index] as StateTransitionOutputDefScript
	if output_def == null:
		return false
	var target_state_path := output_def.get_normalized_target_state_path()
	var target_slot_id := output_def.get_normalized_target_claim_slot_id()
	transition_def.outputs.remove_at(output_index)
	if target_state_path == &"" or target_slot_id == &"":
		return true
	if _snapshot_output_references_slot(transitions, target_state_path, target_slot_id):
		return true
	var target_state := _find_state_def_in_array(states, String(target_state_path))
	if target_state == null:
		return true
	for slot_index in range(target_state.claim_slots.size() - 1, -1, -1):
		var slot_def := target_state.claim_slots[slot_index] as StateClaimSlotDefScript
		if slot_def == null or slot_def.get_normalized_slot_id() != target_slot_id:
			continue
		if slot_def.get_normalized_transition_id() == transition_id and slot_def.get_normalized_code_key() == &"":
			target_state.claim_slots.remove_at(slot_index)
			target_state.ensure_valid_configuration()
		break
	return true


func _snapshot_output_references_slot(
	transitions: Array,
	target_state_path: StringName,
	target_slot_id: StringName
) -> bool:
	for transition_variant in transitions:
		var transition_def := transition_variant as StateTransitionDefScript
		if transition_def == null:
			continue
		for output_variant in transition_def.outputs:
			var output_def := output_variant as StateTransitionOutputDefScript
			if output_def != null \
					and output_def.get_normalized_target_state_path() == target_state_path \
					and output_def.get_normalized_target_claim_slot_id() == target_slot_id:
				return true
	return false


func _find_output_reveal_position(transition_id: int, target_state: StateVariableDefScript) -> Vector2:
	var source_node := _nodes_by_id.get("%s%d" % [_TRANSITION_NODE_PREFIX, transition_id]) as GraphNode
	var source_rect := Rect2(Vector2.ZERO, Vector2(_GRAPH_NODE_FIXED_WIDTH, _GRAPH_NODE_MIN_HEIGHT))
	if source_node != null:
		source_rect = Rect2(source_node.position_offset, source_node.size)
	var target_size := _estimated_state_node_size(target_state)
	var occupied_rects: Array[Rect2] = []
	for node_variant in _nodes_by_id.values():
		var node := node_variant as GraphNode
		if node != null:
			occupied_rects.append(Rect2(node.position_offset, node.size))
	return _nearest_output_reveal_position(source_rect, target_size, occupied_rects)


func _estimated_state_node_size(target_state: StateVariableDefScript) -> Vector2:
	if target_state == null:
		return Vector2(_GRAPH_NODE_FIXED_WIDTH, 420.0)
	return Vector2(
		_GRAPH_NODE_FIXED_WIDTH,
		maxf(420.0, 420.0 + _as_float(target_state.claim_slots.size()) * 76.0)
	)


func _nearest_output_reveal_position(
	source_rect: Rect2,
	target_size: Vector2,
	occupied_rects: Array[Rect2]
) -> Vector2:
	var preferred := Vector2(
		source_rect.end.x + _OUTPUT_REVEAL_HORIZONTAL_GAP,
		source_rect.get_center().y - target_size.y * 0.5
	)
	var x_step := target_size.x + _OUTPUT_REVEAL_HORIZONTAL_GAP
	var y_step := maxf(target_size.y, 240.0) + _OUTPUT_REVEAL_VERTICAL_GAP
	var extent := maxi(16, occupied_rects.size() * 2 + 4)
	var candidates: Array[Dictionary] = []
	for column in range(extent):
		for row in range(-extent, extent + 1):
			var offset := Vector2(_as_float(column) * x_step, _as_float(row) * y_step)
			candidates.append({
				"position": preferred + offset,
				"distance_squared": offset.length_squared(),
				"column": column,
				"row": row,
				"row_rank": _output_reveal_row_rank(row),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance := _as_float(a.get("distance_squared", 0.0))
		var b_distance := _as_float(b.get("distance_squared", 0.0))
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		var a_column := int(a.get("column", 0))
		var b_column := int(b.get("column", 0))
		if a_column != b_column:
			return a_column < b_column
		var a_row := int(a.get("row", 0))
		var b_row := int(b.get("row", 0))
		if absi(a_row) != absi(b_row):
			return absi(a_row) < absi(b_row)
		return int(a.get("row_rank", 0)) < int(b.get("row_rank", 0))
	)
	for candidate in candidates:
		var position: Vector2 = candidate.get("position", preferred)
		var expanded_rect := Rect2(position, target_size).grow(_OUTPUT_REVEAL_COLLISION_MARGIN)
		var collides := false
		for occupied_rect in occupied_rects:
			if expanded_rect.intersects(occupied_rect):
				collides = true
				break
		if not collides:
			return position
	return preferred + Vector2(_as_float(extent) * x_step, 0.0)


func _output_reveal_row_rank(row: int) -> int:
	if row == 0:
		return 0
	return absi(row) * 2 - (1 if row < 0 else 0)


func _resolve_drag_connection_action(origin_info_variant: Variant, target_info_variant: Variant) -> Dictionary:
	var origin_info: Dictionary = origin_info_variant if origin_info_variant is Dictionary else {}
	var target_info: Dictionary = target_info_variant if target_info_variant is Dictionary else {}
	var origin_role := str(origin_info.get("role", ""))
	var target_role := str(target_info.get("role", ""))
	if origin_role == "state_header" and target_role == "transition_condition":
		return {
			"type": "condition",
			"state_path": str(origin_info.get("state_path", "")),
			"transition_id": int(target_info.get("transition_id", 0)),
			"condition_index": int(target_info.get("condition_index", -1)),
		}
	if origin_role == "transition_condition" and target_role == "state_header":
		return {
			"type": "condition",
			"state_path": str(target_info.get("state_path", "")),
			"transition_id": int(origin_info.get("transition_id", 0)),
			"condition_index": int(origin_info.get("condition_index", -1)),
		}
	if origin_role == "transition_output" and target_role == "state_claim":
		return {
			"type": "output",
			"transition_id": int(origin_info.get("transition_id", 0)),
			"output_index": int(origin_info.get("output_index", -1)),
			"state_path": str(target_info.get("state_path", "")),
			"slot_id": str(target_info.get("slot_id", "")),
		}
	if origin_role == "state_claim" and target_role == "transition_output":
		return {
			"type": "output",
			"transition_id": int(target_info.get("transition_id", 0)),
			"output_index": int(target_info.get("output_index", -1)),
			"state_path": str(origin_info.get("state_path", "")),
			"slot_id": str(origin_info.get("slot_id", "")),
		}
	if origin_role == "transition_output" and target_role == "state_claim_new":
		return {
			"type": "output",
			"transition_id": int(origin_info.get("transition_id", 0)),
			"output_index": int(origin_info.get("output_index", -1)),
			"state_path": str(target_info.get("state_path", "")),
			"slot_id": "",
			"force_new_slot": true,
		}
	if origin_role == "state_claim_new" and target_role == "transition_output":
		return {
			"type": "output",
			"transition_id": int(target_info.get("transition_id", 0)),
			"output_index": int(target_info.get("output_index", -1)),
			"state_path": str(origin_info.get("state_path", "")),
			"slot_id": "",
			"force_new_slot": true,
		}
	if origin_role == "transition_output" and target_role == "state_header":
		return {
			"type": "output",
			"transition_id": int(origin_info.get("transition_id", 0)),
			"output_index": int(origin_info.get("output_index", -1)),
			"state_path": str(target_info.get("state_path", "")),
			"slot_id": "",
		}
	if origin_role == "transition_output_new" and target_role == "state_header":
		return {
			"type": "output",
			"transition_id": int(origin_info.get("transition_id", 0)),
			"output_index": -1,
			"state_path": str(target_info.get("state_path", "")),
			"slot_id": "",
		}
	if origin_role == "transition_output_new" and target_role == "state_claim":
		return {
			"type": "output",
			"transition_id": int(origin_info.get("transition_id", 0)),
			"output_index": -1,
			"state_path": str(target_info.get("state_path", "")),
			"slot_id": str(target_info.get("slot_id", "")),
		}
	if origin_role == "transition_output_new" and target_role == "state_claim_new":
		return {
			"type": "output",
			"transition_id": int(origin_info.get("transition_id", 0)),
			"output_index": -1,
			"state_path": str(target_info.get("state_path", "")),
			"slot_id": "",
			"force_new_slot": true,
		}
	if origin_role == "state_claim" and target_role == "transition_output_new":
		return {
			"type": "output",
			"transition_id": int(target_info.get("transition_id", 0)),
			"output_index": -1,
			"state_path": str(origin_info.get("state_path", "")),
			"slot_id": str(origin_info.get("slot_id", "")),
		}
	if origin_role == "state_claim_new" and target_role == "transition_output_new":
		return {
			"type": "output",
			"transition_id": int(target_info.get("transition_id", 0)),
			"output_index": -1,
			"state_path": str(origin_info.get("state_path", "")),
			"slot_id": "",
			"force_new_slot": true,
		}
	if origin_role == "state_header" and target_role == "transition_condition_new":
		return {
			"type": "condition",
			"state_path": str(origin_info.get("state_path", "")),
			"transition_id": int(target_info.get("transition_id", 0)),
			"condition_index": -1,
		}
	if origin_role == "transition_condition_new" and target_role == "state_header":
		return {
			"type": "condition",
			"state_path": str(target_info.get("state_path", "")),
			"transition_id": int(origin_info.get("transition_id", 0)),
			"condition_index": -1,
		}
	return {}


func _apply_database_snapshot(states: Array, transitions: Array, bindings: Dictionary = {}, allow_rollback: bool = true) -> bool:
	if database == null:
		return false
	var before_states: Array = _duplicate_resource_array(database.states)
	var before_transitions: Array = _duplicate_resource_array(database.transitions)
	var before_bindings := _binding_values_for_paths(bindings)
	var resources := _preflight_binding_resources(bindings)
	if resources.is_empty() and not bindings.is_empty():
		return false
	database.states = states
	database.transitions = transitions
	database.ensure_valid_configuration()
	if not database.save_to_default_path():
		if allow_rollback:
			_apply_database_snapshot(before_states, before_transitions, before_bindings, false)
		return false
	for resource_path_variant in bindings.keys():
		var resource_path := str(resource_path_variant)
		var properties := resources.get(resource_path) as Resource
		if !StateBindingIndex.is_binding_resource(properties):
			continue
		var next_path := StringName(str(bindings[resource_path_variant]))
		if properties.get(StateBindingIndex.get_property_name()) == next_path:
			continue
		properties.set(StateBindingIndex.get_property_name(), next_path)
		if ResourceSaver.save(properties, resource_path) != OK:
			if allow_rollback:
				_apply_database_snapshot(before_states, before_transitions, before_bindings, false)
			return false
	runtime_snapshot = {}
	_current_structure_signature = ""
	_rebuild_from_current_state()
	database_changed.emit()
	return true


func _commit_database_snapshot_change(action_name: String, new_states: Array, new_transitions: Array, new_bindings: Dictionary = {}) -> void:
	if database == null:
		return
	var old_states: Array = _duplicate_resource_array(database.states)
	var old_transitions: Array = _duplicate_resource_array(database.transitions)
	var old_bindings := _binding_values_for_paths(new_bindings)
	if _undo_redo != null:
		_undo_redo.create_action(action_name)
		_undo_redo.add_do_method(self, "_apply_database_snapshot", new_states, new_transitions, new_bindings)
		_undo_redo.add_undo_method(self, "_apply_database_snapshot", old_states, old_transitions, old_bindings)
		_undo_redo.commit_action()
	else:
		_apply_database_snapshot(new_states, new_transitions, new_bindings)


func _preflight_binding_resources(bindings: Dictionary) -> Dictionary:
	var resources: Dictionary = {}
	for resource_path_variant in bindings.keys():
		var resource_path := str(resource_path_variant)
		if not ResourceLoader.exists(resource_path):
			return {}
		var properties := ResourceLoader.load(resource_path) as Resource
		if !StateBindingIndex.is_binding_resource(properties):
			return {}
		resources[resource_path] = properties
	return resources


func _binding_values_for_paths(bindings: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	for resource_path_variant in bindings.keys():
		var resource_path := str(resource_path_variant)
		var properties := ResourceLoader.load(resource_path) as Resource
		if properties != null:
			values[resource_path] = String(properties.get(StateBindingIndex.get_property_name()))
	return values


func _duplicate_database_arrays() -> Dictionary:
	return {
		"states": _duplicate_resource_array(database.states) if database != null else [],
		"transitions": _duplicate_resource_array(database.transitions) if database != null else [],
	}


func _duplicate_resource_array(source: Array) -> Array:
	var duplicated: Array = source.duplicate(false)
	for index in range(duplicated.size()):
		var resource := duplicated[index] as Resource
		if resource != null:
			duplicated[index] = resource.duplicate(true)
	return duplicated


func _find_state_def_in_array(states: Array, state_path: String) -> StateVariableDefScript:
	var normalized_state_path := StringName(state_path.strip_edges().to_lower())
	for state_variant in states:
		var state_def := state_variant as StateVariableDefScript
		if state_def != null and state_def.get_normalized_path() == normalized_state_path:
			return state_def
	return null


func _find_transition_def_in_array(transitions: Array, transition_id: int) -> StateTransitionDefScript:
	for transition_variant in transitions:
		var transition_def := transition_variant as StateTransitionDefScript
		if transition_def != null and transition_def.get_normalized_transition_id() == transition_id:
			return transition_def
	return null


func _build_state_snapshot_for_editor(definition: StateVariableDefScript, current_value: Variant) -> Dictionary:
	if definition == null:
		return {}
	return {
		"value_type": int(definition.value_type),
		"possible_values": definition.possible_values.duplicate(),
		"resolved_value": _serialize_state_value_for_snapshot(definition, current_value),
		"default_value": _serialize_state_value_for_snapshot(definition, definition.default_value),
	}


func _generate_unique_state_path(states: Array) -> String:
	var base_path := "custom/new_state"
	var candidate := base_path
	var index := 2
	while _find_state_def_in_array(states, candidate) != null:
		candidate = "%s_%d" % [base_path, index]
		index += 1
	return candidate


func _next_transition_id_from_snapshot(transitions: Array) -> int:
	var max_transition_id := 0
	for transition_variant in transitions:
		var transition_def := transition_variant as StateTransitionDefScript
		if transition_def != null:
			max_transition_id = maxi(max_transition_id, transition_def.get_normalized_transition_id())
	return max_transition_id + 1


func _generate_transition_claim_slot_id(state_def: StateVariableDefScript, transition_id: int) -> StringName:
	var base_slot_id := StringName("transition_%d" % transition_id)
	var candidate := base_slot_id
	var suffix := 2
	while state_def.get_claim_slot_by_id(candidate) != null:
		candidate = StringName("%s_%d" % [String(base_slot_id), suffix])
		suffix += 1
	return candidate


func _ensure_transition_claim_slot_in_snapshot(states: Array, state_path: String, transition_id: int, preferred_slot_id: String = "", force_new_slot: bool = false) -> StringName:
	var state_def := _find_state_def_in_array(states, state_path)
	if state_def == null:
		return &""
	if not preferred_slot_id.is_empty():
		var preferred_slot := state_def.get_claim_slot_by_id(StringName(preferred_slot_id))
		if preferred_slot != null:
			if preferred_slot.get_normalized_transition_id() == transition_id:
				return preferred_slot.get_normalized_slot_id()
			if preferred_slot.get_normalized_transition_id() == 0 and not force_new_slot:
				preferred_slot.code_key = &""
				preferred_slot.transition_id = transition_id
				state_def.ensure_valid_configuration()
				return preferred_slot.get_normalized_slot_id()
	if not force_new_slot:
		for slot_variant in state_def.claim_slots:
			var slot_def := slot_variant as StateClaimSlotDefScript
			if slot_def != null and slot_def.get_normalized_transition_id() == transition_id:
				return slot_def.get_normalized_slot_id()
	var new_slot := StateClaimSlotDefScript.new()
	new_slot.slot_id = _generate_transition_claim_slot_id(state_def, transition_id)
	new_slot.transition_id = transition_id
	state_def.claim_slots.append(new_slot)
	state_def.ensure_valid_configuration()
	return new_slot.get_normalized_slot_id()


func _metadata_for_node_id(node_id: String) -> Dictionary:
	if node_id.begins_with(_STATE_NODE_PREFIX):
		var state_path := node_id.trim_prefix(_STATE_NODE_PREFIX)
		return {"kind": "state", "path": state_path, "data": {}}
	if node_id.begins_with(_TRANSITION_NODE_PREFIX):
		var transition_id := int(node_id.trim_prefix(_TRANSITION_NODE_PREFIX))
		var transition_def: StateTransitionDefScript = database.get_transition_by_id(transition_id) if database != null else null
		return {
			"kind": "transition",
			"transition_id": transition_id,
			"data": {"display_name": transition_def.get_display_name() if transition_def != null else ""},
		}
	return {}


func _node_id_at_viewport_position(viewport_position: Vector2) -> String:
	for node_id_variant in _nodes_by_id.keys():
		var node_id := str(node_id_variant)
		var node := _nodes_by_id[node_id] as GraphNode
		if node != null and node.get_global_rect().has_point(viewport_position):
			return node_id
	return ""


func _persist_node_position(node_id: String, position: Vector2) -> void:
	if persist_runtime_layout:
		var config := ConfigFile.new()
		config.load(_LAYOUT_SAVE_PATH)
		config.set_value(
			_LAYOUT_SECTION,
			_layout_storage_key(node_id),
			[position.x, position.y]
		)
		config.save(_LAYOUT_SAVE_PATH)
	if database != null:
		if node_id.begins_with(_STATE_NODE_PREFIX):
			var definition = database.get_state_definition_by_path(node_id.trim_prefix(_STATE_NODE_PREFIX))
			if definition != null:
				definition.graph_position = position
		elif node_id.begins_with(_TRANSITION_NODE_PREFIX):
			var transition = database.get_transition_by_id(int(node_id.trim_prefix(_TRANSITION_NODE_PREFIX)))
			if transition != null:
				transition.graph_position = position


func _persist_all_visible_positions() -> void:
	for node_id_variant in _nodes_by_id.keys():
		var node_id := str(node_id_variant)
		var node := _nodes_by_id[node_id] as GraphNode
		if node == null:
			continue
		_persist_node_position(node_id, node.position_offset)


func _ensure_preferences_loaded() -> void:
	if _preferences_loaded:
		return
	_preferences_loaded = true
	if not persist_runtime_layout:
		return
	var config := ConfigFile.new()
	if config.load(_LAYOUT_SAVE_PATH) != OK:
		return
	if config.has_section(_VISIBILITY_SECTION):
		for key in config.get_section_keys(_VISIBILITY_SECTION):
			var node_id := _layout_node_id_from_storage_key(str(key))
			if not node_id.is_empty():
				_node_visibility[node_id] = _as_bool(
					config.get_value(_VISIBILITY_SECTION, str(key), false)
				)


func _load_persisted_positions() -> void:
	_node_positions.clear()
	if not persist_runtime_layout:
		return
	var config := ConfigFile.new()
	if config.load(_LAYOUT_SAVE_PATH) != OK:
		return
	if not config.has_section(_LAYOUT_SECTION):
		return
	for key_variant in config.get_section_keys(_LAYOUT_SECTION):
		var key := str(key_variant)
		var node_id := _layout_node_id_from_storage_key(key)
		if node_id.is_empty():
			continue
		var raw_value: Variant = config.get_value(_LAYOUT_SECTION, key, null)
		if raw_value is Array and raw_value.size() >= 2:
			_node_positions[node_id] = Vector2(
				_as_float(raw_value[0]),
				_as_float(raw_value[1])
			)


func _persist_visibility(node_id: String, visible_on_graph: bool) -> void:
	_node_visibility[node_id] = visible_on_graph
	if not persist_runtime_layout:
		return
	var config := ConfigFile.new()
	config.load(_LAYOUT_SAVE_PATH)
	config.set_value(
		_VISIBILITY_SECTION,
		_layout_storage_key(node_id),
		visible_on_graph
	)
	config.save(_LAYOUT_SAVE_PATH)


func _layout_storage_key(node_id: String) -> String:
	var scope_key := String(runtime_snapshot.get("scope_key", "global"))
	if scope_key == "global":
		return node_id
	return "scope=%s|%s" % [scope_key, node_id]


func _layout_node_id_from_storage_key(storage_key: String) -> String:
	var scope_key := String(runtime_snapshot.get("scope_key", "global"))
	if scope_key == "global":
		return "" if storage_key.begins_with("scope=") else storage_key
	var prefix := "scope=%s|" % scope_key
	return storage_key.trim_prefix(prefix) if storage_key.begins_with(prefix) else ""


func _capture_sidebar_group_state() -> void:
	if _sidebar_tree == null:
		return
	var root := _sidebar_tree.get_root()
	if root == null:
		return
	_capture_sidebar_group_state_recursive(root)


func _capture_sidebar_group_state_recursive(item: TreeItem) -> void:
	var child := item.get_first_child()
	while child != null:
		var metadata_variant: Variant = child.get_metadata(_sidebar_column_index(_COLUMN_NAME))
		if metadata_variant is Dictionary:
			var metadata: Dictionary = metadata_variant
			if str(metadata.get("kind", "")) == "group":
				var group_key := str(metadata.get("group_key", ""))
				if not group_key.is_empty():
					_group_collapsed["group:%s" % group_key] = child.collapsed
		_capture_sidebar_group_state_recursive(child)
		child = child.get_next()


func _on_sidebar_button_clicked(item: TreeItem, _column: int, id: int, _mouse_button_index: int) -> void:
	if id != _SIDEBAR_BUTTON_ID_VISIBILITY or item == null:
		return
	var metadata_variant: Variant = item.get_metadata(_sidebar_column_index(_COLUMN_VISIBILITY))
	if not (metadata_variant is Dictionary):
		return
	var metadata: Dictionary = metadata_variant
	match str(metadata.get("kind", "")):
		"state":
			var state_path := str(metadata.get("path", ""))
			var node_id := "%s%s" % [_STATE_NODE_PREFIX, state_path]
			_persist_visibility(node_id, not _as_bool(_node_visibility.get(node_id, false)))
		"transition":
			var transition_id := str(metadata.get("transition_id", ""))
			var transition_node_id := "%s%s" % [_TRANSITION_NODE_PREFIX, transition_id]
			_persist_visibility(transition_node_id, not _as_bool(_node_visibility.get(transition_node_id, true)))
	_rebuild_from_current_state()


func _on_sidebar_item_activated() -> void:
	if _sidebar_tree == null:
		return
	var selected := _sidebar_tree.get_selected()
	if selected == null:
		return
	var selected_column := _logical_sidebar_column(_sidebar_tree.get_selected_column())
	var metadata_variant: Variant = selected.get_metadata(_sidebar_tree.get_selected_column())
	if not (metadata_variant is Dictionary):
		return
	var metadata: Dictionary = metadata_variant
	var kind := str(metadata.get("kind", ""))
	if selected_column == _COLUMN_NAME and (kind == "state" or kind == "transition"):
		_sidebar_rename_request_revision += 1
		_sidebar_rename_request = metadata.duplicate(true)
		if _sidebar_tree.has_method("edit_selected"):
			_sidebar_tree.call("edit_selected", true)
		return
	if kind != "state" or not [_COLUMN_VALUE, _COLUMN_DEFAULT, _COLUMN_RESOLVER].has(selected_column):
		return
	if _sidebar_tree.has_method("edit_selected"):
		_sidebar_tree.call("edit_selected", true)


func _on_sidebar_item_edited() -> void:
	if _sidebar_tree == null:
		return
	var edited_item := _sidebar_tree.get_edited()
	if edited_item == null:
		return
	var edited_column_physical := _sidebar_tree.get_edited_column()
	var edited_column := _logical_sidebar_column(edited_column_physical)
	if edited_column == _COLUMN_NAME:
		var name_metadata_variant: Variant = edited_item.get_metadata(edited_column_physical)
		if not (name_metadata_variant is Dictionary):
			return
		var name_metadata: Dictionary = name_metadata_variant
		match str(name_metadata.get("kind", "")):
			"state":
				_commit_state_leaf_rename(str(name_metadata.get("path", "")), edited_item.get_text(edited_column_physical))
			"transition":
				_commit_transition_display_name(int(name_metadata.get("transition_id", 0)), edited_item.get_text(edited_column_physical))
		return
	var metadata_variant: Variant = edited_item.get_metadata(edited_column_physical)
	if not (metadata_variant is Dictionary):
		return
	var metadata: Dictionary = metadata_variant
	if str(metadata.get("kind", "")) != "state":
		return
	var state_data: Dictionary = metadata.get("data", {})
	var state_path := str(metadata.get("path", ""))
	if state_path.is_empty():
		return
	match edited_column:
		_COLUMN_VALUE:
			var edited_value: Variant = _read_tree_item_value(edited_item, state_data, edited_column_physical)
			if _has_runtime_snapshot() and state_store != null and state_store.has_method("set_override"):
				state_store.call("set_override", state_path, edited_value)
			else:
				_commit_state_default_value(state_path, edited_value)
		_COLUMN_DEFAULT:
			_commit_state_default_value(state_path, _read_tree_item_value(edited_item, state_data, edited_column_physical))
		_COLUMN_RESOLVER:
			var supported_resolvers: Array = _supported_resolvers_for_state(state_data)
			var resolver_index := clampi(int(round(edited_item.get_range(edited_column_physical))), 0, maxi(0, supported_resolvers.size() - 1))
			if not supported_resolvers.is_empty():
				_commit_state_resolver(state_path, int(supported_resolvers[resolver_index]))


func _on_sidebar_gui_input(event: InputEvent) -> void:
	if !_is_graph_input_enabled():
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	var item := _sidebar_tree.get_item_at_position(mouse_event.position)
	if item == null:
		return
	if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.double_click:
		_focus_sidebar_item(item, _sidebar_tree.get_column_at_position(mouse_event.position))
		return
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var metadata_variant: Variant = item.get_metadata(_sidebar_column_index(_COLUMN_NAME))
	if not (metadata_variant is Dictionary):
		return
	_sidebar_context_metadata = metadata_variant.duplicate(true)
	var metadata: Dictionary = _sidebar_context_metadata
	var is_state := str(metadata.get("kind", "")) == "state"
	_sidebar_context_menu.set_item_disabled(
		_sidebar_context_menu.get_item_index(_SIDEBAR_CONTEXT_REMOVE_OVERRIDE),
		not is_state or not _state_is_overridden(metadata.get("data", {}))
	)
	_sidebar_context_menu.set_item_disabled(
		_sidebar_context_menu.get_item_index(_SIDEBAR_CONTEXT_SET_DEFAULT_FROM_RESOLVED),
		not is_state or not _has_runtime_snapshot()
	)
	_sidebar_context_menu.position = DisplayServer.mouse_get_position()
	_sidebar_context_menu.popup()


func _focus_sidebar_item(item: TreeItem, physical_column: int) -> bool:
	if item == null or _logical_sidebar_column(physical_column) != _COLUMN_NAME:
		return false
	var metadata_variant: Variant = item.get_metadata(physical_column)
	if not (metadata_variant is Dictionary):
		return false
	var metadata: Dictionary = metadata_variant
	match str(metadata.get("kind", "")):
		"state":
			return focus_node("%s%s" % [_STATE_NODE_PREFIX, str(metadata.get("path", ""))])
		"transition":
			return focus_node("%s%s" % [_TRANSITION_NODE_PREFIX, str(metadata.get("transition_id", ""))])
		_:
			return false


func _on_graph_node_gui_input(event: InputEvent, node_id: String) -> void:
	if !_is_graph_input_enabled():
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_node_context_node_id = node_id
			_node_context_menu.position = DisplayServer.mouse_get_position()
			_node_context_menu.popup()
			accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.double_click and mouse_event.pressed and mouse_event.position.y <= 46.0:
			_begin_inline_title_edit(node_id)
			accept_event()


func _on_transition_value_row_gui_input(event: InputEvent, target: Dictionary) -> void:
	if !_is_graph_input_enabled():
		return
	pass


func _on_inline_bool_toggled(pressed: bool, commit_callable: Callable) -> void:
	if commit_callable.is_valid():
		commit_callable.call(pressed)


func _on_inline_enum_selected(index: int, option: OptionButton, definition: StateVariableDefScript, commit_callable: Callable) -> void:
	if not commit_callable.is_valid() or definition == null:
		return
	if index < 0 or index >= definition.possible_values.size():
		return
	commit_callable.call(definition.possible_values[index])


func _on_inline_custom_resolution_submitted(_text: String, line_edit: LineEdit, commit_callable: Callable) -> void:
	if not commit_callable.is_valid():
		return
	var code := line_edit.text.strip_edges()
	if code.is_empty():
		return
	commit_callable.call(code if code.begins_with("=") else "=" + code)


func _on_inline_spinbox_value_changed(value: float, commit_callable: Callable, treat_as_int: bool) -> void:
	if commit_callable.is_valid():
		commit_callable.call(int(round(value)) if treat_as_int else value)


func _on_inline_vector2_value_changed(_value: float, x_editor: SpinBox, y_editor: SpinBox, commit_callable: Callable) -> void:
	if commit_callable.is_valid():
		commit_callable.call(Vector2(_as_float(x_editor.value), _as_float(y_editor.value)))


func _on_inline_vector3_value_changed(_value: float, x_editor: SpinBox, y_editor: SpinBox, z_editor: SpinBox, commit_callable: Callable) -> void:
	if commit_callable.is_valid():
		commit_callable.call(Vector3(_as_float(x_editor.value), _as_float(y_editor.value), _as_float(z_editor.value)))


func _on_inline_text_submitted(_text: String, line_edit: LineEdit, commit_callable: Callable) -> void:
	if commit_callable.is_valid():
		commit_callable.call(line_edit.text)


func _on_inline_text_focus_exited(line_edit: LineEdit, commit_callable: Callable) -> void:
	if commit_callable.is_valid():
		commit_callable.call(line_edit.text)


func _on_condition_operator_menu_id_pressed(id: int, transition_id: int, condition_index: int) -> void:
	_commit_transition_condition_operator(transition_id, condition_index, id)


func _on_transition_output_operation_selected(_index: int, transition_id: int, output_index: int, option_button: OptionButton) -> void:
	if option_button == null or option_button.selected < 0:
		return
	_commit_transition_output_operation(transition_id, output_index, option_button.get_item_id(option_button.selected))


func _on_sidebar_context_menu_id_pressed(id: int) -> void:
	if _sidebar_context_metadata.is_empty():
		return
	var kind := str(_sidebar_context_metadata.get("kind", ""))
	match id:
		_SIDEBAR_CONTEXT_REMOVE_OVERRIDE:
			if kind == "state":
				var state_path := str(_sidebar_context_metadata.get("path", ""))
				if state_store != null and state_store.has_method("clear_override"):
					state_store.call("clear_override", state_path)
		_SIDEBAR_CONTEXT_SET_DEFAULT_FROM_RESOLVED:
			if kind == "state":
				var state_path := str(_sidebar_context_metadata.get("path", ""))
				var state_data: Dictionary = _sidebar_context_metadata.get("data", {})
				_commit_state_default_value(state_path, state_data.get("resolved_value", state_data.get("default_value", null)))
		_SIDEBAR_CONTEXT_HIDE:
			if kind == "state":
				_persist_visibility("%s%s" % [_STATE_NODE_PREFIX, str(_sidebar_context_metadata.get("path", ""))], false)
				_rebuild_from_current_state()
			elif kind == "transition":
				_persist_visibility("%s%s" % [_TRANSITION_NODE_PREFIX, str(_sidebar_context_metadata.get("transition_id", ""))], false)
				_rebuild_from_current_state()
		_SIDEBAR_CONTEXT_SHOW_RELEVANT:
			if kind == "state":
				show_relevant("%s%s" % [_STATE_NODE_PREFIX, str(_sidebar_context_metadata.get("path", ""))])
			elif kind == "transition":
				show_relevant("%s%s" % [_TRANSITION_NODE_PREFIX, str(_sidebar_context_metadata.get("transition_id", ""))])
		_SIDEBAR_CONTEXT_DELETE:
			if kind == "state":
				_delete_node_by_id("%s%s" % [_STATE_NODE_PREFIX, str(_sidebar_context_metadata.get("path", ""))])
			elif kind == "transition":
				_delete_node_by_id("%s%s" % [_TRANSITION_NODE_PREFIX, str(_sidebar_context_metadata.get("transition_id", ""))])
	_sidebar_context_metadata.clear()


func _on_canvas_context_menu_id_pressed(id: int) -> void:
	match id:
		_CANVAS_CREATE_STATE:
			_create_new_state_at(_canvas_context_graph_position)
		_CANVAS_CREATE_TRANSITION:
			_create_new_transition_at(_canvas_context_graph_position)


func _on_column_menu_id_pressed(id: int) -> void:
	match id:
		_COLUMN_MENU_DEFAULT:
			_sidebar_show_default_column = not _sidebar_show_default_column
		_COLUMN_MENU_RESOLVER:
			_sidebar_show_resolver_column = not _sidebar_show_resolver_column
	_apply_sidebar_column_visibility()
	_rebuild_from_current_state()


func _on_node_context_menu_id_pressed(id: int) -> void:
	if _node_context_node_id.is_empty():
		return
	match id:
		_NODE_SHOW_RELEVANT:
			show_relevant(_node_context_node_id)
		_NODE_HIDE:
			_persist_visibility(_node_context_node_id, false)
			_rebuild_from_current_state()
		_NODE_DELETE:
			_delete_node_by_id(_node_context_node_id)
	_node_context_node_id = ""


func _begin_inline_title_edit(node_id: String) -> void:
	var node := _nodes_by_id.get(node_id) as GraphNode
	if node == null or not node.has_method("get_titlebar_hbox"):
		return
	var titlebar_hbox := node.call("get_titlebar_hbox") as HBoxContainer
	if titlebar_hbox == null:
		return
	var line_edit := titlebar_hbox.get_node_or_null("InlineTitleEdit") as LineEdit
	if line_edit == null:
		line_edit = LineEdit.new()
		line_edit.name = "InlineTitleEdit"
		line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_edit.text_submitted.connect(_on_inline_title_submitted.bind(node_id, line_edit))
		line_edit.focus_exited.connect(_on_inline_title_focus_exited.bind(node_id, line_edit))
		titlebar_hbox.add_child(line_edit)
	for child in titlebar_hbox.get_children():
		if child is Label:
			child.visible = false
	line_edit.visible = true
	line_edit.text = _inline_title_text_for_node(node_id)
	line_edit.grab_focus()
	line_edit.select_all()


func _inline_title_text_for_node(node_id: String) -> String:
	if node_id.begins_with(_STATE_NODE_PREFIX):
		return node_id.trim_prefix(_STATE_NODE_PREFIX)
	if node_id.begins_with(_TRANSITION_NODE_PREFIX):
		var metadata := _metadata_for_node_id(node_id)
		var data_variant: Variant = metadata.get("data", {})
		if data_variant is Dictionary:
			var display_name := str((data_variant as Dictionary).get("display_name", ""))
			if not display_name.is_empty():
				return display_name
		return "Transition %d" % int(node_id.trim_prefix(_TRANSITION_NODE_PREFIX))
	return ""


func _on_inline_title_submitted(_text: String, node_id: String, line_edit: LineEdit) -> void:
	_finish_inline_title_edit(node_id, line_edit, true)


func _on_inline_title_focus_exited(node_id: String, line_edit: LineEdit) -> void:
	_finish_inline_title_edit(node_id, line_edit, true)


func _finish_inline_title_edit(node_id: String, line_edit: LineEdit, commit_change: bool) -> void:
	var node := _nodes_by_id.get(node_id) as GraphNode
	if line_edit == null:
		return
	if commit_change:
		if node_id.begins_with(_STATE_NODE_PREFIX):
			_commit_state_full_path_rename(node_id.trim_prefix(_STATE_NODE_PREFIX), line_edit.text)
		elif node_id.begins_with(_TRANSITION_NODE_PREFIX):
			_commit_transition_display_name(int(node_id.trim_prefix(_TRANSITION_NODE_PREFIX)), line_edit.text)
	line_edit.visible = false
	if node != null and node.has_method("get_titlebar_hbox"):
		var titlebar_hbox := node.call("get_titlebar_hbox") as HBoxContainer
		if titlebar_hbox != null:
			for child in titlebar_hbox.get_children():
				if child is Label:
					child.visible = true


func _show_override_editor(state_path: String, state_data_variant: Variant) -> void:
	if state_store == null or not state_store.has_method("set_override"):
		return
	var state_data: Dictionary = state_data_variant if state_data_variant is Dictionary else {}
	_override_target_state_path = state_path
	for child in _override_editor_host.get_children():
		child.queue_free()
	_override_editor = null
	var label := Label.new()
	label.text = state_path
	_override_editor_host.add_child(label)
	_override_editor = _build_override_editor(state_data)
	if _override_editor != null:
		_override_editor_host.add_child(_override_editor)
	_override_dialog.popup_centered()


func _show_rename_dialog(metadata: Dictionary) -> void:
	if _rename_dialog == null:
		return
	_rename_target = metadata.duplicate(true)
	var kind := str(metadata.get("kind", ""))
	_rename_path_edit.editable = kind == "state"
	_rename_path_edit.visible = kind == "state"
	_rename_leaf_edit.visible = true
	_rename_display_name_edit.visible = kind == "transition"
	if kind == "state":
		var state_path := str(metadata.get("path", ""))
		_rename_leaf_edit.text = state_path.get_file()
		_rename_path_edit.text = state_path
		_rename_display_name_edit.text = ""
		_rename_dialog.title = "Rename State"
	elif kind == "transition":
		var transition_id := int(metadata.get("transition_id", 0))
		var display_name := ""
		var data_variant: Variant = metadata.get("data", {})
		if data_variant is Dictionary:
			display_name = str((data_variant as Dictionary).get("display_name", ""))
		_rename_leaf_edit.text = display_name if not display_name.is_empty() else "Transition %d" % transition_id
		_rename_display_name_edit.text = display_name
		_rename_dialog.title = "Rename Transition"
	_rename_dialog.popup_centered()
	_rename_leaf_edit.grab_focus()
	_rename_leaf_edit.select_all()


func _apply_rename_dialog() -> void:
	if database == null or _rename_target.is_empty():
		return
	var kind := str(_rename_target.get("kind", ""))
	if kind == "state":
		_commit_state_full_path_rename(str(_rename_target.get("path", "")), _rename_path_edit.text)
	elif kind == "transition":
		_commit_transition_display_name(int(_rename_target.get("transition_id", 0)), _rename_display_name_edit.text)


func _commit_state_leaf_rename(old_path: String, new_leaf: String) -> void:
	var trimmed_leaf := new_leaf.strip_edges().to_lower().replace(" ", "_")
	if trimmed_leaf.is_empty():
		return
	var parent_path := old_path.get_base_dir()
	var new_path := trimmed_leaf if parent_path.is_empty() else "%s/%s" % [parent_path, trimmed_leaf]
	_commit_state_full_path_rename(old_path, new_path)


func _commit_state_full_path_rename(old_path: String, new_path: String) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var rename_plan := StateVariableRenameScript.plan(states, transitions, StateBindingIndex.scan(), old_path, new_path)
	if not bool(rename_plan.get("ok", false)):
		_show_rename_failure(str(rename_plan.get("diagnostic", "Unable to rename state.")))
		return
	if str(rename_plan.get("reason", "")) == "no_op":
		return
	if not StateVariableRenameScript.apply(states, transitions, rename_plan):
		_show_rename_failure("Unable to apply the state rename.")
		return
	_migrate_state_graph_identity(str(rename_plan.get("old_path", "")), str(rename_plan.get("new_path", "")))
	_commit_database_snapshot_change("Rename State", states, transitions, rename_plan.get("binding_edits", {}))


func _show_rename_failure(diagnostic: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Rename State"
	dialog.dialog_text = diagnostic
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)


func _migrate_state_graph_identity(old_path: String, new_path: String) -> void:
	var old_id := "%s%s" % [_STATE_NODE_PREFIX, old_path]
	var new_id := "%s%s" % [_STATE_NODE_PREFIX, new_path]
	for map in [_node_positions, _node_visibility, _group_collapsed]:
		if map.has(old_id):
			map[new_id] = map[old_id]
			map.erase(old_id)
	if persist_runtime_layout:
		var config := ConfigFile.new()
		if config.load(_LAYOUT_SAVE_PATH) == OK:
			for section in [_LAYOUT_SECTION, _VISIBILITY_SECTION]:
				if config.has_section_key(section, old_id):
					config.set_value(section, new_id, config.get_value(section, old_id))
					config.erase_section_key(section, old_id)
			config.save(_LAYOUT_SAVE_PATH)
	var state_values := ConfigFile.new()
	if state_values.load(_STATE_VALUES_SAVE_PATH) == OK:
		for section in ["bases", "overrides"]:
			if state_values.has_section_key(section, old_path):
				state_values.set_value(section, new_path, state_values.get_value(section, old_path))
				state_values.erase_section_key(section, old_path)
		state_values.save(_STATE_VALUES_SAVE_PATH)


func _commit_transition_display_name(transition_id: int, display_name: String) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var transition_def := _find_transition_def_in_array(transitions, transition_id)
	if transition_def == null:
		return
	transition_def.display_name = display_name.strip_edges()
	_commit_database_snapshot_change("Rename Transition", states, transitions)


func _commit_transition_condition_value(transition_id: int, condition_index: int, value: Variant) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var transition_def := _find_transition_def_in_array(transitions, transition_id)
	if transition_def == null or condition_index < 0 or condition_index >= transition_def.conditions.size():
		return
	var condition := transition_def.conditions[condition_index] as StateTransitionConditionDefScript
	if condition == null:
		return
	var state_def := _find_state_def_in_array(states, String(condition.get_normalized_target_state_path()))
	if state_def == null:
		return
	condition.set_expected_value(state_def, value)
	_commit_database_snapshot_change("Edit Transition Condition", states, transitions)


func _commit_transition_condition_operator(transition_id: int, condition_index: int, operator_value: int) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var transition_def := _find_transition_def_in_array(transitions, transition_id)
	if transition_def == null or condition_index < 0 or condition_index >= transition_def.conditions.size():
		return
	var condition := transition_def.conditions[condition_index] as StateTransitionConditionDefScript
	if condition == null:
		return
	var state_def := _find_state_def_in_array(states, String(condition.get_normalized_target_state_path()))
	if state_def == null:
		return
	condition.operator = operator_value
	var supported_operators := condition.get_supported_operators(state_def)
	if not supported_operators.has(condition.operator):
		condition.operator = supported_operators[0] if not supported_operators.is_empty() else int(StateTransitionConditionDefScript.Operator.EQUALS)
	condition.set_expected_value(state_def, condition.get_expected_value(state_def))
	_commit_database_snapshot_change("Edit Transition Condition Operator", states, transitions)


func _commit_transition_output_value(transition_id: int, output_index: int, value: Variant) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var transition_def := _find_transition_def_in_array(transitions, transition_id)
	if transition_def == null or output_index < 0 or output_index >= transition_def.outputs.size():
		return
	var output_def := transition_def.outputs[output_index] as StateTransitionOutputDefScript
	if output_def == null:
		return
	var state_def := _find_state_def_in_array(states, String(output_def.get_normalized_target_state_path()))
	if state_def == null:
		return
	output_def.set_target_value(state_def, value)
	_commit_database_snapshot_change("Edit Transition Output", states, transitions)


func _commit_transition_output_operation(transition_id: int, output_index: int, operation_value: int) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var transition_def := _find_transition_def_in_array(transitions, transition_id)
	if transition_def == null or output_index < 0 or output_index >= transition_def.outputs.size():
		return
	var output_def := transition_def.outputs[output_index] as StateTransitionOutputDefScript
	if output_def == null:
		return
	var state_def := _find_state_def_in_array(states, String(output_def.get_normalized_target_state_path()))
	if state_def == null:
		return
	output_def.operation = operation_value
	var supported_operations := output_def.get_supported_operations(state_def)
	if not supported_operations.has(output_def.operation):
		output_def.operation = supported_operations[0] if not supported_operations.is_empty() else int(StateTransitionOutputDefScript.Operation.SET)
	_commit_database_snapshot_change("Edit Transition Output Operation", states, transitions)


func _show_transition_value_editor(target: Dictionary) -> void:
	if database == null or _value_dialog == null:
		return
	_value_edit_target = target.duplicate(true)
	for child in _value_editor_host.get_children():
		_value_editor_host.remove_child(child)
		child.free()
	_value_editor = null
	var state_def: StateVariableDefScript = null
	var current_value: Variant = null
	match str(target.get("type", "")):
		"condition":
			var transition = database.get_transition_by_id(int(target.get("transition_id", 0)))
			var condition_index := int(target.get("condition_index", -1))
			if transition == null or condition_index < 0 or condition_index >= transition.conditions.size():
				return
			var condition = transition.conditions[condition_index] as StateTransitionConditionDefScript
			if condition == null:
				return
			state_def = database.get_state_definition_by_path(String(condition.get_normalized_target_state_path()))
			current_value = condition.get_expected_value(state_def)
			_value_dialog.title = "Edit Condition Value"
		"output":
			var transition = database.get_transition_by_id(int(target.get("transition_id", 0)))
			var output_index := int(target.get("output_index", -1))
			if transition == null or output_index < 0 or output_index >= transition.outputs.size():
				return
			var output_def = transition.outputs[output_index] as StateTransitionOutputDefScript
			if output_def == null:
				return
			state_def = database.get_state_definition_by_path(String(output_def.get_normalized_target_state_path()))
			current_value = output_def.get_target_value(state_def)
			_value_dialog.title = "Edit Output Value"
	if state_def == null:
		return
	var fake_state := _build_state_snapshot_for_editor(state_def, current_value)
	var label := Label.new()
	label.text = String(state_def.get_normalized_path())
	_value_editor_host.add_child(label)
	_value_editor = _build_override_editor(fake_state)
	if _value_editor != null:
		_value_editor_host.add_child(_value_editor)
	_value_dialog.popup_centered()


func _apply_value_dialog() -> void:
	if database == null or _value_editor == null or _value_edit_target.is_empty():
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var transition_def := _find_transition_def_in_array(transitions, int(_value_edit_target.get("transition_id", 0)))
	if transition_def == null:
		return
	match str(_value_edit_target.get("type", "")):
		"condition":
			var condition_index := int(_value_edit_target.get("condition_index", -1))
			if condition_index < 0 or condition_index >= transition_def.conditions.size():
				return
			var condition = transition_def.conditions[condition_index] as StateTransitionConditionDefScript
			if condition == null:
				return
			var state_def := _find_state_def_in_array(states, String(condition.get_normalized_target_state_path()))
			if state_def == null:
				return
			condition.set_expected_value(state_def, _read_override_editor_value(_value_editor))
			_commit_database_snapshot_change("Edit Transition Condition", states, transitions)
		"output":
			var output_index := int(_value_edit_target.get("output_index", -1))
			if output_index < 0 or output_index >= transition_def.outputs.size():
				return
			var output_def := transition_def.outputs[output_index] as StateTransitionOutputDefScript
			if output_def == null:
				return
			var state_def := _find_state_def_in_array(states, String(output_def.get_normalized_target_state_path()))
			if state_def == null:
				return
			output_def.set_target_value(state_def, _read_override_editor_value(_value_editor))
			_commit_database_snapshot_change("Edit Transition Output", states, transitions)


func _create_new_state_at(graph_position: Vector2) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var state_def := StateVariableDefScript.new()
	state_def.path = StringName(_generate_unique_state_path(states))
	state_def.value_type = StateVariableDefScript.ValueType.STRING
	state_def.resolver = StateVariableDefScript.Resolver.ORDERED
	state_def.default_value = ""
	state_def.graph_position = graph_position
	states.append(state_def)
	_persist_visibility("%s%s" % [_STATE_NODE_PREFIX, String(state_def.get_normalized_path())], true)
	_pending_inline_title_node_id = "%s%s" % [_STATE_NODE_PREFIX, String(state_def.get_normalized_path())]
	_commit_database_snapshot_change("Create State", states, transitions)
	call_deferred("_begin_pending_inline_title_edit")


func _create_new_transition_at(graph_position: Vector2) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var transition_def := StateTransitionDefScript.new()
	transition_def.transition_id = _next_transition_id_from_snapshot(transitions)
	transition_def.display_name = ""
	transition_def.graph_position = graph_position
	transitions.append(transition_def)
	_persist_visibility("%s%d" % [_TRANSITION_NODE_PREFIX, transition_def.transition_id], true)
	_pending_inline_title_node_id = "%s%d" % [_TRANSITION_NODE_PREFIX, transition_def.transition_id]
	_commit_database_snapshot_change("Create Transition", states, transitions)
	call_deferred("_begin_pending_inline_title_edit")


func _begin_pending_inline_title_edit() -> void:
	if _pending_inline_title_node_id.is_empty():
		return
	var node_id := _pending_inline_title_node_id
	_pending_inline_title_node_id = ""
	if _nodes_by_id.has(node_id):
		_begin_inline_title_edit(node_id)


func _database_state_definition(state_path: String) -> StateVariableDefScript:
	if database == null:
		return null
	return database.get_state_definition_by_path(state_path)


func _has_runtime_snapshot() -> bool:
	return not runtime_snapshot.is_empty()


func _rebuild_value_editor_host(host: Control, editor: Control) -> void:
	if host == null:
		return
	_clear_container_children(host)
	if editor != null:
		host.add_child(editor)


func _claim_source_name(claim_snapshot: Dictionary) -> String:
	var code_key := str(claim_snapshot.get("code_key", ""))
	if not code_key.is_empty():
		return code_key
	return _transition_display_name(int(claim_snapshot.get("transition_id", 0)))


func _transition_display_name(transition_id: int) -> String:
	if transition_id <= 0:
		return ""
	for transition_variant in _get_effective_snapshot().get("transitions", []):
		var transition_data: Dictionary = transition_variant
		if int(transition_data.get("transition_id", 0)) != transition_id:
			continue
		var display_name := str(transition_data.get("display_name", ""))
		return display_name if not display_name.is_empty() else "Transition %d" % transition_id
	var transition_def: StateTransitionDefScript = database.get_transition_by_id(transition_id) if database != null else null
	if transition_def != null:
		var display_name := transition_def.get_display_name()
		return display_name if not display_name.is_empty() else "Transition %d" % transition_id
	return "Transition %d" % transition_id


func _find_state_snapshot(state_path: String) -> Dictionary:
	for state_variant in _get_effective_snapshot().get("states", []):
		var state_data: Dictionary = state_variant
		if str(state_data.get("path", "")) == state_path:
			return state_data
	return {}


func _focus_claim_name_editor(editor: LineEdit) -> void:
	if editor == null:
		return
	editor.grab_focus()
	editor.select_all()
	_pending_claim_edit_state_path = ""
	_pending_claim_edit_slot_id = ""


func _on_claim_name_submitted(_text: String, state_path: String, slot_id: String, editor: LineEdit) -> void:
	_commit_claim_code_key(state_path, slot_id, editor.text)


func _on_claim_name_focus_exited(state_path: String, slot_id: String, editor: LineEdit) -> void:
	_commit_claim_code_key(state_path, slot_id, editor.text)


func _commit_claim_code_key(state_path: String, slot_id: String, new_code_key: String) -> void:
	if database == null:
		return
	var normalized_key := new_code_key.strip_edges().to_lower().replace(" ", "_")
	if normalized_key.is_empty():
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var state_def := _find_state_def_in_array(states, state_path)
	if state_def == null:
		return
	var slot_def := state_def.get_claim_slot_by_id(StringName(slot_id))
	if slot_def == null or slot_def.get_normalized_transition_id() > 0:
		return
	slot_def.code_key = StringName(normalized_key)
	state_def.ensure_valid_configuration()
	_commit_database_snapshot_change("Rename Claim", states, transitions)


func _create_new_code_claim(state_path: String) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var state_def := _find_state_def_in_array(states, state_path)
	if state_def == null:
		return
	var slot_def := StateClaimSlotDefScript.new()
	var index := state_def.claim_slots.size() + 1
	var slot_id := StringName("claim_%d" % index)
	while state_def.get_claim_slot_by_id(slot_id) != null:
		index += 1
		slot_id = StringName("claim_%d" % index)
	slot_def.slot_id = slot_id
	slot_def.code_key = slot_id
	state_def.claim_slots.append(slot_def)
	state_def.ensure_valid_configuration()
	_pending_claim_edit_state_path = state_path
	_pending_claim_edit_slot_id = String(slot_def.get_normalized_slot_id())
	_commit_database_snapshot_change("Create Claim", states, transitions)


func _move_claim_slot(state_path: String, slot_id: String, direction: int) -> void:
	if database == null or direction == 0:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var state_def := _find_state_def_in_array(states, state_path)
	if state_def == null:
		return
	var current_index := -1
	for index in range(state_def.claim_slots.size()):
		var slot := state_def.claim_slots[index] as StateClaimSlotDefScript
		if slot != null and String(slot.get_normalized_slot_id()) == slot_id:
			current_index = index
			break
	if current_index < 0:
		return
	var new_index := clampi(current_index + direction, 0, state_def.claim_slots.size() - 1)
	if new_index == current_index:
		return
	var slot_def := state_def.claim_slots[current_index]
	state_def.claim_slots.remove_at(current_index)
	state_def.claim_slots.insert(new_index, slot_def)
	state_def.ensure_valid_configuration()
	_commit_database_snapshot_change("Reorder Claim", states, transitions)


func _move_claim_slot_to_slot(state_path: String, slot_id: String, target_slot_id: String, before: bool) -> void:
	if database == null or slot_id.is_empty() or target_slot_id.is_empty() or slot_id == target_slot_id:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var state_def := _find_state_def_in_array(states, state_path)
	if state_def == null:
		return
	var current_index := -1
	var target_index := -1
	for index in range(state_def.claim_slots.size()):
		var slot := state_def.claim_slots[index] as StateClaimSlotDefScript
		if slot == null:
			continue
		var normalized_slot_id := String(slot.get_normalized_slot_id())
		if normalized_slot_id == slot_id:
			current_index = index
		if normalized_slot_id == target_slot_id:
			target_index = index
	if current_index < 0 or target_index < 0:
		return
	var slot_def := state_def.claim_slots[current_index]
	state_def.claim_slots.remove_at(current_index)
	if current_index < target_index:
		target_index -= 1
	if not before:
		target_index += 1
	target_index = clampi(target_index, 0, state_def.claim_slots.size())
	state_def.claim_slots.insert(target_index, slot_def)
	state_def.ensure_valid_configuration()
	_commit_database_snapshot_change("Reorder Claim", states, transitions)


func _delete_claim_slot(state_path: String, slot_id: String) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var state_def := _find_state_def_in_array(states, state_path)
	if state_def == null:
		return
	state_def.claim_slots = state_def.claim_slots.filter(func(slot):
		return slot != null and String((slot as StateClaimSlotDefScript).get_normalized_slot_id()) != slot_id
	)
	for transition_variant in transitions:
		var transition_def := transition_variant as StateTransitionDefScript
		if transition_def == null:
			continue
		transition_def.outputs = transition_def.outputs.filter(func(output):
			if output == null:
				return false
			var output_def := output as StateTransitionOutputDefScript
			return not (
				String(output_def.get_normalized_target_state_path()) == state_path
				and String(output_def.get_normalized_target_claim_slot_id()) == slot_id
			)
		)
	_commit_database_snapshot_change("Delete Claim", states, transitions)


func _build_state_override_editor(state_path: String, state_data: Dictionary) -> Control:
	var state_def := _database_state_definition(state_path)
	if state_def == null:
		return null
	if not _has_runtime_snapshot():
		var placeholder := Label.new()
		placeholder.text = "none"
		placeholder.modulate = _STATE_IDLE_COLOR
		return placeholder
	var enabled := _as_bool(state_data.get("override_enabled", false))
	var value: Variant = state_data.get(
		"override_value",
		state_data.get("resolved_value", state_data.get("default_value", null))
	) if enabled else state_data.get("resolved_value", state_data.get("default_value", null))
	var editor := _build_inline_value_editor(
		state_def,
		value,
		Callable(self, "_commit_state_override_value").bind(state_path)
	)
	if editor == null:
		return null
	return editor


func _commit_state_override_value(state_path: String, value: Variant) -> void:
	if state_store != null and state_store.has_method("set_override"):
		state_store.call("set_override", state_path, value)


func _clear_state_override(state_path: String) -> void:
	if state_store != null and state_store.has_method("clear_override"):
		state_store.call("clear_override", state_path)


func _commit_state_default_value(state_path: String, value: Variant) -> void:
	if _commit_code_declared_default_value(state_path, value):
		return
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var state_def := _find_state_def_in_array(states, state_path)
	if state_def == null:
		return
	state_def.default_value = state_def.coerce_value(value)
	state_def.ensure_valid_configuration()
	_commit_database_snapshot_change("Edit State Default", states, transitions)


## Routes a generated entry's default edit to the resource property that owns it, and
## reports whether it handled the edit (PGO-226 / PGO-211 Q7).
##
## Per the Q7 ruling a code-declared entry is editable in the graph for its default value
## and node position only; path, value_type, resolver and claim_slots are code-owned and
## display-only. The default is the half that has to go somewhere, and it must never go
## into the monolithic `.tres` — the runtime database this view is shown is a composite
## that refuses to save anyway, so writing it there would be silently lost. [StateStore]
## owns the resource write-back, so the edit is handed to it whole.
func _commit_code_declared_default_value(state_path: String, value: Variant) -> bool:
	if state_store == null:
		return false
	if not state_store.has_method("is_code_declared") or not state_store.has_method("set_layer_value"):
		return false
	if not bool(state_store.call("is_code_declared", state_path)):
		return false
	state_store.call("set_layer_value", state_path, value, _STATE_STORE_DEFAULT_LAYER)
	return true


func _build_state_tags_editor(state_path: String, state_data: Dictionary) -> LineEdit:
	var editor := LineEdit.new()
	editor.text = ", ".join(PackedStringArray(state_data.get("tags", PackedStringArray())))
	editor.placeholder_text = "comma-separated tags"
	editor.tooltip_text = "Lifecycle tags used to query or reset related state."
	editor.text_submitted.connect(_commit_state_tags.bind(state_path))
	return editor


func _commit_state_tags(value: String, state_path: String) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var state_def := _find_state_def_in_array(states, state_path)
	if state_def == null:
		return
	state_def.tags.clear()
	for tag in value.split(",", false):
		state_def.tags.append(tag)
	state_def.ensure_valid_configuration()
	_commit_database_snapshot_change("Edit State Tags", states, transitions)


func _commit_state_resolver(state_path: String, resolver_value: int) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var state_def := _find_state_def_in_array(states, state_path)
	if state_def == null:
		return
	state_def.resolver = resolver_value
	state_def.ensure_valid_configuration()
	_commit_database_snapshot_change("Edit State Resolver", states, transitions)


func _commit_state_value_type(state_path: String, value_type: int) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	var state_def := _find_state_def_in_array(states, state_path)
	if state_def == null:
		return
	state_def.value_type = value_type
	if state_def.value_type == StateVariableDefScript.ValueType.ENUM and state_def.possible_values.is_empty():
		state_def.possible_values = [state_def.coerce_value(state_def.default_value)]
	if state_def.value_type == StateVariableDefScript.ValueType.LIST:
		state_def.default_value = []
	state_def.ensure_valid_configuration()
	_commit_database_snapshot_change("Edit State Type", states, transitions)


func _supported_resolvers_for_state(state_data: Dictionary) -> Array:
	var state_def := _database_state_definition(str(state_data.get("path", "")))
	if state_def != null:
		return state_def.get_supported_resolvers()
	var fallback := StateVariableDefScript.new()
	fallback.value_type = int(state_data.get("value_type", int(StateVariableDefScript.ValueType.STRING)))
	return fallback.get_supported_resolvers()


func _resolver_name_from_value(resolver_value: int) -> String:
	return StateVariableDefScript.Resolver.keys()[resolver_value].to_lower()


func _populate_resolver_option_button(option_button: OptionButton, state_data: Dictionary) -> void:
	if option_button == null:
		return
	option_button.clear()
	var supported_resolvers: Array = _supported_resolvers_for_state(state_data)
	var selected_index := 0
	for index in range(supported_resolvers.size()):
		var resolver_value := int(supported_resolvers[index])
		option_button.add_item(_resolver_name_from_value(resolver_value), resolver_value)
		if resolver_value == int(state_data.get("resolver", 0)):
			selected_index = index
	if option_button.item_count > 0:
		option_button.select(selected_index)


func _on_state_resolver_selected(_index: int, state_path: String, option_button: OptionButton) -> void:
	if option_button == null or option_button.selected < 0:
		return
	_commit_state_resolver(state_path, option_button.get_item_id(option_button.selected))


func _on_state_type_selected(_index: int, state_path: String, option_button: OptionButton) -> void:
	if option_button == null or option_button.selected < 0:
		return
	_commit_state_value_type(state_path, option_button.get_item_id(option_button.selected))


func _sync_state_titlebar_controls(node: GraphNode, state_data: Dictionary) -> void:
	if node == null or not node.has_method("get_titlebar_hbox"):
		return
	var titlebar_hbox := node.call("get_titlebar_hbox") as HBoxContainer
	if titlebar_hbox == null:
		return
	var type_button := titlebar_hbox.get_node_or_null("TypeButton") as OptionButton
	if type_button == null:
		type_button = OptionButton.new()
		type_button.name = "TypeButton"
		type_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		type_button.focus_mode = Control.FOCUS_CLICK
		type_button.item_selected.connect(_on_state_type_selected.bind(str(state_data.get("path", "")), type_button))
		titlebar_hbox.add_child(type_button)
	for child in titlebar_hbox.get_children():
		if child is Label:
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_button.clear()
	for value_type_index in range(StateVariableDefScript.ValueType.size()):
		type_button.add_item(StateVariableDefScript.ValueType.keys()[value_type_index].to_lower(), value_type_index)
	type_button.select(int(state_data.get("value_type", 0)))
	type_button.visible = not _compact_graph_mode


func _selected_node_ids() -> Array[String]:
	var selected: Array[String] = []
	for node_id_variant in _nodes_by_id.keys():
		var node_id := str(node_id_variant)
		var node := _nodes_by_id[node_id] as GraphNode
		if node != null and node.selected:
			selected.append(node_id)
	return selected


func _delete_node_by_id(node_id: String) -> void:
	if database == null:
		return
	var snapshot := _duplicate_database_arrays()
	var states: Array = snapshot.get("states", [])
	var transitions: Array = snapshot.get("transitions", [])
	if node_id.begins_with(_STATE_NODE_PREFIX):
		var state_path := node_id.trim_prefix(_STATE_NODE_PREFIX)
		for index in range(states.size() - 1, -1, -1):
			var state_def := states[index] as StateVariableDefScript
			if state_def != null and String(state_def.get_normalized_path()) == state_path:
				states.remove_at(index)
				break
		for transition_variant in transitions:
			var transition_def := transition_variant as StateTransitionDefScript
			if transition_def == null:
				continue
			transition_def.conditions = transition_def.conditions.filter(func(c): return c != null and String((c as StateTransitionConditionDefScript).get_normalized_target_state_path()) != state_path)
			transition_def.outputs = transition_def.outputs.filter(func(o): return o != null and String((o as StateTransitionOutputDefScript).get_normalized_target_state_path()) != state_path)
		_commit_database_snapshot_change("Delete State", states, transitions)
	elif node_id.begins_with(_TRANSITION_NODE_PREFIX):
		var transition_id := int(node_id.trim_prefix(_TRANSITION_NODE_PREFIX))
		for index in range(transitions.size() - 1, -1, -1):
			var transition_def := transitions[index] as StateTransitionDefScript
			if transition_def != null and transition_def.get_normalized_transition_id() == transition_id:
				transitions.remove_at(index)
				break
		for state_variant in states:
			var state_def := state_variant as StateVariableDefScript
			if state_def == null:
				continue
			state_def.claim_slots = state_def.claim_slots.filter(func(slot): return slot != null and (slot as StateClaimSlotDefScript).get_normalized_transition_id() != transition_id)
		_commit_database_snapshot_change("Delete Transition", states, transitions)


func _build_override_editor(state_data: Dictionary) -> Control:
	var value_type := int(state_data.get("value_type", int(StateVariableDefScript.ValueType.STRING)))
	var current_value: Variant = state_data.get("resolved_value", state_data.get("default_value", null))
	match value_type:
		StateVariableDefScript.ValueType.BOOL:
			var checkbox := CheckBox.new()
			checkbox.button_pressed = _as_bool(current_value)
			checkbox.text = "Enabled"
			return checkbox
		StateVariableDefScript.ValueType.INT:
			var int_editor := SpinBox.new()
			int_editor.allow_greater = true
			int_editor.allow_lesser = true
			int_editor.step = 1.0
			int_editor.value = _as_float(_as_int(current_value))
			return int_editor
		StateVariableDefScript.ValueType.FLOAT:
			var float_editor := SpinBox.new()
			float_editor.allow_greater = true
			float_editor.allow_lesser = true
			float_editor.step = 0.05
			float_editor.value = _as_float(current_value)
			return float_editor
		StateVariableDefScript.ValueType.ENUM:
			var enum_editor := OptionButton.new()
			var possible_values: Array = state_data.get("possible_values", [])
			var selected_index := 0
			for index in range(possible_values.size()):
				var option_value: Variant = possible_values[index]
				enum_editor.add_item(str(option_value), index)
				if option_value == current_value:
					selected_index = index
			if enum_editor.item_count > 0:
				enum_editor.select(selected_index)
			return enum_editor
		StateVariableDefScript.ValueType.LIST:
			var label := Label.new()
			label.text = _describe_state_value_for_tree(state_data, current_value)
			return label
		StateVariableDefScript.ValueType.VECTOR2:
			var box := HBoxContainer.new()
			var vector_value: Vector2 = current_value if current_value is Vector2 else Vector2.ZERO
			var x_editor := SpinBox.new()
			x_editor.allow_greater = true
			x_editor.allow_lesser = true
			x_editor.step = 0.05
			x_editor.value = vector_value.x
			var y_editor := SpinBox.new()
			y_editor.allow_greater = true
			y_editor.allow_lesser = true
			y_editor.step = 0.05
			y_editor.value = vector_value.y
			box.add_child(x_editor)
			box.add_child(y_editor)
			return box
		StateVariableDefScript.ValueType.VECTOR3:
			var vector3_box := HBoxContainer.new()
			var vector3_value: Vector3 = current_value if current_value is Vector3 else Vector3.ZERO
			for axis_value in [vector3_value.x, vector3_value.y, vector3_value.z]:
				var axis_editor := SpinBox.new()
				axis_editor.allow_greater = true
				axis_editor.allow_lesser = true
				axis_editor.step = 0.05
				axis_editor.value = float(axis_value)
				vector3_box.add_child(axis_editor)
			return vector3_box
		_:
			var line_edit := LineEdit.new()
			line_edit.text = str(current_value)
			return line_edit


func _read_tree_item_value(item: TreeItem, state_data: Dictionary, column: int) -> Variant:
	var value_type := int(state_data.get("value_type", int(StateVariableDefScript.ValueType.STRING)))
	match value_type:
		StateVariableDefScript.ValueType.BOOL:
			return item.is_checked(column)
		StateVariableDefScript.ValueType.ENUM:
			var possible_values: Array = state_data.get("possible_values", [])
			var selected_index := clampi(int(round(item.get_range(column))), 0, maxi(0, possible_values.size() - 1))
			return possible_values[selected_index] if not possible_values.is_empty() else ""
		StateVariableDefScript.ValueType.INT:
			return item.get_text(column).strip_edges().to_int()
		StateVariableDefScript.ValueType.FLOAT:
			return item.get_text(column).strip_edges().to_float()
		StateVariableDefScript.ValueType.LIST:
			return state_data.get("resolved_value", [])
		StateVariableDefScript.ValueType.VECTOR2:
			var parts := item.get_text(column).split(",", false)
			if parts.size() >= 2:
				return Vector2(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float())
			return Vector2.ZERO
		StateVariableDefScript.ValueType.VECTOR3:
			var vector3_parts := item.get_text(column).split(",", false)
			if vector3_parts.size() >= 3:
				return Vector3(
					vector3_parts[0].strip_edges().to_float(),
					vector3_parts[1].strip_edges().to_float(),
					vector3_parts[2].strip_edges().to_float()
				)
			return Vector3.ZERO
		_:
			return item.get_text(column)


func _apply_override_from_dialog() -> void:
	if _override_target_state_path.is_empty() or _override_editor == null:
		return
	var value: Variant = _read_override_editor_value(_override_editor)
	if state_store != null and state_store.has_method("set_override"):
		state_store.call("set_override", _override_target_state_path, value)
	_override_target_state_path = ""


func _read_override_editor_value(editor: Control) -> Variant:
	if editor is CheckBox:
		return (editor as CheckBox).button_pressed
	if editor is SpinBox:
		return (editor as SpinBox).value
	if editor is OptionButton:
		var option := editor as OptionButton
		return option.get_item_text(option.selected)
	if editor is LineEdit:
		return (editor as LineEdit).text
	if editor is HBoxContainer and editor.get_child_count() >= 3 and editor.get_child(0) is SpinBox and editor.get_child(1) is SpinBox and editor.get_child(2) is SpinBox:
		return Vector3(
			_as_float((editor.get_child(0) as SpinBox).value),
			_as_float((editor.get_child(1) as SpinBox).value),
			_as_float((editor.get_child(2) as SpinBox).value)
		)
	if editor is HBoxContainer and editor.get_child_count() >= 2 and editor.get_child(0) is SpinBox and editor.get_child(1) is SpinBox:
		var x_editor := editor.get_child(0) as SpinBox
		var y_editor := editor.get_child(1) as SpinBox
		return Vector2(_as_float(x_editor.value), _as_float(y_editor.value))
	return null


func _state_is_overridden(state_data_variant: Variant) -> bool:
	if not (state_data_variant is Dictionary):
		return false
	var state_data: Dictionary = state_data_variant
	return _as_bool(state_data.get("override_enabled", false))


func _make_eye_icon(visible_on_graph: bool) -> Texture2D:
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var stroke := Color(0.9, 0.9, 0.95, 1.0)
	var iris := Color(0.35, 0.55, 1.0, 1.0) if visible_on_graph else Color(0.45, 0.45, 0.48, 1.0)
	for y in range(24):
		for x in range(24):
			var nx := (_as_float(x) - 11.5) / 9.5
			var ny := (_as_float(y) - 11.5) / 6.0
			var ellipse := (nx * nx) + (ny * ny)
			if ellipse >= 0.8 and ellipse <= 1.15:
				image.set_pixel(x, y, stroke)
			var iris_dx := _as_float(x) - 11.5
			var iris_dy := _as_float(y) - 11.5
			if (iris_dx * iris_dx) + (iris_dy * iris_dy) <= 14.0:
				image.set_pixel(x, y, iris)
	if not visible_on_graph:
		for slash_index in range(4, 20):
			var slash_y := 23 - slash_index
			if slash_y >= 0 and slash_y < 24:
				image.set_pixel(slash_index, slash_y, Color(1.0, 0.45, 0.45, 1.0))
				if slash_y + 1 < 24:
					image.set_pixel(slash_index, slash_y + 1, Color(1.0, 0.45, 0.45, 0.85))
	return ImageTexture.create_from_image(image)
