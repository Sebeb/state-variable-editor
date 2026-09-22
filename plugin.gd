@tool
extends EditorPlugin

const REQUIRED_HOST_PATHS := [
	"res://systems/state/state_variable_database.gd",
	"res://systems/state/state_variable_baker.gd",
	"res://systems/state/state_claim_slot_def.gd",
	"res://systems/state/state_transition_condition_def.gd",
	"res://systems/state/state_transition_def.gd",
	"res://systems/state/state_transition_output_def.gd",
	"res://systems/state/state_variable_def.gd",
	"res://systems/state/state_variable_rename.gd",
	"res://systems/state/entity_state_machine_template.gd",
	"res://systems/pills/pill_activation_binding_index.gd",
]

var _state_variable_baker_script: GDScript = null

## Cross-addon lookup groups. Other addons (e.g. pill_editor) have no direct
## reference to this plugin, so they find the live dock/plugin instance via
## `get_tree().get_first_node_in_group(...)` instead, matching the group
## convention already used for gameplay singletons elsewhere in this repo.
const DOCK_VIEW_GROUP := &"state_graph_dock_view"
const PLUGIN_GROUP := &"state_graph_editor_plugin"

var _inspector_plugin: EditorInspectorPlugin = null
var _debugger_plugin: EditorDebuggerPlugin = null
var _dock_view: Control = null
var _was_playing := false
var _bottom_panel_button: Button = null
var _graph_subscription_active := false


func _enter_tree() -> void:
	var missing_paths := _missing_host_paths()
	if not missing_paths.is_empty():
		print("State Variable Editor inactive; missing host requirements: %s" % ", ".join(missing_paths))
		return

	var inspector_plugin_script: GDScript = load(
		"res://addons/state_variable_editor/state_variable_inspector_plugin.gd"
	)
	var state_graph_debugger_plugin_script: GDScript = load(
		"res://addons/state_variable_editor/state_graph_debugger_plugin.gd"
	)
	var state_graph_view_scene: PackedScene = load(
		"res://addons/state_variable_editor/state_graph_view.tscn"
	)
	var state_variable_database_script: GDScript = load(
		"res://systems/state/state_variable_database.gd"
	)
	_state_variable_baker_script = load("res://systems/state/state_variable_baker.gd")

	_inspector_plugin = inspector_plugin_script.new()
	_inspector_plugin.undo_redo_ref = get_undo_redo()
	add_inspector_plugin(_inspector_plugin)

	_dock_view = state_graph_view_scene.instantiate()
	if _dock_view.has_method("set_presentation_mode"):
		_dock_view.call("set_presentation_mode", "shown")
	if _dock_view.has_method("set_undo_redo"):
		_dock_view.call("set_undo_redo", get_undo_redo())
	var database = state_variable_database_script.load_default_database()
	if _dock_view.has_method("set_database"):
		_dock_view.call("set_database", database)
	_bottom_panel_button = add_control_to_bottom_panel(_dock_view, "State Graph")
	_dock_view.add_to_group(DOCK_VIEW_GROUP)
	add_to_group(PLUGIN_GROUP)
	queue_save_layout()

	_debugger_plugin = state_graph_debugger_plugin_script.new()
	if _debugger_plugin.has_method("set_target_view"):
		_debugger_plugin.call("set_target_view", _dock_view)
	add_debugger_plugin(_debugger_plugin)
	set_process(true)


func _missing_host_paths() -> PackedStringArray:
	var missing := PackedStringArray()
	for path in REQUIRED_HOST_PATHS:
		if not ResourceLoader.exists(path):
			missing.append(path)
	return missing


func _exit_tree() -> void:
	if _debugger_plugin != null:
		if _debugger_plugin.has_method("set_subscribed"):
			_debugger_plugin.call("set_subscribed", false)
		remove_debugger_plugin(_debugger_plugin)
		_debugger_plugin = null
	if _dock_view != null:
		remove_control_from_bottom_panel(_dock_view)
		_dock_view.queue_free()
		_dock_view = null
	_bottom_panel_button = null
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
	_state_variable_baker_script = null
	set_process(false)


## Public bridge for other addons (e.g. pill_editor's "View State" button):
## reveals the bottom panel and centers the graph on the given node id
## (see StateGraphView.state_node_id / focus_node / show_relevant).
func reveal_and_focus_node(node_id: String) -> bool:
	if _dock_view == null:
		return false
	make_bottom_panel_item_visible(_dock_view)
	if not _dock_view.has_method("show_relevant"):
		return false
	var shown := bool(_dock_view.call("show_relevant", node_id))
	if shown and _dock_view.has_method("focus_node"):
		_dock_view.call("focus_node", node_id)
	return shown


## Rebakes the code-declared state variables whenever the editor saves (PGO-225).
##
## `_save_external_data` is the editor's hook for data an addon owns outside the scene
## being saved, which is exactly what the bake is: a generated file derived from resource
## properties. Hooking here rather than on a timer means editing a declared property and
## saving is the whole workflow, and it keeps generation at editor time — a shipped build
## never scans for declarations, so a stale bake is a stale shipped default.
##
## Silent when nothing changed; [StateVariableBaker] compares the rendered source before
## writing, so an unrelated save produces no diff.
func _save_external_data() -> void:
	if _state_variable_baker_script == null:
		return
	var result: Dictionary = _state_variable_baker_script.bake()
	if not bool(result.get("ok", false)):
		push_error("State-variable bake failed: %s" % str(result.get("errors", [])))
		return
	if bool(result.get("changed", false)):
		print("Baked %d code-declared state variable(s) into %s." % [
			int(result.get("count", 0)), str(result.get("path", "")),
		])
		var filesystem := get_editor_interface().get_resource_filesystem()
		if filesystem != null:
			filesystem.scan()


func _process(_delta: float) -> void:
	var editor_interface := get_editor_interface()
	if editor_interface == null:
		return
	var is_playing := editor_interface.is_playing_scene()
	if _was_playing and not is_playing and _dock_view != null and _dock_view.has_method("set_runtime_snapshot"):
		_dock_view.call("set_runtime_snapshot", {})
	_was_playing = is_playing
	var should_subscribe := is_playing and _dock_view != null and _dock_view.is_visible_in_tree()
	if should_subscribe != _graph_subscription_active:
		_graph_subscription_active = should_subscribe
		if _debugger_plugin != null and _debugger_plugin.has_method("set_subscribed"):
			_debugger_plugin.call("set_subscribed", should_subscribe)
