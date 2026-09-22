# State Variable Editor

A Godot editor plugin for inspecting and editing the state graph used by
[Pills-God](https://github.com/Sebeb/Pills-God).

Install this repository at `addons/state_variable_editor`, then enable
`State Variable Editor` in Godot's Project Settings under Plugins.

## Host requirements

The editor is intentionally a view over a host project's state model. It does
not own or duplicate that model. Full functionality currently requires these
host paths:

- `res://systems/state/state_variable_database.gd`
- `res://systems/state/state_variable_baker.gd`
- `res://systems/state/state_claim_slot_def.gd`
- `res://systems/state/state_transition_condition_def.gd`
- `res://systems/state/state_transition_def.gd`
- `res://systems/state/state_transition_output_def.gd`
- `res://systems/state/state_variable_def.gd`
- `res://systems/state/state_variable_rename.gd`
- `res://systems/state/entity_state_machine_template.gd`
- `res://systems/pills/pill_activation_binding_index.gd`

The authoring view also scans `res://data/` for entity state-machine template
resources. Runtime graph inspection expects the host game to implement the
`state_graph:subscribe`, `state_graph:unsubscribe`, `state_graph:request_snapshot`,
`state_graph:snapshot`, `state_graph:delta`, and `state_graph:scope_registry`
debugger messages described in `system-doc.md`.

When these requirements are absent, the plugin remains enableable but does not
install its inspector, graph panel, or debugger integration. This allows a host
to carry the shared dependency before its state runtime is integrated.

## Attribution

The initial source was extracted from
[`Sebeb/Pills-God`](https://github.com/Sebeb/Pills-God) at commit
`ff0b89d1840cb2a3c411f52a607183a15db1dfcf`.

Files taken from `addons/state_variable_editor/`:

- `plugin.cfg`
- `plugin.gd`
- `plugin.gd.uid`
- `state_graph_debugger_plugin.gd`
- `state_graph_debugger_plugin.gd.uid`
- `state_graph_output_picker.gd`
- `state_graph_output_picker.gd.uid`
- `state_graph_output_picker.tscn`
- `state_graph_view.gd`
- `state_graph_view.gd.uid`
- `state_graph_view.tscn`
- `state_variable_database_editor.gd`
- `state_variable_database_editor.gd.uid`
- `state_variable_inspector_plugin.gd`
- `state_variable_inspector_plugin.gd.uid`
- `system-doc.md`

The extraction copied the committed tree at that revision. Uncommitted files
and changes in the source checkout were not included.
