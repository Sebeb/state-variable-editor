# Shared State Variable System and Editor

A portable Godot 4 runtime and graph editor, consolidated from Pills-God with
Adventure Infinitum's compatibility and graph input fixes. `master` is the
consolidated runtime/editor branch. The historical editor-only `main` remains
available for existing pinned consumers.

Install as a submodule at `addons/state_variable_system`, then enable the plugin
in Project Settings. Extend `runtime/state_store.gd` in a host-owned manager or
add that script as a singleton. Runtime definitions live in
`res://data/state/state_variable_database.tres`; an absent database creates an
empty runtime and can be authored through the editor. The database path can be
overridden with `state_variables/database_path`.

The package contains DEFAULT/BASE/claim/OVERRIDE layers, keyed and anonymous
claims, muting, tags, VECTOR3 and MERGE resolution, batched notifications,
transitions, entity scopes, baked resource declarations, safe default writers,
and graph authoring/debugging. It requires no game globals or Logot.

## Host integration

Host display policy, startup defaults and legacy preference behavior belong in
a small subclass. `_initialize_host_defaults()` runs inside the initialization
batch before persistence is loaded. `StateVariableDef.persistent`,
`set_claim_value()` and integer-returning `set_current_value()` preserve legacy
AdInf resources and claim callers. `set_current_value()` replaces ordinary
claims while retaining BASE/OVERRIDE. The new `reset()` deliberately clears BASE and ordinary claims, retaining
OVERRIDE. Modern persistence stores BASE and OVERRIDE separately.

Optional seams:

- Set `state_console.gd.service` (or store `Console`) to a Logot-compatible
  service. With no console, runtime logging and registration are skipped.
- Set `state_resource_catalog.gd.provider`, or
  `state_variables/resource_catalog_script` to a provider script with
  `get_registered_types()`, `get_entries(type, force_refresh)`,
  `get_entry(type, base_path)`, and `get_source()`. Entries extend
  `runtime/state_declaring_resource.gd`. The data root defaults to
  `res://data/`, configurable through `state_variables/data_root`.
- Baking writes `res://data/state/generated_state_variables.gd`. Without a
  catalog, bake is disabled and writes nothing. Export hosts must include the
  generated artifact; runtime never scans game data to discover declarations.
- External bindings use `state_binding_index.gd.provider` or
  `state_variables/binding_index_script`, exposing `scan(root)` and optional
  `invalidate()`. `state_variables/binding_property` defaults to `state_path`.
  Rename plans save bindings and restore prior values if a save fails.
- Populate `state_path_aliases.gd.renamed_paths` and the legacy migration
  manifest's `path_types`/`migration_targets` for host-specific old saves.
  Legacy saves without a configured manifest are preserved and migration
  refuses to overwrite them.

Do not load duplicate copies of these class_name scripts in one Godot host.
Consumers previously using `systems/state` should replace those scripts and
adapt preload paths, keeping game-specific catalog/migration policy in the host.

## Verification

Run `python3 tests/run.py` (`GODOT=/path/to/godot` selects the executable).
The disposable host imports the editor with strict Variant inference warnings,
then exercises layers, claims, muting, VECTOR3, MERGE, batching, isolation,
legacy migration, provider-backed bake/default resolution, external binding
rename, and graph lifecycle. No Pills or Logot checkout is needed.

Manual checks after a consumer update:

1. Open the State Graph editor, edit a value, connect a transition, undo and
   redo; the database and connections should follow each operation.
2. Open the runtime graph and inspect DEFAULT, BASE, claims and OVERRIDE;
   changing an override should immediately update the resolved value.
3. Mute/unmute a claim; its icon and resolved contribution should update.
4. Hide the graph and use underlying gameplay controls; no graph should
   intercept input. Transparent presentation must also be input inert.
5. Restart the host and confirm its preferences and overrides restore without
   converting DEFAULT preferences into BASE values.

Source revisions and original file hashes are recorded in `provenance.json`.
Pills source: `844786f6`; AdInf compatibility source: `19d2b13b`. See
[system-doc.md](system-doc.md) for architecture and integration details.
