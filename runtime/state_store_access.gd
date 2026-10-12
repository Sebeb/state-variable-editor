extends RefCounted

static var instance: Node = null
static var coordinator: RefCounted = null

static func bind(store: Node) -> void:
	instance = store
	coordinator = store.get("coordinator")

static func unbind(store: Node) -> void:
	if instance == store:
		instance = null
		coordinator = null

static func get_value(path: String, fallback: Variant = null) -> Variant:
	return instance.call("get_value", path, fallback) if is_instance_valid(instance) else fallback

static func get_variable(path: String) -> Variant:
	return instance.call("get_variable", path) if is_instance_valid(instance) else null
