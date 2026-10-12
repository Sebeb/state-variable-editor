extends RefCounted
class_name StateMachineScopeAddress

const GLOBAL_KEY := &"global"

var template_key: StringName = &""
var instance_key: StringName = &""
var qualified_key: StringName = &""


func _init(
	scope_template_key: StringName = &"",
	scope_instance_key: StringName = &""
) -> void:
	template_key = _normalize_segment(scope_template_key)
	instance_key = _normalize_segment(scope_instance_key)
	if template_key == GLOBAL_KEY and instance_key == &"":
		qualified_key = GLOBAL_KEY
	elif template_key != &"" and instance_key != &"":
		qualified_key = StringName("%s/%s" % [String(template_key), String(instance_key)])


func is_valid() -> bool:
	return qualified_key != &""


func is_global() -> bool:
	return qualified_key == GLOBAL_KEY


func get_qualified_key_string() -> String:
	return String(qualified_key)


static func global_scope():
	return StateMachineScopeAddress.new(GLOBAL_KEY)


static func entity(
	entity_template_key: StringName,
	entity_instance_key: StringName
):
	return StateMachineScopeAddress.new(entity_template_key, entity_instance_key)


static func _normalize_segment(value: StringName) -> StringName:
	return StringName(String(value).strip_edges().to_lower().trim_prefix("/").trim_suffix("/"))
