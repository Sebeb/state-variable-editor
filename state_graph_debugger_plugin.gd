@tool
extends EditorDebuggerPlugin

var _target_view: Control = null
var _subscription_requested := false
var _subscribed_session_ids: Dictionary = {}


func set_target_view(view: Control) -> void:
	if _target_view != null and _target_view.has_signal("runtime_resync_requested"):
		if _target_view.runtime_resync_requested.is_connected(_request_all_snapshots):
			_target_view.runtime_resync_requested.disconnect(_request_all_snapshots)
	if _target_view != null and _target_view.has_signal("runtime_scope_selected"):
		if _target_view.runtime_scope_selected.is_connected(_select_scope_for_all_sessions):
			_target_view.runtime_scope_selected.disconnect(_select_scope_for_all_sessions)
	_target_view = view
	if _target_view != null and _target_view.has_signal("runtime_resync_requested"):
		if not _target_view.runtime_resync_requested.is_connected(_request_all_snapshots):
			_target_view.runtime_resync_requested.connect(_request_all_snapshots)
	if _target_view != null and _target_view.has_signal("runtime_scope_selected"):
		if not _target_view.runtime_scope_selected.is_connected(_select_scope_for_all_sessions):
			_target_view.runtime_scope_selected.connect(_select_scope_for_all_sessions)


func set_subscribed(subscribed: bool) -> void:
	if _subscription_requested == subscribed:
		return
	_subscription_requested = subscribed
	for session in get_sessions():
		if session == null or not session.is_active():
			continue
		if subscribed:
			_subscribe_session(session)
		else:
			_unsubscribe_session(session)


func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	if session == null:
		return
	session.started.connect(_on_session_started.bind(session_id))
	session.stopped.connect(_on_session_stopped.bind(session_id))


func _on_session_started(session_id: int) -> void:
	if _subscription_requested:
		_subscribe_session(get_session(session_id))


func _on_session_stopped(session_id: int) -> void:
	_subscribed_session_ids.erase(session_id)


func _subscribe_session(session: EditorDebuggerSession) -> void:
	if session == null:
		return
	var session_id: int = session.get_session_id()
	if _subscribed_session_ids.has(session_id):
		return
	_subscribed_session_ids[session_id] = true
	session.send_message("state_graph:subscribe", [str(session_id)])
	session.send_message("state_graph:request_snapshot", [str(session_id)])


func _unsubscribe_session(session: EditorDebuggerSession) -> void:
	if session == null:
		return
	var session_id: int = session.get_session_id()
	if not _subscribed_session_ids.has(session_id):
		return
	session.send_message("state_graph:unsubscribe", [str(session_id)])
	_subscribed_session_ids.erase(session_id)


func _request_all_snapshots() -> void:
	if not _subscription_requested:
		return
	for session in get_sessions():
		if session != null and session.is_active():
			session.send_message("state_graph:request_snapshot", [str(session.get_session_id())])


func _select_scope_for_all_sessions(scope_key: StringName) -> void:
	if not _subscription_requested:
		return
	for session in get_sessions():
		if session != null and session.is_active():
			session.send_message(
				"state_graph:select_scope",
				[str(session.get_session_id()), String(scope_key)]
			)


func _has_capture(prefix: String) -> bool:
	return prefix == "state_graph"


func _capture(message: String, data: Array, session_id: int) -> bool:
	if message == "state_graph:snapshot":
		if _target_view != null and _target_view.has_method("set_runtime_snapshot") and not data.is_empty():
			_target_view.call("set_runtime_snapshot", data[0])
		return true
	if message == "state_graph:delta":
		if _target_view != null and _target_view.has_method("apply_runtime_delta") and not data.is_empty():
			var applied := bool(_target_view.call("apply_runtime_delta", data[0]))
			if not applied:
				var session := get_session(session_id)
				if session != null and session.is_active():
					session.send_message("state_graph:request_snapshot", [str(session_id)])
		return true
	if message == "state_graph:scope_registry":
		if (
			_target_view != null
			and _target_view.has_method("apply_scope_registry_event")
			and not data.is_empty()
		):
			_target_view.call("apply_scope_registry_event", data[0])
		return true
	return false
