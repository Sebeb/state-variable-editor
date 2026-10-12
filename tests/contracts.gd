extends SceneTree

const Def = preload("res://addons/state_variable_system/runtime/state_variable_def.gd")
const Variable = preload("res://addons/state_variable_system/runtime/state_variable.gd")
const Database = preload("res://addons/state_variable_system/runtime/state_variable_database.gd")
const Runtime = preload("res://addons/state_variable_system/runtime/state_machine_runtime.gd")
const Scope = preload("res://addons/state_variable_system/runtime/state_machine_scope_address.gd")
const Baker = preload("res://addons/state_variable_system/runtime/state_variable_baker.gd")
const Catalog = preload("res://addons/state_variable_system/runtime/state_resource_catalog.gd")
const Bindings = preload("res://addons/state_variable_system/runtime/state_binding_index.gd")
const Migration = preload("res://addons/state_variable_system/runtime/migrations/legacy_persistent_state_v1/legacy_persistent_state_v1.gd")
const Manifest = preload("res://addons/state_variable_system/runtime/migrations/legacy_persistent_state_v1/legacy_persistent_path_manifest.gd")
const Aliases = preload("res://addons/state_variable_system/runtime/state_path_aliases.gd")
const Fixture = preload("res://addons/state_variable_system/tests/declaring_fixture.gd")
const Provider = preload("res://addons/state_variable_system/tests/provider_fixture.gd")
const Writer = preload("res://addons/state_variable_system/runtime/state_default_resource_writer.gd")
const Store = preload("res://addons/state_variable_system/runtime/state_store.gd")
const Graph = preload("res://addons/state_variable_system/state_graph_view.tscn")
const Overlay = preload("res://addons/state_variable_system/runtime/state_graph_debug_overlay.gd")

var checks := 0
var failures := 0
var batches := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func definition(path: String, value: Variant, type: int = Def.ValueType.INT, resolver: int = Def.Resolver.LATEST):
	var result := Def.new()
	result.path = StringName(path)
	result.value_type = type
	result.resolver = resolver
	result.default_value = value
	return result

func run() -> void:
	var d = definition("test/value", 1)
	var v = Variable.new(d)
	check(v.resolved_value == 1, "DEFAULT initializes value")
	v.set_base_value(2)
	check(v.resolved_value == 2 and v.get_default_value() == 1, "BASE remains distinct from DEFAULT")
	v.set_claim_value(&"owner", 3)
	check(v.resolved_value == 3, "legacy claim alias")
	v.set_override(4)
	check(v.resolved_value == 4, "OVERRIDE wins")
	v.clear_override()
	v.mute_claim(&"owner")
	check(v.resolved_value == 2, "muted claim falls back to BASE")
	v.unmute_claim(&"owner")
	check(v.resolved_value == 3, "unmute restores claim")
	var id: int = v.set_current_value(5)
	check(id > 0 and v.claims.size() == 2 and v.resolved_value == 5, "legacy current value clears prior claims and returns ID")
	check(v.remove_claim(id) and v.resolved_value == 2, "legacy returned ID is removable")
	var vector = Variable.new(definition("test/vector", Vector3.ONE, Def.ValueType.VECTOR3, Def.Resolver.ADD))
	vector.add_claim(Vector3(2, 3, 4))
	check(vector.resolved_value == Vector3(3, 4, 5), "VECTOR3 ADD")
	var merged = Variable.new(definition("test/list", ["a"], Def.ValueType.LIST, Def.Resolver.MERGE))
	merged.add_claim(["a", "b"])
	check(merged.resolved_value == ["a", "b"], "MERGE deduplicates contributions")
	var db := Database.new()
	db.states.assign([d])
	var runtime := Runtime.new()
	check(runtime.configure(db, Scope.global_scope()), "global runtime configures")
	runtime.batch_committed.connect(func(_a, _b, _c, _d): batches += 1)
	runtime.batch_changes(func():
		runtime.set_claim("test/value", &"owner", 8)
		runtime.set_claim("test/value", &"owner", 9)
	)
	check(batches == 1 and runtime.get_value("test/value") == 9, "batch emits one coherent commit")
	var local := Runtime.new()
	check(local.configure(db, Scope.entity(&"actor", &"one")), "entity runtime configures")
	local.set_claim("test/value", &"owner", 20)
	check(runtime.get_value("test/value") == 9 and local.get_value("test/value") == 20, "scope isolation")
	local.teardown()
	check(local.is_torn_down(), "scope teardown")
	runtime.teardown()
	check(Baker.bake().get("disabled", false), "unconfigured catalog cannot overwrite bake")
	check(Bindings.scan().is_empty(), "unconfigured external bindings are empty")
	check(db.save_to_default_path(), "standalone authoring creates database directory")
	check(Database.load_default_database().get_definition_by_path("test/value") != null, "saved database reloads")
	var legacy := ConfigFile.new()
	legacy.set_value("persistent_defaults", "test/value", 17)
	legacy.save("user://legacy-contract.cfg")
	var migration: Dictionary = Migration.migrate_if_needed("user://legacy-contract.cfg", {"test/value": v})
	check(migration.reason == "manifest_required" and not migration.durable, "missing host manifest fails closed")
	var preserved := ConfigFile.new()
	preserved.load("user://legacy-contract.cfg")
	check(preserved.get_value("persistent_defaults", "test/value") == 17, "legacy file preserved")

	Manifest.path_types = {"test/old": "INT"}
	Manifest.migration_targets = {"test/old": "test/middle"}
	Aliases.renamed_paths = {"test/middle": "test/value"}
	legacy = ConfigFile.new()
	legacy.set_value("persistent_defaults", "test/old", 17)
	legacy.save("user://alias-contract.cfg")
	migration = Migration.migrate_if_needed("user://alias-contract.cfg", {"test/value": v})
	check(migration.durable and migration.bases.get("test/value") == 17, "legacy mapping composes modern alias")
	Manifest.path_types = {}
	Manifest.migration_targets = {}
	Aliases.renamed_paths = {}
	var fixture := Fixture.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/fixtures"))
	ResourceSaver.save(fixture, "res://data/fixtures/provider.tres")
	fixture.take_over_path("res://data/fixtures/provider.tres")
	var provider := Provider.new()
	provider.fixture = fixture
	Catalog.provider = provider
	Bindings.provider = provider
	check(Bindings.bindings_for_path(Bindings.scan(), "test/value").size() == 1, "configured binding provider")
	check(Baker.bake().ok and Baker.verify_up_to_date().ok, "configured catalog bakes declarations")
	var owner: Dictionary = Writer.new().resolve_owner("fixtures/provider/amount")
	check(owner.ok and owner.resource == fixture, "default writer resolves configured owner")
	db.states.assign([d])
	var renamed: Dictionary = db.rename_state_variable("test/value", "test/renamed")
	check(renamed.ok and fixture.state_path == &"test/renamed", "rename updates database and external binding")
	var rejected: Dictionary = db.rename_state_variable("test/renamed", "")
	check(not rejected.ok and fixture.state_path == &"test/renamed", "invalid rename leaves binding intact")
	# The standalone store contract below uses the original path again.
	db.rename_state_variable("test/renamed", "test/value")
	Catalog.provider = null
	Bindings.provider = null
	var graph = Graph.instantiate()
	root.add_child(graph)
	await process_frame
	graph.set_presentation_mode("transparent_overlay")
	check(graph.visible and graph.mouse_filter == Control.MOUSE_FILTER_IGNORE, "transparent graph ignores input")
	graph.set_presentation_mode("hidden")
	check(not graph.visible and graph.process_mode == Node.PROCESS_MODE_DISABLED, "hidden graph is inert")
	graph.queue_free()
	var overlay := Overlay.new()
	root.add_child(overlay)
	await process_frame
	check(overlay.get_child_count() == 0, "overlay starts without graph")
	overlay.set_mode("shown")
	check(overlay.get_child_count() == 1, "shown overlay instantiates graph")
	overlay.set_mode("hidden")
	await process_frame
	await process_frame
	check(overlay.get_child_count() == 0, "hidden overlay destroys graph")
	overlay.queue_free()
	var store := Store.new()
	root.add_child(store)
	await process_frame
	check(store.global_runtime != null and store.get_value("test/value") == 1, "store boots without Logot or host globals")
	store.queue_free()
	await process_frame
	print("Shared state contracts: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
