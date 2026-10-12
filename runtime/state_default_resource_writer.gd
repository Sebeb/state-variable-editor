extends RefCounted
class_name StateDefaultResourceWriter

const ResourceCatalog = preload("state_resource_catalog.gd")

## Persists a DEFAULT-layer edit on a code-declared state variable to the resource
## property that declares it (PGO-226 / PGO-211 G3).
##
## [StateDefaultDatabaseWriter] rewrites an authored row in the monolithic
## `data/state/state_variable_database.tres`. A code-declared variable has no such row:
## PGO-225 inverted the relationship so the [b]resource property is the source-of-truth
## default[/b] and the baked entry is generated from it. Setting its default therefore
## means editing the owning `.tres`, and this class is the only place that happens.
##
## [b]The atomicity pattern is inherited deliberately, not re-invented.[/b] Write a
## sibling temporary file, load it back and confirm it really carries the requested
## value, and only then rename it over the original. A half-written resource file is a
## worse failure than a half-written database because it is content, not config — a
## truncated pill loses its icon, its script and its display name, not just one number.
## A crash at any point before the rename leaves the original untouched.
##
## [b]The edit is textual, not a re-save.[/b] Round-tripping the resource through
## [ResourceSaver] would rewrite every line: sub-resource ids are reallocated, properties
## sitting at their script default are dropped, and formatting is normalised — so a
## one-number tweak would land as a whole-file diff and could quietly drop data this
## class never meant to touch. Replacing the single assignment line keeps the diff to the
## value that actually changed. The corollary is that only text resources can be written;
## a binary `.res` is refused rather than mangled.

const LogLevel := preload("state_log_level.gd")
const StateVariableBakerScript := preload("state_variable_baker.gd")

const _TEMP_SUFFIX := ".state-default.tmp.tres"
const _RESOURCE_SECTION := "[resource]"
const _TEXT_RESOURCE_HEADER := "[gd_resource"


func failure_log_level(is_editor_hint: bool, is_debug_build: bool) -> int:
	return LogLevel.ERROR if is_editor_hint or is_debug_build else LogLevel.WARN


## Maps a derived state-variable path back to the resource and property that declare it.
##
## The derived path is `<base path>/<property>` by construction (PGO-225), so the last
## segment is the property and the rest is the resource's base path — which is exactly
## the key [ResourceCatalog] already indexes its entries under. Re-deriving it here from
## `res://data/...` would be a second implementation of the same rule, free to drift from
## the one the bake used; asking the catalog cannot drift.
##
## The candidate is then required to actually [i]declare[/i] that property. Without that
## check a path naming any property of any catalogued resource would be writable, and a
## typo'd path would silently rewrite a real field.
##
## Returns `{"ok": bool, "resource": StateDeclaringResource, "property": String,
## "base_path": String, "type_name": String}` or a failure dictionary.
func resolve_owner(variable_path: String) -> Dictionary:
	var normalized := variable_path.strip_edges().trim_prefix("/").trim_suffix("/")
	var property := normalized.get_file()
	var base_path := normalized.get_base_dir()
	if property.is_empty() or base_path.is_empty():
		return _failure(
			"unresolvable_path",
			"'%s' is not a derived state-variable path, so it names no resource property." % variable_path
		)
	for type_name in ResourceCatalog.get_registered_types():
		var declaring := ResourceCatalog.get_entry(type_name, base_path) as StateDeclaringResource
		if declaring == null:
			continue
		if not _declares_path(declaring, normalized):
			continue
		return {
			"ok": true,
			"resource": declaring,
			"property": property,
			"base_path": base_path,
			"type_name": str(type_name),
		}
	return _failure(
		"unknown_owner",
		"No catalogued resource at base path '%s' declares '%s'. The catalog is populated from %s." % [
			base_path, normalized, ResourceCatalog.get_source(),
		]
	)


## Persists [param value] as the shipped default of the property behind
## [param variable]'s derived path.
##
## Returns `{"ok": bool, "changed": bool, ...}`. The runtime [StateVariable] is
## deliberately left alone: the caller moves it only once the file on disk agrees, so a
## refused write never leaves the session showing a default that was not saved.
func write_default(variable: StateVariable, value: Variant) -> Dictionary:
	if variable == null:
		return _failure("missing_variable", "The live state variable is unavailable.")
	var coerced: Variant = variable.definition.coerce_value(value)
	if variable.definition.values_equal(variable.get_default_value(), coerced):
		return {"ok": true, "changed": false}
	var owner := resolve_owner(String(variable.get_path()))
	if not bool(owner.get("ok", false)):
		return owner
	var result := write_property(
		owner.get("resource") as Resource,
		str(owner.get("property", "")),
		coerced
	)
	if not bool(result.get("ok", false)):
		return result
	result.merge(_rebake(), true)
	return result


## Writes [param value] to [param property] of [param resource]'s backing file.
##
## Split out from [method write_default] so the atomic guarantee can be exercised against
## a throwaway fixture without a catalogued resource, and so the graph editor could one
## day address a resource it already holds.
func write_property(resource: Resource, property: String, value: Variant) -> Dictionary:
	if resource == null:
		return _failure("missing_resource", "The owning resource is unavailable.")
	var resource_path := resource.resource_path
	if resource_path.is_empty():
		# Godot clears `resource_path` on `duplicate()`, and runtime-only instances never
		# had one. There is no file to save into, and pretending otherwise would report a
		# default as persisted that vanishes on the next load — the failure this refusal
		# exists to prevent. The read side degrades gracefully here (see
		# StateDeclaringResource.get_declared_value); the write side must not.
		return _failure(
			"unsaved_resource",
			"The resource declaring '%s' has no resource path — it is a runtime-only or duplicate() copy, so its default cannot be saved anywhere." % property
		)
	var global_path := ProjectSettings.globalize_path(resource_path)
	if not FileAccess.file_exists(global_path) or DirAccess.dir_exists_absolute(global_path):
		return _failure("missing_or_unwritable", "%s is missing or is not a writable file." % resource_path)
	var stored := _convert_to_property_type(resource, property, value)
	if not bool(stored.get("ok", false)):
		return stored
	var stored_value: Variant = stored.get("value")

	var source := FileAccess.get_file_as_string(resource_path)
	if source.is_empty():
		return _failure("unreadable", "%s could not be read." % resource_path)
	if not source.begins_with(_TEXT_RESOURCE_HEADER):
		return _failure(
			"not_text_resource",
			"%s is not a text resource; a binary resource cannot be edited a line at a time." % resource_path
		)
	var candidate_result := _assign_resource_property(source, property, var_to_str(stored_value))
	if not bool(candidate_result.get("ok", false)):
		return candidate_result

	var temp_path := resource_path + _TEMP_SUFFIX
	var temp_global_path := ProjectSettings.globalize_path(temp_path)
	_remove_file(temp_global_path)
	var temp_file := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp_file == null:
		return _failure("unwritable", "A sibling temporary resource could not be created next to %s." % resource_path)
	temp_file.store_string(str(candidate_result.get("text", "")))
	temp_file.flush()
	temp_file = null

	var validation := _validate_candidate(temp_path, resource, property, stored_value)
	if not bool(validation.get("ok", false)):
		_remove_file(temp_global_path)
		return validation
	var replace_error := DirAccess.rename_absolute(temp_global_path, global_path)
	if replace_error != OK:
		_remove_file(temp_global_path)
		return _failure("replace_failed", "The candidate resource could not atomically replace %s." % resource_path)

	# The loaded instance is the one gameplay reads through and the one the next bake
	# collects from, so it has to agree with the file that now exists on disk.
	resource.set(property, stored_value)
	return {
		"ok": true,
		"changed": true,
		"resource_path": resource_path,
		"property": property,
		"value": stored_value,
	}


## Confirms the candidate file loads as the same kind of resource and really carries the
## requested value, before anything irreversible happens.
func _validate_candidate(
	temp_path: String,
	resource: Resource,
	property: String,
	stored_value: Variant
) -> Dictionary:
	var candidate := ResourceLoader.load(temp_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if candidate == null:
		return _failure("invalid_candidate", "The candidate resource for %s did not load." % resource.resource_path)
	if candidate.get_script() != resource.get_script():
		return _failure(
			"invalid_candidate",
			"The candidate resource for %s no longer carries the original script." % resource.resource_path
		)
	# Compared as serialised text: that is the form the file actually stores, so it
	# answers "does reloading this give back what was asked for" without a per-type
	# tolerance argument for floats and vectors.
	if var_to_str(candidate.get(property)) != var_to_str(stored_value):
		return _failure(
			"invalid_candidate",
			"The candidate resource for %s did not read back '%s' as the requested value." % [
				resource.resource_path, property,
			]
		)
	return {"ok": true}


## Re-derives the bake so the generated default matches the property that just changed.
##
## The bake is a pure function of the declarations, so a written property with an unbaked
## default is a tree that contradicts itself: the shipped build would keep serving the old
## number, and [method StateVariableBaker.verify_up_to_date] — the drift guard — would go
## red on a checkout whose only sin was tweaking a value during playtest. Re-baking here
## keeps the two in step at the moment they diverge, and costs nothing when nothing
## changed, because [method StateVariableBaker.bake] writes only on a real difference.
##
## A failed re-bake does not fail the write. The property is the source of truth and it is
## already correct on disk; the bake is the derived artifact, so the honest outcome is a
## saved default plus a reported staleness the drift guard will catch.
func _rebake() -> Dictionary:
	var bake := StateVariableBakerScript.bake(true)
	var report := {
		"bake_ok": bool(bake.get("ok", false)),
		"bake_changed": bool(bake.get("changed", false)),
	}
	if not bool(bake.get("ok", false)):
		report["bake_errors"] = bake.get("errors", PackedStringArray())
	return report


func _declares_path(declaring: StateDeclaringResource, normalized_path: String) -> bool:
	var declared := declaring.get_state_variable_declarations()
	for declaration_variant in declared.get("declarations", []) as Array:
		if str((declaration_variant as Dictionary).get("path", "")) == normalized_path:
			return true
	return false


## Converts [param value] to the property's own variant type.
##
## The state layer's value types are coarser than Godot's — a `StringName` property and a
## `String` property are both `ValueType.STRING` — so writing the state-coerced value
## verbatim would spell a `StringName` as `"x"` instead of `&"x"` and make the file
## disagree with the resource it describes.
func _convert_to_property_type(resource: Resource, property: String, value: Variant) -> Dictionary:
	for property_info in resource.get_property_list():
		if str(property_info.get("name", "")) != property:
			continue
		var usage := int(property_info.get("usage", 0))
		if usage & PROPERTY_USAGE_STORAGE == 0:
			return _failure(
				"unstored_property",
				"'%s' is not stored on %s, so it has no saved value to write." % [property, resource.resource_path]
			)
		return {"ok": true, "value": type_convert(value, int(property_info.get("type", TYPE_NIL)))}
	return _failure("unknown_property", "%s has no property named '%s'." % [resource.resource_path, property])


## Replaces — or, when the property currently sits at its script default and Godot
## therefore omitted it, appends — one assignment inside the `[resource]` section.
##
## Omission is the common case, not an edge case: a freshly declared property has never
## been touched in the inspector, so the file says nothing about it at all. A writer that
## only knew how to replace would report "missing target" for exactly the variables this
## goal exists to make editable.
func _assign_resource_property(source: String, property: String, serialized_value: String) -> Dictionary:
	var lines := source.split("\n", true)
	var section_index := -1
	for index in range(lines.size()):
		if lines[index].strip_edges() == _RESOURCE_SECTION:
			section_index = index
			break
	if section_index < 0:
		return _failure("missing_resource_section", "The resource file has no [resource] section to write into.")
	var block_end := lines.size()
	for index in range(section_index + 1, lines.size()):
		if lines[index].begins_with("["):
			block_end = index
			break

	var assignment := "%s = %s" % [property, serialized_value]
	var target_index := -1
	for index in range(section_index + 1, block_end):
		if _statement_name(lines[index]) == property:
			target_index = index
			break

	var rebuilt := PackedStringArray()
	if target_index < 0:
		# Append at the end of the section, before whatever trailing blank lines the file
		# ends with. Section order is irrelevant to Godot, and the next write finds the
		# line and replaces it in place, so this stays stable across repeated edits.
		var insert_index := block_end
		while insert_index > section_index + 1 and lines[insert_index - 1].strip_edges().is_empty():
			insert_index -= 1
		for index in range(lines.size()):
			if index == insert_index:
				rebuilt.append(assignment)
			rebuilt.append(lines[index])
		if insert_index == lines.size():
			rebuilt.append(assignment)
		return {"ok": true, "text": "\n".join(rebuilt)}

	# A value may span several lines (Godot writes dictionaries that way), so the
	# replacement consumes every line up to the next statement rather than assuming one.
	# A blank line ends it too: no serialised value contains one, and treating the file's
	# trailing newline as part of the value would silently strip it.
	var value_end := target_index + 1
	while value_end < block_end \
			and not lines[value_end].strip_edges().is_empty() \
			and _statement_name(lines[value_end]).is_empty() \
			and not lines[value_end].begins_with("["):
		value_end += 1
	for index in range(lines.size()):
		if index == target_index:
			rebuilt.append(assignment)
			continue
		if index > target_index and index < value_end:
			continue
		rebuilt.append(lines[index])
	return {"ok": true, "text": "\n".join(rebuilt)}


## The property name a `.tres` line assigns, or an empty string when the line is not an
## assignment — a continuation of a multi-line value, a blank, or a section header.
static func _statement_name(line: String) -> String:
	if line.begins_with("["):
		return ""
	var separator := line.find(" = ")
	if separator <= 0:
		return ""
	var name := line.substr(0, separator)
	if name != name.strip_edges():
		return ""
	for index in range(name.length()):
		var character := name[index]
		if character == "_" or character == "/":
			continue
		if character >= "0" and character <= "9":
			continue
		# A single character is a valid identifier only when it is a letter or an
		# underscore, which is exactly the remaining case a property name may use.
		if not character.is_valid_identifier():
			return ""
	return name


func _failure(reason: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"changed": false,
		"reason": reason,
		"message": message,
		"log_level": failure_log_level(Engine.is_editor_hint(), OS.is_debug_build()),
	}


func _remove_file(global_path: String) -> void:
	if FileAccess.file_exists(global_path):
		DirAccess.remove_absolute(global_path)
