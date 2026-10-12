@tool
extends RefCounted
class_name StateResourceCatalog

static var provider: Object = null

static func _provider() -> Object:
	if is_instance_valid(provider): return provider
	var path := str(ProjectSettings.get_setting("state_variables/resource_catalog_script", ""))
	if !path.is_empty() and ResourceLoader.exists(path):
		provider = load(path)
	return provider

static func is_configured() -> bool:
	return _provider() != null

static func get_registered_types() -> Array:
	var source := _provider()
	return source.call("get_registered_types") if source != null else []

static func get_entries(type_name: String, force_refresh := false) -> Array:
	var source := _provider()
	return source.call("get_entries", type_name, force_refresh) if source != null else []

static func get_entry(type_name: String, base_path: String) -> Resource:
	var source := _provider()
	return source.call("get_entry", type_name, base_path) as Resource if source != null else null

static func get_source() -> String:
	var source := _provider()
	return str(source.call("get_source")) if source != null else "unconfigured"

static func derive_base_path(path: String) -> String:
	var root := str(ProjectSettings.get_setting("state_variables/data_root", "res://data/")).trim_suffix("/") + "/"
	return path.trim_prefix(root).get_basename() if path.begins_with(root) else ""
