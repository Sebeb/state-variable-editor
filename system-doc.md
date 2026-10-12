# Shared State Variables
UID: sdoc-04143fc8-5396-4af5-a05f-530835807b0d

## System Design

This package owns reusable state resolution and graph tooling. A host owns its
state definitions, game resource catalog, legacy path inventory, display policy
and console instance. The runtime works with no console or resource catalog.
The `master` branch consolidates Pills' runtime/editor and AdInf's compatibility
fixes; historical editor-only consumers may continue using pinned `main`.

Each variable has a DEFAULT value, optional BASE, ordinary claims and optional
OVERRIDE. Claims contribute through the configured resolver. Muting removes a
claim's contribution without deleting its membership. The enum ordering is
stable for existing serialized resources, with VECTOR3 and MERGE appended.
Batches delay observers until the complete mutation sequence is resolved.
Entity runtimes use independent scope addresses and can be torn down explicitly.
The coordinator routes cross-scope transition claims without making game
singletons part of the package.

Resource declarations make an exported resource property the source of its
shipped DEFAULT. Editor baking produces a primitive declaration artifact.
Runtime consumes that artifact and authored databases without scanning game
files. Generated definitions remain an in-memory composite and cannot be saved
back into the authored database. Default writers validate temporary files before
replacing originals, preserving source formatting.

The graph receives an activation snapshot followed by versioned deltas.
Hidden runtime overlays contain no graph scene. Transparent graph controls are
recursively input inert. The editor panel subscribes only while visible.
Runtime graph scripts use an Object undo-redo reference so shipped builds do
not require the editor-only EditorUndoRedoManager type.

## System Implementation

`runtime/state_variable.gd` resolves layers and claims. Its compatibility
`set_claim_value` aliases keyed claims. `set_current_value` replaces ordinary
claims, retains BASE/OVERRIDE, and returns a removable anonymous claim ID;
`reset` clears BASE and ordinary claims, retaining OVERRIDE as in Pills. The exported legacy `persistent`
field in `state_variable_def.gd` remains available for host preference policy.
`state_machine_runtime.gd` owns batches, transition evaluation and subscriptions;
`state_machine_coordinator.gd` and scope/template resources manage entity state.

`runtime/state_store.gd` binds runtime access, optional console integration,
persistence and graph messages. Hosts can subclass it: initialization calls
`_initialize_host_defaults` before preference loading within the startup batch.
AdInf supplies its old DEFAULT preference format and platform UI scale through
that adapter. The package's generic modern save uses BASE/OVERRIDE; legacy
migration needs the host manifest and preserves files if it is absent.

`state_resource_catalog.gd`, `state_binding_index.gd`, `state_console.gd` and
`state_store_access.gd` are explicit adapter boundaries. See README for provider
methods and settings. Providers are optional. Binding rename plans validate
resources before saving, roll back on failed saves, and migrate saved state keys.
The generated bake is `res://data/state/generated_state_variables.gd` and must
be included in an exported game's resource set.

`state_graph_view.gd` owns graph indexes, claim rows, scopes, relation filtering
and layout. `state_graph_debugger_plugin.gd` exchanges subscribe/unsubscribe,
request_snapshot, snapshot and delta messages. `plugin.gd` exposes the graph
through cross-addon groups without depending on a particular game's editor.

`tests/run.py` creates a disposable strict-warning Godot host, imports the editor
and runs `tests/contracts.gd`. Contracts cover layers, removable legacy IDs,
muting, VECTOR3/MERGE, batching, scope isolation/teardown, database authoring,
missing-manifest protection, configured alias migration, provider bake and
owner resolution, binding rename, and graph visibility/input lifecycle.
`provenance.json` records upstream inputs; the package does not include Pills'
generated data, game catalog or path inventory. Manual verification steps are
maintained in README and each consumer's change record.
