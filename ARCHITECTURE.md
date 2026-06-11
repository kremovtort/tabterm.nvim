# Tabterm Architecture

## Overview

`tabterm` is a Neovim plugin for a floating terminal workspace with:

- a backdrop window
- a vertical sidebar with terminal tabs
- a panel that shows either a terminal buffer or a placeholder view

The plugin uses a mostly one-way flow:

1. An API method, command, or autocmd emits an event.
2. `reducer.lua` applies the event to logical state and repairs structural invariants.
3. `reconcile.lua` derives UI/effect commands from the current state.
4. `events.lua` executes those commands, delegating render-only commands to `ui.lua` and handling effect commands that need follow-up events.

The design is intentionally pragmatic, not dogmatically Redux-pure. The important boundary is that domain behavior changes should flow through the reducer, while window and buffer handles live outside the domain state.

## Module Roles

### `init.lua`

Public API and command entrypoints.

- Ensures setup
- Converts user actions into events
- Provides high-level helpers like `toggle()`, `new_shell()`, `focus_sidebar()`, `focus_panel()`

### `types.lua`

Event type constants shared across the plugin.

### `state.lua`

Canonical in-memory domain state.

- One workspace per tabpage
- Terminal ordering and active terminal selection
- Logical runtime flags such as `visible`

### `reducer.lua`

The main state transition layer.

- Creates and deletes terminals
- Changes active terminal
- Tracks terminal lifecycle and notifications
- Opens and closes the logical workspace
- Repairs structural invariants such as terminal ordering and active terminal selection

If a change is part of the terminal or workspace behavior, it should happen here.

### `reconcile.lua`

Maps logical state to UI operations.

- Decides whether the workspace should be mounted or unmounted
- Decides whether the panel should show a terminal or a placeholder
- Produces self-contained UI/effect commands for the command executor

`reconcile` must not mutate domain state. It should only inspect the current workspace and derive commands.

### `ui.lua`

Owns actual Neovim windows and buffers.

- Creates and closes float windows
- Renders sidebar lines and placeholder content
- Mounts terminal buffers into the panel
- Starts terminal jobs

This module may mutate `ui_state`, but it must not mutate domain state directly.

### `ui_state.lua`

Ephemeral UI registry.

- `by_tabpage[tabpage] -> { backdrop, sidebar, panel }`
- terminal buffer lookup tables
- suppression flags for autocmd-driven cleanup

This is intentionally outside the reducer because Neovim window and buffer handles are UI implementation details, not domain state.

### `events.lua`

Bridges Neovim autocmds and terminal integration signals into plugin events.

- Win/Buf lifecycle hooks
- OSC 133 and OSC 7 terminal integration
- dispatch orchestration and deferred refresh paths

### `model.lua`

Pure-ish presentation/model helpers.

- workspace and terminal constructors
- display-name and placeholder derivation
- shape normalization helpers

`ensure_terminal_shape()` still normalizes table shape in place. That is acceptable as a shape-fixup helper, but it should not be used as a hidden lifecycle state machine.

## State Ownership

There are two kinds of state.

### 1. Domain state

Stored in `state.lua` workspaces and terminals.

Examples:

- `workspace.runtime.visible`
- `workspace.active_terminal_id`
- `workspace.terminal_order`
- `terminal.runtime.phase`
- `terminal.snapshot.notification`

Rule: domain state changes belong in `reducer.lua`.

### 2. Ephemeral UI state

Stored in `ui_state.lua`.

Examples:

- panel/sidebar/backdrop `winid`
- mounted `bufnr`
- terminal buffer lookup tables
- suppression flags like `suppress_winclosed`

Rule: UI handles and cleanup flags belong in `ui_state.lua`, not in workspace or terminal tables.

## Render Flow

The normal flow is:

1. `events.dispatch(event)`
2. `reducer.apply(event)`
3. `reconcile.derive(tabpage, workspace)`
4. `events.lua` executes each derived command, delegating render-only commands to `ui.execute(cmd)` and handling effect commands that need follow-up events

The command protocol from `reconcile` to the executor should be self-contained. Command execution should not need to re-read store state to finish render-only commands. If a render step needs a terminal title, buffer, or placeholder model, that data should be provided in the command args. Effect commands such as starting a terminal may re-read current state defensively before producing follow-up events.

## Structural vs Behavioral Invariants

This plugin keeps a small `sanitize_workspace()` step in `reducer.lua`. It runs as part of `reducer.apply()` after event handling.

Allowed in `sanitize_workspace()`:

- deduplicate `terminal_order`
- remove dead references from ordering
- ensure every terminal has normalized shape
- repair `active_terminal_id` if it points to a missing terminal

Not allowed in `sanitize_workspace()`:

- changing terminal lifecycle phase because a buffer disappeared
- marking commands as exited or failed
- changing unread/read notification behavior
- any other domain transition that should correspond to an explicit event

In short:

- structural repair belongs in the reducer
- behavioral transitions belong in the reducer
- reconcile must remain a projection from state to commands

## Recovery Rules

Recovery paths exist because Neovim can invalidate windows and buffers outside the plugin's direct control.

Examples:

- user closes the panel window manually
- user wipes a terminal buffer
- another plugin changes focus or layout

Rules for recovery code:

- it may clean up `ui_state`
- it may dispatch domain events
- it should avoid directly mutating workspace or terminal tables
- it should avoid bypassing the normal `dispatch -> reducer -> reconcile -> command executor` flow for behavior changes

If a recovery path needs to reopen the workspace, prefer dispatching `WORKSPACE_OPEN_REQUESTED` instead of manually flipping state and calling UI functions directly.

## UI And Effect Commands

Current command categories derived by `reconcile.lua`:

- `MOUNT`
- `UNMOUNT`
- `RELAYOUT`
- `RENDER_SIDEBAR`
- `RENDER_PLACEHOLDER`
- `START_TERMINAL`
- `MOUNT_TERMINAL`
- `DISPOSE_TERMINAL_BUFFERS`

Command design rules:

- command args should contain everything needed to execute the command safely
- commands should be easy to inspect in logs or tests
- adding a new command is preferred over embedding more branching into existing execution paths

## Known Pragmatic Compromises

These are intentional for now:

- `sanitize_workspace()` mutates workspace shape inside the reducer after applying events
- `model.ensure_terminal_shape()` mutates passed tables to normalize shape
- `events.lua` contains some imperative glue because Neovim autocmd behavior is not purely event-sourced

These are acceptable as long as they do not become alternate domain state machines.

## Maintenance Rules

When changing the plugin, use these checks:

1. Does this change terminal or workspace behavior?
2. If yes, can it be represented as an event handled by `reducer.lua`?
3. Is this only a window, buffer, or autocmd bookkeeping detail?
4. If yes, keep it in `ui.lua` or `ui_state.lua`.
5. Does `reconcile.lua` only derive commands from current state without mutating workspace tables?

Good changes preserve the boundary:

- reducer owns behavior
- ui_state owns Neovim handles
- reconcile owns projection from state to UI/effect commands

## Smoke Test Expectations

At minimum, changes should not break these flows:

- `toggle()`
- `hide()`
- `new_shell()`
- `focus_sidebar()`
- `focus_panel()`
- manual sidebar or panel close recovery
- placeholder rendering when no live terminal buffer is mountable
