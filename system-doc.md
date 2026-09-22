# State Graph Tooling
UID: sdoc-04143fc8-5396-4af5-a05f-530835807b0d

## System Design

The State Graph is an editor and runtime inspection surface for the [runtime state system](../../systems/state/system-doc.md#system-design). It shows state values, claims, transitions, and their connections without imposing continuous debugging work on ordinary gameplay.

The in-game overlay has three presentation states: hidden, shown, and transparent overlay. Hidden means absent, not merely invisible: no graph scene exists, no runtime graph subscription remains, and no graph processing occurs. Opening it creates the view and takes one full snapshot. Subsequent changes arrive as versioned deltas. Returning to hidden disconnects and frees the overlay.

The editor bottom panel follows the same subscription model. Active debugger sessions subscribe only while the State Graph panel is visible. A newly active subscription requests one full snapshot, then applies deltas until the session stops, the panel closes, or a schema/topology mismatch requires resynchronization.

## System Implementation

`state_graph_debugger_plugin.gd` manages debugger sessions and sends `state_graph:subscribe`, `state_graph:unsubscribe`, and `state_graph:request_snapshot`. It captures `state_graph:snapshot` and `state_graph:delta` messages. `plugin.gd` derives subscription state from play state and bottom-panel visibility.

`state_graph_view.gd` stores runtime state and transition maps, graph-node indexes, and sidebar-item indexes. `apply_runtime_delta()` replaces only supplied snapshots, refreshes only their sidebar rows and graph nodes, and preserves unaffected node instances. State claim rows are rebuilt only when the local claim membership signature changes; value-only updates edit existing claim row content. Runtime claim IDs are excluded from the global structure signature.

The view has no state snapshot polling or JSON hashing. Its `_process()` method is limited to visual animation, connection drawing, compact-mode updates, and layout capture, and processing is disabled whenever the control is not visible in the tree.

Connection endpoints are regenerated from the indexed visible nodes after a delta. Full reconstruction remains available for full snapshots, topology/layout operations, relation visibility filters, or version recovery. Auto-arrangement uses directed state-to-transition-to-state ranks so cascades remain left-to-right while related branches preserve their seeded vertical order.

`tests/logot_cases/state_graph_runtime_delta_test.gd` verifies lazy lifecycle, the single activation snapshot, delta-only updates, node identity preservation, and teardown. `state_graph_auto_arrange_hybrid_test.gd` and `state_graph_relation_visibility_test.gd` cover ranked layout and visibility filtering.

`plugin.gd` registers its dock `StateGraphView` and itself into the `state_graph_dock_view` and `state_graph_editor_plugin` scene-tree groups so other addons with no direct reference (currently `addons/pill_editor`) can reach the live instances through `get_tree().get_first_node_in_group(...)`, the established cross-addon lookup convention already used for gameplay singletons elsewhere in this repo. `plugin.gd` exposes `reveal_and_focus_node(node_id)` as the public bridge for that use: it makes the bottom panel item visible, then calls the dock's existing `show_relevant`/`focus_node`.

`state_graph_view.gd` exposes three public members specifically for external embedding outside the graph canvas: `build_embedded_output_rows(transition_id)` returns one transition's Outputs section built from the exact same row/value-editor/commit/undo/save code paths the graph's own transition nodes use, with a `show_port` flag on the underlying `_build_transition_output_row` so embedded rows omit connection sockets (embedded rows are not part of the connection canvas); `open_output_picker_for_transition(transition_id, ...)` opens the same searchable output-target picker the graph's drag-to-connect flow uses, so a click-driven "Add Output" entry point commits through the graph's own commit/undo/save path; and `database_changed` is emitted from the single commit funnel `_apply_database_snapshot` after every successful do/undo, so an embedder knows when to refresh rows it built via `build_embedded_output_rows`.

The output-value commit path's callable must be built as a closure capturing `transition_id`/`output_index`, not `Callable(self, "_commit_transition_output_value").bind(transition_id, output_index)`: `Callable.bind()` appends bound arguments after the caller-supplied value rather than before it, which scrambles `_commit_transition_output_value`'s `(transition_id, output_index, value)` parameter order and silently drops the edit. This previously affected inline output-value edits in the graph itself, not only external embedders.
