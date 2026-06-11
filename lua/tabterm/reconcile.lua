local types = require("tabterm.types")
local ui_state = require("tabterm.ui_state")
local util = require("tabterm.util")

local M = {}

---@param commands tabterm.UICommand[]
---@param stale_terminal_refs tabterm.TerminalBufferRef[]
local function append_dispose_commands(commands, stale_terminal_refs)
	if #stale_terminal_refs == 0 then
		return
	end

	table.insert(commands, {
		types.ui_commands.DISPOSE_TERMINAL_BUFFERS,
		{
			terminal_refs = stale_terminal_refs,
		},
	})
end

---@param terminal tabterm.Terminal?
---@return boolean
local function can_mount_in_panel(terminal)
	if not terminal then
		return false
	end
	local bufnr = ui_state.get_terminal_bufnr(terminal.id)
	if not util.valid_buf(bufnr) then
		return false
	end
	if terminal.runtime.phase == "live" then
		return true
	end
	return terminal.runtime.phase == "exited"
end

---@param tabpage integer
---@param workspace tabterm.Workspace?
---@return tabterm.TerminalBufferRef[]
local function stale_terminal_refs(tabpage, workspace)
	local refs = {}
	local live_terminals = workspace and workspace.terminals_by_id or {}

	for _, ref in ipairs(ui_state.terminal_refs_for_tabpage(tabpage)) do
		if not live_terminals[ref.terminal_id] then
			table.insert(refs, ref)
		end
	end

	return refs
end

---@param commands tabterm.UICommand[]
---@param tabpage integer
---@param workspace tabterm.Workspace
local function append_start_terminal_commands(commands, tabpage, workspace)
	for _, terminal_id in ipairs(workspace.terminal_order) do
		local terminal = workspace.terminals_by_id[terminal_id]
		if terminal and terminal.runtime.phase == "starting" then
			table.insert(commands, {
				types.ui_commands.START_TERMINAL,
				{
					tabpage = tabpage,
					terminal_id = terminal.id,
					terminal = terminal,
				},
			})
		end
	end
end

---@param tabpage integer
---@param workspace tabterm.Workspace?
---@return tabterm.UICommand[]
function M.derive(tabpage, workspace)
	if not workspace then
		return {}
	end

	local stale_refs = stale_terminal_refs(tabpage, workspace)

	local ui = ui_state.get(tabpage)
	local has_any_window = util.valid_win(ui.backdrop.winid)
		or util.valid_win(ui.sidebar.winid)
		or util.valid_win(ui.panel.winid)
	local has_windows = util.valid_win(ui.backdrop.winid)
		and util.valid_win(ui.sidebar.winid)
		and util.valid_win(ui.panel.winid)

	---@type tabterm.UICommand[]
	local commands = {}

	if not workspace.runtime.visible then
		if has_any_window then
			table.insert(commands, { types.ui_commands.UNMOUNT, { tabpage = tabpage } })
		end
		append_dispose_commands(commands, stale_refs)
		return commands
	end

	if not has_windows then
		table.insert(commands, { types.ui_commands.MOUNT, { tabpage = tabpage } })
	else
		table.insert(commands, { types.ui_commands.RELAYOUT, { tabpage = tabpage } })
	end

	table.insert(commands, { types.ui_commands.RENDER_SIDEBAR, { tabpage = tabpage, workspace = workspace } })

	local active = workspace.active_terminal_id and workspace.terminals_by_id[workspace.active_terminal_id] or nil
	if not can_mount_in_panel(active) then
		table.insert(commands, { types.ui_commands.RENDER_PLACEHOLDER, { tabpage = tabpage, workspace = workspace } })
	else
		---@cast active tabterm.Terminal
		local bufnr = ui_state.get_terminal_bufnr(active.id)
		---@cast bufnr integer
		table.insert(commands, {
			types.ui_commands.MOUNT_TERMINAL,
			{
				tabpage = tabpage,
				terminal_id = active.id,
				terminal = active,
				bufnr = bufnr,
			},
		})
	end

	append_dispose_commands(commands, stale_refs)
	append_start_terminal_commands(commands, tabpage, workspace)

	return commands
end

return M
