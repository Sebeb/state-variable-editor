extends RefCounted
class_name StateConsoleNotifier

signal changed()


func notify() -> void:
	changed.emit()
