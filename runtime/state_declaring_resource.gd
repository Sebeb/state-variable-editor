@tool
extends Resource
class_name StateDeclaringResource

const ResourceCatalog = preload("state_resource_catalog.gd")

## Base class for resources that declare state variables on their own properties.
##
## A subclass overrides [method _get_state_variable_declarations] and returns one
## dictionary per property it wants published as a state variable. The variable's path
## is not written anywhere: it is derived from the resource's own location, as
## `<base path>/<property>` — `res://data/pills/addiction.tres` declaring
## `addiction_min_heartbeat_pitch` becomes
## `pills/addiction/addiction_min_heartbeat_pitch`. See [method
## ResourceCatalog.derive_base_path].
##
## [b]The property is the source-of-truth default.[/b] This inverts the older
## [GameplayConfig] relationship, where a database entry's `default_value` shadowed the
## resource field and the two were kept in step by hand. Here the baked entry is
## generated [i]from[/i] the property, so there is only one place to edit.
##
## [b]Declaration is explicit, not magic.[/b] GDScript has no custom annotations, and an
## `@export`-naming convention was rejected as too implicit, so the metadata list is
## written out and then checked against [method Object.get_property_list]: a declared
## property must actually exist and must actually be stored on the resource. Everything
## that can be read off the real property — its value type, its enum options, its
## current value — is read off it rather than restated, so the declaration cannot drift
## from the property it describes.
##
## Declarations are evaluated per instance, so a resource may declare conditionally
## (see [method PillProperties._get_state_variable_declarations], which asks the pill's
## behaviour script). Baking happens at editor time via [StateVariableBaker]; nothing
## here runs in a shipped build.

const StateStore = preload("state_store_access.gd")
const StateVariableDefScript := preload("state_variable_def.gd")

## Declaration keys. `property` and `description` are required; the rest default from
## the property itself or from [StateVariableDef]'s own defaults.
const KEY_PROPERTY := "property"
const KEY_DESCRIPTION := "description"
const KEY_VALUE_TYPE := "value_type"
const KEY_RESOLVER := "resolver"
const KEY_CONSOLE_EXPOSED := "console_exposed"
const KEY_CONSOLE_HIDDEN := "console_hidden"
const KEY_POSSIBLE_VALUES := "possible_values"
const KEY_TAGS := "tags"

## Tag applied to every generated definition, so code-declared variables can be told
## apart from hand-authored ones at runtime without consulting the bake.
const CODE_DECLARED_TAG := "code_declared"

## Variant type -> [enum StateVariableDef.ValueType]. Types absent here cannot be
## inferred and must be declared explicitly, which keeps the failure loud instead of
## silently coercing an unsupported property to a string.
const _VALUE_TYPE_BY_VARIANT_TYPE := {
	TYPE_BOOL: StateVariableDefScript.ValueType.BOOL,
	TYPE_INT: StateVariableDefScript.ValueType.INT,
	TYPE_FLOAT: StateVariableDefScript.ValueType.FLOAT,
	TYPE_STRING: StateVariableDefScript.ValueType.STRING,
	TYPE_STRING_NAME: StateVariableDefScript.ValueType.STRING,
	TYPE_VECTOR2: StateVariableDefScript.ValueType.VECTOR2,
	TYPE_VECTOR3: StateVariableDefScript.ValueType.VECTOR3,
	TYPE_ARRAY: StateVariableDefScript.ValueType.LIST,
}


## Override point: the explicit metadata list. Returns one dictionary per declared
## property, keyed by the `KEY_*` constants above. The default is no declarations, so a
## subclass that never overrides this contributes nothing to the bake.
func _get_state_variable_declarations() -> Array[Dictionary]:
	return []


## Validated, fully-populated declarations for this resource instance.
##
## Returns `{"ok": bool, "base_path": String, "declarations": Array[Dictionary],
## "errors": PackedStringArray}`. Each returned declaration carries its derived `path`,
## its inferred `value_type`, and the property's current value as `default_value`.
## Resources with no derived base path — runtime-only instances, [method
## Resource.duplicate] copies, anything outside the data root — declare nothing, which
## is what lets a test build a throwaway copy and keep editing the plain property.
func get_state_variable_declarations() -> Dictionary:
	var base_path := get_base_path()
	var declarations: Array[Dictionary] = []
	var errors := PackedStringArray()
	var raw_declarations := _get_state_variable_declarations()
	if raw_declarations.is_empty() or base_path.is_empty():
		return {"ok": true, "base_path": base_path, "declarations": declarations, "errors": errors}

	var properties_by_name := _build_stored_property_index()
	var seen_properties: Dictionary = {}
	for raw_declaration in raw_declarations:
		var property_name := str(raw_declaration.get(KEY_PROPERTY, "")).strip_edges()
		if property_name.is_empty():
			errors.append("%s: a declaration is missing its '%s' key." % [resource_path, KEY_PROPERTY])
			continue
		if seen_properties.has(property_name):
			errors.append("%s: property '%s' is declared more than once." % [resource_path, property_name])
			continue
		seen_properties[property_name] = true
		if not properties_by_name.has(property_name):
			# Either the property does not exist or it is not stored on the resource.
			# A non-stored property has no saved value, so it cannot be the
			# source-of-truth default this whole mechanism rests on.
			errors.append(
				"%s: declared property '%s' is not a stored property of %s." % [
					resource_path, property_name, get_class(),
				]
			)
			continue
		var declaration := _normalize_declaration(
			base_path,
			property_name,
			properties_by_name[property_name] as Dictionary,
			raw_declaration,
			errors
		)
		if not declaration.is_empty():
			declarations.append(declaration)
	declarations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("path", "")) < str(b.get("path", ""))
	)
	return {
		"ok": errors.is_empty(),
		"base_path": base_path,
		"declarations": declarations,
		"errors": errors,
	}


## Resolves a declared property through the state system, falling back to the plain
## property when there is nothing to resolve against.
##
## This is the read helper code-declared variables are meant to be consumed through —
## the generalisation of [method GameplayConfig.get_float]. The fallback is load-bearing
## in two directions: a runtime-only or duplicated resource has no derived path and so
## keeps behaving exactly like a plain property, and a resource whose declaration has
## not been baked yet still reads its own value rather than nothing.
func get_declared_value(property: StringName) -> Variant:
	var fallback: Variant = get(property)
	var base_path := get_base_path()
	if base_path.is_empty() or StateStore == null:
		return fallback
	var variable_path := "%s/%s" % [base_path, property]
	return StateStore.get_value(variable_path, fallback)


func get_declared_float(property: StringName) -> float:
	return float(get_declared_value(property))


func get_declared_int(property: StringName) -> int:
	return int(get_declared_value(property))


func get_declared_bool(property: StringName) -> bool:
	return bool(get_declared_value(property))


## Stored script properties of this instance, keyed by name.
##
## Restricted to [constant PROPERTY_USAGE_STORAGE] script variables: a property that is
## not serialised with the resource cannot supply a shipped default, and an engine-side
## property (`resource_path`, `script`) is not something a resource may declare.
func _build_stored_property_index() -> Dictionary:
	var index: Dictionary = {}
	for property in get_property_list():
		var usage := int(property.get("usage", 0))
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		index[str(property.get("name", ""))] = property
	return index


func _normalize_declaration(
	base_path: String,
	property_name: String,
	property_info: Dictionary,
	raw_declaration: Dictionary,
	errors: PackedStringArray
) -> Dictionary:
	var description := str(raw_declaration.get(KEY_DESCRIPTION, "")).strip_edges()
	if description.is_empty():
		# Logot surfaces the description as the command's highlight text, and the
		# hand-authored database is already held to this, so generated entries are too.
		errors.append("%s: declared property '%s' has no description." % [resource_path, property_name])
		return {}

	var inferred := _infer_value_type(property_info)
	var value_type := int(raw_declaration.get(KEY_VALUE_TYPE, inferred.get("value_type", -1)))
	if value_type < 0:
		errors.append(
			"%s: property '%s' has variant type %d, which has no state value type. Declare '%s' explicitly." % [
				resource_path, property_name, int(property_info.get("type", TYPE_NIL)), KEY_VALUE_TYPE,
			]
		)
		return {}

	var possible_values: Array = []
	if raw_declaration.has(KEY_POSSIBLE_VALUES):
		possible_values = (raw_declaration[KEY_POSSIBLE_VALUES] as Array).duplicate()
	else:
		possible_values = (inferred.get("possible_values", []) as Array).duplicate()

	# Deliberately untyped: these dictionaries are rendered into the bake with
	# var_to_str, and a typed array serialises as `Array[String]([...])`, which is not a
	# constant expression and will not parse back.
	var tags: Array = [CODE_DECLARED_TAG]
	for tag in raw_declaration.get(KEY_TAGS, []) as Array:
		var normalized_tag := str(tag).strip_edges().to_lower()
		if not normalized_tag.is_empty() and not tags.has(normalized_tag):
			tags.append(normalized_tag)

	return {
		"path": "%s/%s" % [base_path, property_name],
		"source": resource_path,
		"property": property_name,
		"description": description,
		"value_type": value_type,
		"resolver": int(raw_declaration.get(KEY_RESOLVER, StateVariableDefScript.Resolver.LATEST)),
		"default_value": get(property_name),
		"console_exposed": bool(raw_declaration.get(KEY_CONSOLE_EXPOSED, true)),
		"console_hidden": bool(raw_declaration.get(KEY_CONSOLE_HIDDEN, false)),
		"possible_values": possible_values,
		"tags": tags,
	}


## Reads the value type — and, for an enum-hinted property, its options — off the real
## property rather than making the declaration restate them.
static func _infer_value_type(property_info: Dictionary) -> Dictionary:
	var variant_type := int(property_info.get("type", TYPE_NIL))
	var hint := int(property_info.get("hint", PROPERTY_HINT_NONE))
	if hint == PROPERTY_HINT_ENUM and (variant_type == TYPE_STRING or variant_type == TYPE_STRING_NAME):
		var options: Array = []
		for entry in str(property_info.get("hint_string", "")).split(",", false):
			# Godot spells enum hints as "name" or "name:value"; only the name is the
			# state value, matching how `@export_enum` string properties store it.
			var option := str(entry).split(":")[0].strip_edges()
			if not option.is_empty() and not options.has(option):
				options.append(option)
		return {"value_type": StateVariableDefScript.ValueType.ENUM, "possible_values": options}
	if _VALUE_TYPE_BY_VARIANT_TYPE.has(variant_type):
		return {"value_type": int(_VALUE_TYPE_BY_VARIANT_TYPE[variant_type]), "possible_values": []}
	return {"value_type": -1, "possible_values": []}


## Rebuilds a [StateVariableDef] from a declaration dictionary — the shape produced by
## [method get_state_variable_declarations] and, after a round trip through the bake, by
## [GeneratedStateVariables]. Both paths must produce identical definitions, which is
## what makes the bake verifiable.
static func build_definition(declaration: Dictionary) -> StateVariableDef:
	var definition := StateVariableDefScript.new() as StateVariableDef
	definition.path = StringName(str(declaration.get("path", "")))
	definition.description = str(declaration.get("description", ""))
	definition.value_type = int(declaration.get("value_type", StateVariableDefScript.ValueType.BOOL))
	definition.resolver = int(declaration.get("resolver", StateVariableDefScript.Resolver.LATEST))
	definition.default_value = declaration.get("default_value")
	definition.console_exposed = bool(declaration.get("console_exposed", true))
	definition.console_hidden = bool(declaration.get("console_hidden", false))
	definition.possible_values = (declaration.get("possible_values", []) as Array).duplicate()
	var tags: Array[String] = []
	for tag in declaration.get("tags", []) as Array:
		tags.append(str(tag))
	definition.tags = tags
	definition.ensure_valid_configuration()
	return definition


func get_base_path() -> String:
	return ResourceCatalog.derive_base_path(resource_path)
