extends RefCounted
class_name StateTransitionScope

enum Scope {
	CURRENT,
	GLOBAL,
	BOUND,
}


static func normalize_binding_key(value: StringName) -> StringName:
	return StringName(String(value).strip_edges().to_lower().trim_prefix("/").trim_suffix("/"))
