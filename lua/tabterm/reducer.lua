local model = require("tabterm.model")
local state = require("tabterm.state")
local types = require("tabterm.types")

local M = {}

---@param workspace tabterm.Workspace?
---@param terminal_id string?
---@return boolean
local function terminal_is_visible(workspace, terminal_id)
	return workspace ~= nil and workspace.runtime.visible and workspace.active_terminal_id == terminal_id
end

---@param order string[]
---@param id string
local function remove_from_order(order, id)
	for index = #order, 1, -1 do
		if order[index] == id then
			table.remove(order, index)
		end
	end
end

---@param order string[]
---@param id string
---@param to_index integer
local function move_in_order(order, id, to_index)
	remove_from_order(order, id)
	to_index = math.max(1, math.min(#order + 1, to_index))
	table.insert(order, to_index, id)
end

---@param workspace tabterm.Workspace
---@return string
local function next_id(workspace)
	local id = ("t%d"):format(workspace.runtime.next_terminal_seq)
	workspace.runtime.next_terminal_seq = workspace.runtime.next_terminal_seq + 1
	return id
end

---@param workspace tabterm.Workspace?
---@param terminal_id string?
local function drop_terminal(workspace, terminal_id)
	if not workspace or not terminal_id then
		return
	end

	local terminal = workspace and workspace.terminals_by_id[terminal_id] or nil
	if not terminal then
		return
	end

	local removed_index = nil
	for index, id in ipairs(workspace.terminal_order) do
		if id == terminal_id then
			removed_index = index
			break
		end
	end

	workspace.terminals_by_id[terminal_id] = nil
	remove_from_order(workspace.terminal_order, terminal_id)

	if workspace.active_terminal_id == terminal_id then
		if #workspace.terminal_order == 0 then
			workspace.active_terminal_id = nil
		else
			local next_index = math.min(removed_index or 1, #workspace.terminal_order)
			workspace.active_terminal_id = workspace.terminal_order[next_index]
		end
	end
end

---@param workspace tabterm.Workspace?
---@param visible_terminal_id string?
local function prune_hidden_exited_cmds(workspace, visible_terminal_id)
	if not workspace then
		return
	end

	local ids = vim.deepcopy(workspace.terminal_order)
	for _, id in ipairs(ids) do
		local terminal = workspace.terminals_by_id[id]
		if
			terminal
			and terminal.spec.kind == "cmd"
			and terminal.runtime.phase == "exited"
			and id ~= visible_terminal_id
		then
			drop_terminal(workspace, id)
		end
	end
end

---@param workspace tabterm.Workspace
---@param spec tabterm.TerminalSpecInput?
---@param to_index integer?
---@return tabterm.Terminal
local function create_terminal(workspace, spec, to_index)
	local id = next_id(workspace)
	local terminal = model.new_terminal(id, spec)
	workspace.terminals_by_id[id] = terminal
	local index = tonumber(to_index) or (#workspace.terminal_order + 1)
	index = math.max(1, math.min(#workspace.terminal_order + 1, index))
	table.insert(workspace.terminal_order, index, id)
	workspace.active_terminal_id = id
	return terminal
end

---@param workspace tabterm.Workspace?
---@return tabterm.Workspace?
local function sanitize_workspace(workspace)
	if not workspace then
		return nil
	end

	local ordered = {}
	local seen = {}
	for _, id in ipairs(workspace.terminal_order) do
		if workspace.terminals_by_id[id] and not seen[id] then
			table.insert(ordered, id)
			seen[id] = true
		end
	end

	for id, terminal in pairs(workspace.terminals_by_id) do
		workspace.terminals_by_id[id] = model.ensure_terminal_shape(id, terminal)
		if not seen[id] then
			table.insert(ordered, id)
			seen[id] = true
		end
	end
	workspace.terminal_order = ordered

	if #workspace.terminal_order == 0 then
		workspace.active_terminal_id = nil
	elseif not workspace.active_terminal_id or not workspace.terminals_by_id[workspace.active_terminal_id] then
		workspace.active_terminal_id = workspace.terminal_order[1]
	end

	return workspace
end

---@param event tabterm.Event
---@return tabterm.Workspace?
local function apply_unsanitized(event)
	local tabpage = event.tabpage or state.current_tabpage()
	local create_workspace = event.type ~= types.events.TABPAGE_CLOSED
	local workspace = state.get_workspace(tabpage, create_workspace)
	if event.type == types.events.TABPAGE_CLOSED then
		state.workspaces_by_tab[state.tab_key(tabpage)] = nil
		return nil
	end
	if not workspace then
		return nil
	end

	if event.type == types.events.WORKSPACE_OPEN_REQUESTED then
		workspace.runtime.visible = true
		workspace.runtime.last_editor_winid = event.payload and event.payload.winid or vim.api.nvim_get_current_win()
		return workspace
	end

	if
		event.type == types.events.WORKSPACE_CLOSE_REQUESTED
		or event.type == types.events.SIDEBAR_WINDOW_CLOSED_EXTERNALLY
		or event.type == types.events.PANEL_WINDOW_CLOSED_EXTERNALLY
	then
		if workspace then
			workspace.runtime.visible = false

			prune_hidden_exited_cmds(workspace, nil)
		end
		return workspace
	end

	if event.type == types.events.WORKSPACE_TOGGLE_REQUESTED then
		workspace.runtime.visible = not workspace.runtime.visible
		if workspace.runtime.visible then
			workspace.runtime.last_editor_winid = event.payload and event.payload.winid
				or vim.api.nvim_get_current_win()
		end
		return workspace
	end

	if event.type == types.events.TERMINAL_CREATE_REQUESTED then
		local payload = event.payload or {}
		local created = create_terminal(workspace, payload.spec or {}, payload.to_index)
		prune_hidden_exited_cmds(workspace, created and created.id or workspace.active_terminal_id)
		return workspace
	end

	local terminal_id = event.terminal_id or workspace and workspace.active_terminal_id
	local terminal = workspace and terminal_id and workspace.terminals_by_id[terminal_id] or nil

	if event.type == types.events.TERMINAL_DELETE_REQUESTED then
		if terminal then
			drop_terminal(workspace, terminal_id)
			if #workspace.terminal_order == 0 then
				workspace.runtime.visible = false
			end
		end
		return workspace
	end

	if not terminal and event.type ~= types.events.TABPAGE_CLOSED then
		return workspace
	end
	if not terminal or not terminal_id then
		return workspace
	end

	if event.type == types.events.TERMINAL_RENAME_REQUESTED then
		terminal.spec.name_override = event.payload and event.payload.name_override or nil
		return workspace
	end

	if event.type == types.events.TERMINAL_SELECT_REQUESTED then
		workspace.active_terminal_id = terminal_id
		terminal.snapshot.notification.unread = false
		prune_hidden_exited_cmds(workspace, terminal_id)
		return workspace
	end

	if event.type == types.events.TERMINAL_READ_REQUESTED then
		if terminal then
			terminal.snapshot.notification.unread = false
		end
		return workspace
	end

	if event.type == types.events.TERMINAL_NEXT_REQUESTED or event.type == types.events.TERMINAL_PREV_REQUESTED then
		if #workspace.terminal_order == 0 then
			workspace.active_terminal_id = nil
			return workspace
		end

		local current_index = 1
		for index, id in ipairs(workspace.terminal_order) do
			if id == workspace.active_terminal_id then
				current_index = index
				break
			end
		end

		local delta = event.type == types.events.TERMINAL_NEXT_REQUESTED and 1 or -1
		local next_index = ((current_index - 1 + delta) % #workspace.terminal_order) + 1
		workspace.active_terminal_id = workspace.terminal_order[next_index]
		prune_hidden_exited_cmds(workspace, workspace.active_terminal_id)
		return workspace
	end

	if event.type == types.events.TERMINAL_MOVE_REQUESTED then
		move_in_order(workspace.terminal_order, terminal_id, event.payload and event.payload.to_index or 1)
		return workspace
	end

	if event.type == types.events.TERMINAL_START_REQUESTED then
		terminal.runtime.phase = "starting"
		terminal.runtime.channel_id = nil
		terminal.runtime.command.phase = terminal.spec.kind == "cmd" and "running" or "unknown"
		return workspace
	end

	if event.type == types.events.TERMINAL_PROCESS_OPENED then
		terminal.runtime.phase = "live"
		terminal.runtime.channel_id = event.payload.channel_id
		return workspace
	end

	if event.type == types.events.TERMINAL_START_FAILED then
		terminal.runtime.phase = "stopped"
		terminal.runtime.channel_id = nil
		terminal.runtime.command.phase = "unknown"
		terminal.snapshot.last_result.kind = "error"
		terminal.snapshot.last_result.code = nil
		terminal.snapshot.last_result.source = "process"
		terminal.snapshot.last_output_line = event.payload and event.payload.message or "Failed to start terminal"
		terminal.snapshot.notification.unread = false
		terminal.snapshot.notification.kind = "error"
		terminal.snapshot.notification.line = nil
		return workspace
	end

	if event.type == types.events.TERMINAL_PROCESS_EXITED then
		terminal.runtime.phase = "exited"
		terminal.runtime.channel_id = nil
		terminal.runtime.command.phase = "unknown"

		local source = event.payload and event.payload.source
		if not source then
			source = terminal.spec.kind == "cmd" and "process" or "unknown"
		end

		terminal.snapshot.last_result.kind = (event.payload and event.payload.code or 0) == 0 and "success" or "error"
		terminal.snapshot.last_result.code = event.payload and event.payload.code or 0
		terminal.snapshot.last_result.source = source
		terminal.snapshot.notification.unread = not terminal_is_visible(workspace, terminal_id)
		terminal.snapshot.notification.kind = terminal.snapshot.last_result.kind
		return workspace
	end

	if event.type == types.events.SHELL_INTEGRATION_DETECTED then
		terminal.runtime.command.integration = event.payload.integration
		return workspace
	end

	if event.type == types.events.SHELL_PROMPT_STARTED then
		terminal.runtime.command.phase = "prompt"
		return workspace
	end

	if event.type == types.events.SHELL_COMMAND_INPUT_STARTED then
		terminal.runtime.command.phase = "editing"
		return workspace
	end

	if event.type == types.events.SHELL_COMMAND_EXECUTED then
		terminal.runtime.command.phase = "running"
		return workspace
	end

	if event.type == types.events.SHELL_COMMAND_FINISHED then
		terminal.runtime.command.phase = "prompt"
		terminal.snapshot.last_result.kind = (event.payload.code or 0) == 0 and "success" or "error"
		terminal.snapshot.last_result.code = event.payload.code or 0
		terminal.snapshot.last_result.source = "shell"
		terminal.snapshot.notification.unread = not terminal_is_visible(workspace, terminal_id)
		terminal.snapshot.notification.kind = terminal.snapshot.last_result.kind
		terminal.snapshot.notification.line = nil
		return workspace
	end

	if event.type == types.events.SHELL_COMMAND_ABORTED then
		terminal.runtime.command.phase = "prompt"
		return workspace
	end

	if event.type == types.events.TERMINAL_CWD_REPORTED then
		terminal.snapshot.cwd = event.payload.cwd
		return workspace
	end

	if event.type == types.events.TERMINAL_TITLE_UPDATED then
		terminal.snapshot.title = event.payload.title
		return workspace
	end

	if event.type == types.events.SHELL_BACKGROUND_JOB_NOTIFIED then
		local kind = event.payload and event.payload.kind or "unknown"
		local line = event.payload and event.payload.line or nil
		terminal.snapshot.notification.unread = true
		terminal.snapshot.notification.kind = kind
		terminal.snapshot.notification.line = line
		if line and line ~= "" then
			terminal.snapshot.last_output_line = line
		end
		return workspace
	end

	if event.type == types.events.TERMINAL_BUFFER_WIPED_EXTERNALLY then
		terminal.runtime.phase = "stopped"
		terminal.runtime.channel_id = nil
		terminal.runtime.command.phase = "unknown"
		return workspace
	end

	return workspace
end

---@param event tabterm.Event
---@return tabterm.Workspace?
function M.apply(event)
	return sanitize_workspace(apply_unsanitized(event))
end

return M
