@tool
extends EditorPlugin

const InspectorPluginScript = preload("state_variable_inspector_plugin.gd")
const StateGraphDebuggerPluginScript = preload("state_graph_debugger_plugin.gd")
const StateGraphViewScene = preload("state_graph_view.tscn")
const StateVariableDatabaseScript = preload("runtime/state_variable_database.gd")
const StateVariableBakerScript = preload("runtime/state_variable_baker.gd")

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
	_inspector_plugin = InspectorPluginScript.new()
	_inspector_plugin.undo_redo_ref = get_undo_redo()
	add_inspector_plugin(_inspector_plugin)

	_dock_view = StateGraphViewScene.instantiate()
	if _dock_view.has_method("set_presentation_mode"):
		_dock_view.call("set_presentation_mode", "shown")
	if _dock_view.has_method("set_undo_redo"):
		_dock_view.call("set_undo_redo", get_undo_redo())
	var database := StateVariableDatabaseScript.load_default_database()
	if _dock_view.has_method("set_database"):
		_dock_view.call("set_database", database)
	_bottom_panel_button = add_control_to_bottom_panel(_dock_view, "State Graph")
	_dock_view.add_to_group(DOCK_VIEW_GROUP)
	add_to_group(PLUGIN_GROUP)
	queue_save_layout()

	_debugger_plugin = StateGraphDebuggerPluginScript.new()
	if _debugger_plugin.has_method("set_target_view"):
		_debugger_plugin.call("set_target_view", _dock_view)
	add_debugger_plugin(_debugger_plugin)
	set_process(true)


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
	var result := StateVariableBakerScript.bake()
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
