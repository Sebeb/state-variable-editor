extends RefCounted
class_name StateVariableBaker

## Writes the code-declared state-variable bake (PGO-225 / PGO-211 G2).
##
## Baking is an editor-time step by decision, not by convenience: the shipped game loads
## resources from the hand-authored `data/startup/*.tres` manifest and never walks
## `res://data`, so a runtime scan to discover declarations would pass every test and
## then find nothing in the real build. [StateStore] therefore reads only the artifact
## this class produces.
##
## The bake itself deliberately does [i]not[/i] go through the startup manifest. It walks
## the editor/tooling scan so a declaration is baked as soon as it exists, whatever a
## manifest happens to list; [method verify_manifest_coverage] then reports any baked
## source the shipped manifest omits, so the two staying in step is checked rather than
## assumed.

const StateVariableGeneratorScript := preload("state_variable_generator.gd")

const BAKED_SCRIPT_PATH := StateVariableGeneratorScript.BAKED_SCRIPT_PATH


## Regenerates the baked artifact from the current declarations.
##
## Returns `{"ok": bool, "changed": bool, "path": String, "count": int, "errors":
## PackedStringArray}`. Writes nothing when the rendered source already matches, so
## running the bake on an unchanged project produces no diff and no reimport churn.
##
## Declaration errors abort the write. A bake that dropped a malformed declaration and
## carried on would ship a database quietly missing a variable, and the resource would
## still look declared.
static func bake(force_refresh := true) -> Dictionary:
	if !StateVariableGeneratorScript.ResourceCatalog.is_configured():
		return {"ok": true, "changed": false, "path": BAKED_SCRIPT_PATH, "count": 0, "errors": PackedStringArray(), "disabled": true}
	var rendered := StateVariableGeneratorScript.render_current_source(force_refresh)
	var errors := rendered.get("errors", PackedStringArray()) as PackedStringArray
	var declarations := rendered.get("declarations", []) as Array
	if not errors.is_empty():
		return {
			"ok": false,
			"changed": false,
			"path": BAKED_SCRIPT_PATH,
			"count": declarations.size(),
			"errors": errors,
		}
	var source := str(rendered.get("source", ""))
	if StateVariableGeneratorScript.read_baked_source() == source:
		return {"ok": true, "changed": false, "path": BAKED_SCRIPT_PATH, "count": declarations.size(), "errors": errors}

	var directory := BAKED_SCRIPT_PATH.get_base_dir()
	var make_directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if make_directory_error != OK and make_directory_error != ERR_ALREADY_EXISTS:
		errors.append("Could not create %s (error %d)." % [directory, make_directory_error])
		return {"ok": false, "changed": false, "path": BAKED_SCRIPT_PATH, "count": declarations.size(), "errors": errors}

	var file := FileAccess.open(BAKED_SCRIPT_PATH, FileAccess.WRITE)
	if file == null:
		errors.append("Could not open %s for writing (error %d)." % [BAKED_SCRIPT_PATH, FileAccess.get_open_error()])
		return {"ok": false, "changed": false, "path": BAKED_SCRIPT_PATH, "count": declarations.size(), "errors": errors}
	file.store_string(source)
	file.flush()
	file = null
	return {"ok": true, "changed": true, "path": BAKED_SCRIPT_PATH, "count": declarations.size(), "errors": errors}


## Drift guard: does the committed bake still match what the declarations produce?
##
## Returns `{"ok": bool, "reason": String, "count": int, "errors": PackedStringArray}`.
## This is what keeps the inversion honest — the resource property is the source of
## truth, so an edited property with a stale bake means the shipped default no longer
## matches the resource, which is the very duplication this goal removes.
static func verify_up_to_date(force_refresh := true) -> Dictionary:
	var rendered := StateVariableGeneratorScript.render_current_source(force_refresh)
	var errors := rendered.get("errors", PackedStringArray()) as PackedStringArray
	var declarations := rendered.get("declarations", []) as Array
	if not errors.is_empty():
		return {"ok": false, "reason": "declaration_errors", "count": declarations.size(), "errors": errors}
	var expected := str(rendered.get("source", ""))
	var actual := StateVariableGeneratorScript.read_baked_source()
	if actual.is_empty():
		return {"ok": false, "reason": "not_baked", "count": declarations.size(), "errors": errors}
	if actual != expected:
		return {"ok": false, "reason": "stale", "count": declarations.size(), "errors": errors}
	return {"ok": true, "reason": "", "count": declarations.size(), "errors": errors}


## Reports baked sources the shipped startup manifest never loads.
##
## The bake is scan-backed and the shipped game is manifest-backed, so this is where the
## two are reconciled: a variable baked for a resource no manifest declares is inert in
## the real build. Returns `{"ok": bool, "checked": int, "unlisted": PackedStringArray}`.
## Takes the manifest's resource paths so this class needs no startup-system dependency.
static func verify_manifest_coverage(manifest_resource_paths: PackedStringArray, force_refresh := true) -> Dictionary:
	var listed: Dictionary = {}
	for path in manifest_resource_paths:
		listed[str(path)] = true
	var collected := StateVariableGeneratorScript.collect(force_refresh)
	var sources := collected.get("sources", PackedStringArray()) as PackedStringArray
	var unlisted := PackedStringArray()
	for source in sources:
		if not listed.has(str(source)):
			unlisted.append(str(source))
	return {"ok": unlisted.is_empty(), "checked": sources.size(), "unlisted": unlisted}
