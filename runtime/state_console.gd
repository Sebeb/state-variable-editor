extends RefCounted

static var service: Object = null

static func can_log(level: int, channel: String) -> bool:
	return service != null and is_instance_valid(service) and service.has_method("can_log") and bool(service.call("can_log", level, channel))

static func try_log(factory: Callable, level: int, channel: String) -> void:
	if service != null and is_instance_valid(service) and service.has_method("try_log"):
		service.call("try_log", factory, level, channel)


static func supports(method: StringName) -> bool:
	return service != null and is_instance_valid(service) and service.has_method(method)
