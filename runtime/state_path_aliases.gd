extends RefCounted
class_name StatePathAliases

static var renamed_paths: Dictionary = {}

static func resolve(path: String) -> String:
	var current := path.strip_edges().to_lower()
	for _step in renamed_paths.size():
		if !renamed_paths.has(current): break
		current = str(renamed_paths[current])
	return current

static func is_alias(path: String) -> bool:
	return renamed_paths.has(path.strip_edges().to_lower())
