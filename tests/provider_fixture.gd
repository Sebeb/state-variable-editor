extends RefCounted

var fixture: Resource
var invalidations := 0

func get_registered_types() -> Array:
	return ["Fixture"]

func get_entries(_type: String, _refresh: bool) -> Array:
	return [fixture]

func get_entry(_type: String, base: String) -> Resource:
	return fixture if base == "fixtures/provider" else null

func get_source() -> String:
	return "contract fixture"

func scan(_root: String) -> Dictionary:
	return {fixture.resource_path: fixture.state_path}

func invalidate() -> void:
	invalidations += 1
