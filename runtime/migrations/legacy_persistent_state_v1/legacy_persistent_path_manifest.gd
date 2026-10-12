extends RefCounted
class_name LegacyPersistentPathManifestV1

const StatePathAliases = preload("../../state_path_aliases.gd")

static var path_types: Dictionary = {}
static var migration_targets: Dictionary = {}

static func get_paths() -> Array[String]:
	var result: Array[String] = []
	for path in path_types: result.append(str(path))
	result.sort()
	return result

static func get_type_name(path: String) -> String:
	return str(path_types.get(path, ""))

static func get_migration_target(path: String) -> String:
	return StatePathAliases.resolve(str(migration_targets.get(path, path)))
