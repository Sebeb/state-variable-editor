extends RefCounted
class_name StateClaim

var claim_id: int = 0
var value: Variant = null
var is_default: bool = false
var muted: bool = false
var activation_serial: int = 0
var update_serial: int = 0


func _init(
	p_claim_id: int = 0,
	p_value: Variant = null,
	p_is_default: bool = false,
	p_activation_serial: int = 0
) -> void:
	claim_id = p_claim_id
	value = p_value
	is_default = p_is_default
	activation_serial = p_activation_serial
	update_serial = p_activation_serial


func to_debug_string() -> String:
	return "#%d%s%s=%s" % [
		claim_id,
		" (default)" if is_default else "",
		" (muted)" if muted else "",
		str(value),
	]
