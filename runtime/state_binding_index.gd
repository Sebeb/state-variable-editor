@tool
extends RefCounted
class_name StateBindingIndex

static var provider: Object = null

static func _provider() -> Object:
	if is_instance_valid(provider): return provider
	var path := str(ProjectSettings.get_setting("state_variables/binding_index_script", ""))
	if !path.is_empty() and ResourceLoader.exists(path): provider = load(path)
	return provider

static func scan(root: String = "res://") -> Dictionary:
	var source := _provider()
	return source.call("scan", root) if source != null else {}

static func invalidate() -> void:
	var source := _provider()
	if source != null and source.has_method("invalidate"): source.call("invalidate")

static func get_property_name() -> String:
	return str(ProjectSettings.get_setting("state_variables/binding_property", "state_path"))

static func is_binding_resource(resource: Resource) -> bool:
	if resource == null: return false
	for property in resource.get_property_list():
		if str(property.name) == get_property_name(): return true
	return false

static func bindings_for_path(index: Dictionary, state_path: String) -> Array[String]:
	var result: Array[String] = []
	for path in index:
		if str(index[path]).strip_edges().to_lower() == state_path.strip_edges().to_lower(): result.append(str(path))
	result.sort()
	return result
