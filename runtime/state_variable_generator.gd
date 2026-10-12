extends RefCounted
class_name StateVariableGenerator

const ResourceCatalog = preload("state_resource_catalog.gd")

## Collects code-declared state variables off the resource catalog and renders the baked
## artifact that shipped builds read (PGO-225 / PGO-211 G2).
##
## Two directions, and they must agree:
## [br]• [method collect] walks [ResourceCatalog], asks every [StateDeclaringResource]
##   for its declarations, and derives each variable's path from the resource's own
##   location. This is the editor-time direction and the one [StateVariableBaker] writes
##   from.
## [br]• [method load_baked_declarations] reads the artifact back. This is the only
##   direction a shipped build takes: it loads one generated script and never walks
##   `res://data`, never introspects a property, and never touches the catalog.
##
## [b]The bake is a GDScript file, not a `.tres`, and that is the point.[/b] The
## monolithic `data/state/state_variable_database.tres` is a structural merge-conflict
## site: sub-resource ids are allocated from one sequential counter, so two branches
## adding a variable independently both take the next free `GameplayConfig_NN` and
## produce a duplicate id that Godot resolves silently by keeping the last one read; and
## the `states`/`entries` arrays are single enormous lines that git cannot merge. Baking
## to a script gives every variable its own block of lines, keyed by its derived path
## and sorted, with no shared id space at all — two branches declaring variables on two
## different resources touch two different regions of the file and merge cleanly. Any
## conflict that does occur is repaired by re-running the bake rather than by hand-picking
## a side. See [method render_source].

const StateVariableDefScript := preload("state_variable_def.gd")

const BAKED_SCRIPT_PATH := "res://data/state/generated_state_variables.gd"

## Ordering of the keys written into each baked block. Fixed so the rendered file is a
## pure function of the declarations — an unstable key order would make every bake a
## spurious diff.
const _BAKED_KEY_ORDER: PackedStringArray = [
	"path",
	"source",
	"property",
	"description",
	"value_type",
	"resolver",
	"default_value",
	"console_exposed",
	"console_hidden",
	"possible_values",
	"tags",
]


## Walks the resource catalog and returns every code-declared state variable.
##
## Returns `{"ok": bool, "declarations": Array[Dictionary], "errors": PackedStringArray,
## "sources": PackedStringArray}`, declarations sorted by derived path.
##
## Linear in the number of catalogued resources and declarations: paths are deduplicated
## through a dictionary rather than by rescanning the accumulated list, because this runs
## over the whole data root and the variable count is heading into the hundreds.
static func collect(force_refresh := false) -> Dictionary:
	var declarations: Array[Dictionary] = []
	var errors := PackedStringArray()
	var sources := PackedStringArray()
	var seen_paths: Dictionary = {}
	var seen_resources: Dictionary = {}

	for type_name in ResourceCatalog.get_registered_types():
		for resource in ResourceCatalog.get_entries(type_name, force_refresh):
			var declaring := resource as StateDeclaringResource
			if declaring == null:
				continue
			# A resource can be catalogued under more than one registered type, and the
			# MazeEntity root is the whole data root, so guard against re-declaring it.
			var source_path := declaring.resource_path
			if source_path.is_empty() or seen_resources.has(source_path):
				continue
			seen_resources[source_path] = true
			var result := declaring.get_state_variable_declarations()
			for error in result.get("errors", PackedStringArray()) as PackedStringArray:
				errors.append(error)
			var resource_declarations := result.get("declarations", []) as Array
			if resource_declarations.is_empty():
				continue
			sources.append(source_path)
			for declaration_variant in resource_declarations:
				var declaration := declaration_variant as Dictionary
				var path := str(declaration.get("path", ""))
				if seen_paths.has(path):
					errors.append(
						"Duplicate derived state-variable path '%s': declared by both %s and %s." % [
							path, str(seen_paths[path]), source_path,
						]
					)
					continue
				seen_paths[path] = source_path
				declarations.append(declaration)

	declarations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("path", "")) < str(b.get("path", ""))
	)
	sources.sort()
	return {
		"ok": errors.is_empty(),
		"declarations": declarations,
		"errors": errors,
		"sources": sources,
	}


## Reads the baked artifact. This is the shipped-build entry point: one script load, no
## filesystem walk, no property introspection, no dependency on [ResourceCatalog].
##
## Returns an empty array when nothing has been baked yet, so a fresh checkout that has
## not run the bake degrades to today's hand-authored-only behaviour rather than failing
## to boot.
static func load_baked_declarations() -> Array[Dictionary]:
	if not ResourceLoader.exists(BAKED_SCRIPT_PATH):
		return []
	var baked := load(BAKED_SCRIPT_PATH) as GDScript
	if baked == null:
		return []
	var raw: Variant = baked.get("DECLARATIONS")
	var declarations: Array[Dictionary] = []
	if raw is Array:
		for entry in raw as Array:
			if entry is Dictionary:
				declarations.append(entry as Dictionary)
	return declarations


## Builds runtime [StateVariableDef] instances from baked declarations.
static func build_baked_definitions() -> Array[StateVariableDef]:
	var definitions: Array[StateVariableDef] = []
	for declaration in load_baked_declarations():
		var definition := StateDeclaringResource.build_definition(declaration)
		if definition.get_normalized_path() != &"":
			definitions.append(definition)
	return definitions


## Renders the baked script for [param declarations].
##
## One dictionary per variable, one key per line, blocks ordered by derived path. The
## layout is deliberately line-oriented: it is what makes concurrent declarations on
## different resources land in different regions of the file and merge without conflict,
## and it makes the generated data reviewable in a diff instead of being one opaque line.
static func render_source(declarations: Array) -> String:
	var lines := PackedStringArray()
	lines.append("# GENERATED FILE — DO NOT EDIT BY HAND.")
	lines.append("#")
	lines.append("# Baked from code-declared state variables by StateVariableBaker (PGO-225).")
	lines.append("# Each block is derived from one property of one resource: the path comes from the")
	lines.append("# resource's location under the data root, and default_value is that property's")
	lines.append("# shipped value. Edit the resource property, then re-run the bake.")
	lines.append("#")
	lines.append("# Regenerate with the Logot command `/state/bake_declared_variables`, or by saving")
	lines.append("# in the editor with the state_variable_editor plugin enabled.")
	lines.append("extends RefCounted")
	lines.append("class_name GeneratedStateVariables")
	lines.append("")
	lines.append("")
	if declarations.is_empty():
		lines.append("const DECLARATIONS: Array[Dictionary] = []")
		lines.append("")
		return "\n".join(lines)
	lines.append("const DECLARATIONS: Array[Dictionary] = [")
	for declaration_variant in declarations:
		var declaration := declaration_variant as Dictionary
		lines.append("\t{")
		for key in _BAKED_KEY_ORDER:
			if not declaration.has(key):
				continue
			lines.append("\t\t\"%s\": %s," % [key, _render_value(declaration[key])])
		lines.append("\t},")
	lines.append("]")
	lines.append("")
	return "\n".join(lines)


## Serialises one declaration value as a GDScript constant expression.
##
## [method @GlobalScope.var_to_str] spells a typed array as `Array[String]([...])`, which
## is not a constant expression and fails to parse when the bake is loaded back — so
## arrays are flattened to untyped literals here. Everything else round-trips as-is.
static func _render_value(value: Variant) -> String:
	if value is Array:
		var untyped: Array = []
		for entry in value as Array:
			untyped.append(entry)
		return var_to_str(untyped)
	return var_to_str(value)


## Renders the bake straight from the catalog. Returns `{"ok", "source", "errors",
## "declarations", "sources"}`.
static func render_current_source(force_refresh := true) -> Dictionary:
	var collected := collect(force_refresh)
	collected["source"] = render_source(collected.get("declarations", []) as Array)
	return collected


static func read_baked_source() -> String:
	if not FileAccess.file_exists(BAKED_SCRIPT_PATH):
		return ""
	return FileAccess.get_file_as_string(BAKED_SCRIPT_PATH)


## Counts the path lookups [method merge_definitions] performs, so a test can assert the
## merge is linear rather than timing it.
##
## The same shape as [method FileUtils.get_recursive_resource_discovery_evidence]: prove
## the property by counting the operation, not by watching the clock. A dictionary-backed
## merge does exactly one lookup per generated definition; the obvious wrong version —
## asking the database for each path in turn — does one scan of every authored definition
## per generated one, which is the PGO-118/PGO-120 failure mode transplanted into boot.
static var _merge_path_lookup_count := 0


static func reset_merge_probe() -> void:
	_merge_path_lookup_count = 0


static func get_merge_path_lookup_count() -> int:
	return _merge_path_lookup_count


## Merges baked definitions into the hand-authored ones, rejecting any generated path
## that an authored definition already owns.
##
## Returns `{"definitions": Array[StateVariableDef], "generated_paths": Dictionary,
## "rejected": Array[Dictionary]}`.
##
## [b]Authored definitions win.[/b] A collision means a variable is being declared twice
## by two mechanisms, and the hand-authored entry is the one gameplay is already reading
## through, so taking the generated value would change live behaviour silently — exactly
## the failure the monolithic database's duplicate sub-resource ids already cause. The
## rejection is reported instead, and clearing it is the migration step (G4) of deleting
## the authored entry.
##
## Linear in both inputs: authored paths are indexed once, then each generated definition
## costs a single dictionary lookup.
static func merge_definitions(
	authored: Array,
	generated: Array
) -> Dictionary:
	var definitions: Array[StateVariableDef] = []
	var claimed_paths: Dictionary = {}
	for definition_variant in authored:
		var definition := definition_variant as StateVariableDef
		if definition == null:
			continue
		definitions.append(definition)
		claimed_paths[definition.get_normalized_path()] = "authored"

	var generated_paths: Dictionary = {}
	var rejected: Array[Dictionary] = []
	for definition_variant in generated:
		var definition := definition_variant as StateVariableDef
		if definition == null:
			continue
		var path := definition.get_normalized_path()
		_merge_path_lookup_count += 1
		if claimed_paths.has(path):
			rejected.append({
				"path": String(path),
				"reason": str(claimed_paths[path]),
			})
			continue
		claimed_paths[path] = "generated"
		generated_paths[path] = true
		definitions.append(definition)
	return {
		"definitions": definitions,
		"generated_paths": generated_paths,
		"rejected": rejected,
	}
