local config = require("tabterm.config")
local events = require("tabterm.events")
local model = require("tabterm.model")
local state = require("tabterm.state")
local ui_state = require("tabterm.ui_state")
local types = require("tabterm.types")
local ui = require("tabterm.ui")
local util = require("tabterm.util")

---@alias tabterm.Placement "before"|"after"|"first"|"last"

local M = {}

---@param create boolean?
---@return tabterm.Workspace?
local function current_workspace(create)
	local workspace, _ = state.get_workspace(state.current_tabpage(), create)
	return workspace
end

---@param event tabterm.Event
---@return tabterm.Workspace?
local function dispatch(event)
	M.ensure_setup()
	return events.dispatch(event)
end

local function schedule_checktime()
	vim.schedule(function()
		pcall(vim.cmd, "checktime")
	end)
end

---@param spec tabterm.TerminalSpecInput?
---@return tabterm.TerminalSpec
local function default_shell_spec(spec)
	local normalized = vim.tbl_extend("force", {
		kind = "shell",
		cmd = model.default_shell_cmd(),
		cwd = (vim.uv or vim.loop).cwd() or vim.fn.getcwd(),
	}, spec or {})
	---@cast normalized tabterm.TerminalSpec
	return normalized
end

---@param workspace tabterm.Workspace
local function open_workspace_ui(workspace)
	dispatch({
		type = types.events.WORKSPACE_OPEN_REQUESTED,
		tabpage = workspace.runtime.tabpage,
		payload = { winid = vim.api.nvim_get_current_win() },
	})
end

---@param tabpage integer
---@param spec tabterm.TerminalSpec|tabterm.TerminalSpecInput
---@param opts { to_index: integer? }?
local function create_and_start(tabpage, spec, opts)
	dispatch({
		type = types.events.TERMINAL_CREATE_REQUESTED,
		tabpage = tabpage,
		payload = {
			spec = spec,
			to_index = opts and opts.to_index or nil,
		},
	})

	local workspace = state.get_workspace(tabpage, true)
	if workspace and workspace.active_terminal_id then
		dispatch({
			type = types.events.TERMINAL_START_REQUESTED,
			tabpage = tabpage,
			terminal_id = workspace.active_terminal_id,
		})
	end
end

---@type fun(workspace: tabterm.Workspace?): string?
local sidebar_terminal_id

---@param workspace tabterm.Workspace?
---@param terminal_id string?
---@return integer?
local function terminal_index(workspace, terminal_id)
	if not workspace or not terminal_id then
		return nil
	end

	for index, id in ipairs(workspace.terminal_order) do
		if id == terminal_id then
			return index
		end
	end

	return nil
end

---@param workspace tabterm.Workspace?
---@param placement tabterm.Placement?
---@return integer
local function insertion_index(workspace, placement)
	if not workspace then
		return 1
	end

	if placement == "first" then
		return 1
	end

	if placement == "last" or #workspace.terminal_order == 0 then
		return #workspace.terminal_order + 1
	end

	local anchor = sidebar_terminal_id(workspace) or workspace.active_terminal_id
	local index = terminal_index(workspace, anchor) or #workspace.terminal_order

	if placement == "before" then
		return index
	end

	if placement == "after" then
		return index + 1
	end

	return #workspace.terminal_order + 1
end

---@param workspace tabterm.Workspace
---@param spec tabterm.TerminalSpec|tabterm.TerminalSpecInput
---@param placement tabterm.Placement?
local function create_at(workspace, spec, placement)
	open_workspace_ui(workspace)
	create_and_start(workspace.runtime.tabpage, spec, { to_index = insertion_index(workspace, placement) })
	M.focus_panel()
end

---@param workspace tabterm.Workspace?
local function preserve_tabterm_focus_after_delete(workspace)
	if not workspace or not workspace.runtime.visible or #workspace.terminal_order == 0 then
		state.set_autoclose_suspended(workspace and workspace.runtime and workspace.runtime.tabpage or nil, false)
		return
	end

	vim.defer_fn(function()
		local latest = current_workspace(false)
		if latest and #latest.terminal_order > 0 then
			if not latest.runtime.visible then
				open_workspace_ui(latest)
			end
			M.focus_sidebar()
		end
		state.set_autoclose_suspended(workspace.runtime.tabpage, false)
	end, 20)
end

---@param workspace tabterm.Workspace?
local function move_focus_to_sidebar_before_delete(workspace)
	if not workspace or not workspace.runtime.visible then
		return
	end

	local ui = ui_state.get(workspace.runtime.tabpage)
	local sidebar_win = ui.sidebar.winid
	if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) and vim.api.nvim_get_current_win() ~= sidebar_win then
		vim.api.nvim_set_current_win(sidebar_win)
	end
end

---@param workspace tabterm.Workspace?
local function stabilize_panel_before_delete(workspace)
	if not workspace or not workspace.runtime.visible then
		return
	end

	local ui = ui_state.get(workspace.runtime.tabpage)
	local panel_win = ui.panel.winid
	if not panel_win or not vim.api.nvim_win_is_valid(panel_win) then
		return
	end

	local scratch = vim.api.nvim_create_buf(false, true)
	vim.bo[scratch].buftype = "nofile"
	vim.bo[scratch].bufhidden = "wipe"
	vim.bo[scratch].swapfile = false
	vim.bo[scratch].modifiable = false
	pcall(vim.api.nvim_win_set_buf, panel_win, scratch)
end

---@param terminal tabterm.Terminal?
---@return boolean
local function confirm_delete_terminal(terminal)
	if not terminal or not model.is_waiting(terminal) then
		return true
	end

	local label = model.command_label(terminal)
	local choice = vim.fn.confirm(("Delete running terminal '%s'?"):format(label), "&Delete\n&Cancel", 2)

	return choice == 1
end

---@param workspace tabterm.Workspace?
---@param terminal_id string?
local function delete_terminal(workspace, terminal_id)
	if not workspace or not terminal_id then
		return
	end

	local terminal = workspace.terminals_by_id[terminal_id]
	if not terminal or not confirm_delete_terminal(terminal) then
		return
	end

	local should_preserve_focus = workspace.runtime.visible
		and terminal_id == workspace.active_terminal_id
		and #workspace.terminal_order > 1

	if should_preserve_focus then
		state.set_autoclose_suspended(workspace.runtime.tabpage, true)
		move_focus_to_sidebar_before_delete(workspace)
		stabilize_panel_before_delete(workspace)
	end

	dispatch({
		type = types.events.TERMINAL_DELETE_REQUESTED,
		tabpage = workspace.runtime.tabpage,
		terminal_id = terminal_id,
	})

	local latest = state.get_workspace(workspace.runtime.tabpage, false)
	if latest and #latest.terminal_order == 0 and latest.runtime.visible then
		dispatch({
			type = types.events.WORKSPACE_CLOSE_REQUESTED,
			tabpage = latest.runtime.tabpage,
		})
		return
	end

	if should_preserve_focus then
		preserve_tabterm_focus_after_delete(workspace)
	end
end

---@param workspace tabterm.Workspace?
---@return tabterm.Terminal?
local function active_terminal(workspace)
	return workspace and workspace.active_terminal_id and workspace.terminals_by_id[workspace.active_terminal_id] or nil
end

---@param terminal tabterm.Terminal?
---@return integer?
local function terminal_bufnr(terminal)
	return terminal and ui_state.get_terminal_bufnr(terminal.id) or nil
end

---@param terminal tabterm.Terminal?
---@return boolean
local function has_normal_mode_intent(terminal)
	local bufnr = terminal_bufnr(terminal)
	return util.valid_buf(bufnr) and vim.b[bufnr].tabterm_normal_mode_intent == true
end

---@param terminal tabterm.Terminal?
---@param value boolean
local function set_normal_mode_intent(terminal, value)
	local bufnr = terminal_bufnr(terminal)
	if util.valid_buf(bufnr) then
		vim.b[bufnr].tabterm_normal_mode_intent = value
	end
end

---@param workspace tabterm.Workspace?
---@return string?
sidebar_terminal_id = function(workspace)
	if not workspace or not workspace.runtime.visible then
		return nil
	end

	local ui = ui_state.get(workspace.runtime.tabpage)
	if not ui.sidebar.winid then
		return nil
	end

	local row = vim.api.nvim_win_get_cursor(ui.sidebar.winid)[1]
	return ui.sidebar.line_map[row] or nil
end

---@param workspace tabterm.Workspace?
---@param terminal_id string?
---@return integer?
local function sidebar_row_for_terminal(workspace, terminal_id)
	if not workspace or not terminal_id then
		return nil
	end

	local ui = ui_state.get(workspace.runtime.tabpage)
	for row, id in ipairs(ui.sidebar.line_map or {}) do
		if id == terminal_id then
			return row
		end
	end

	return nil
end

---@param workspace tabterm.Workspace?
---@param delta integer
---@return integer?
local function sidebar_target_row(workspace, delta)
	if not workspace or not workspace.runtime.visible then
		return nil
	end

	local ui = ui_state.get(workspace.runtime.tabpage)
	if not ui.sidebar.winid then
		return nil
	end

	local line_map = ui.sidebar.line_map or {}
	local row = vim.api.nvim_win_get_cursor(ui.sidebar.winid)[1]
	local current_id = line_map[row]
	if not current_id then
		return nil
	end

	if delta > 0 then
		for index = row + 1, #line_map do
			if line_map[index] and line_map[index] ~= current_id then
				return index
			end
		end
	else
		for index = row - 1, 1, -1 do
			if line_map[index] and line_map[index] ~= current_id then
				local target_id = line_map[index]
				while index > 1 and line_map[index - 1] == target_id do
					index = index - 1
				end
				return index
			end
		end
	end

	return row
end

---@param opts tabterm.ConfigInput?
---@return table
function M.setup(opts)
	state.config = config.merge(opts)
	ui.setup_highlights()

	if not state.initialized then
		events.setup_autocmds()
		state.initialized = true
	end

	return M
end

function M.ensure_setup()
	if not state.initialized then
		M.setup({})
	end
end

function M.open()
	local workspace = current_workspace(true)
	---@cast workspace tabterm.Workspace
	open_workspace_ui(workspace)
	if #workspace.terminal_order == 0 then
		create_and_start(workspace.runtime.tabpage, default_shell_spec())
	end
	M.focus_panel()
end

function M.close()
	local workspace = current_workspace(false)
	if not workspace then
		return
	end
	dispatch({ type = types.events.WORKSPACE_CLOSE_REQUESTED, tabpage = workspace.runtime.tabpage })
end

function M.hide()
	local workspace = current_workspace(false)
	if not workspace then
		return
	end

	local ui = ui_state.get(workspace.runtime.tabpage)
	local restore_win = workspace.runtime.last_editor_winid
	local was_visible = workspace.runtime.visible
	M.close()

	if
		restore_win
		and vim.api.nvim_win_is_valid(restore_win)
		and restore_win ~= ui.sidebar.winid
		and restore_win ~= ui.panel.winid
		and restore_win ~= ui.backdrop.winid
	then
		pcall(vim.api.nvim_set_current_win, restore_win)
	end

	if was_visible then
		schedule_checktime()
	end
end

function M.toggle()
	local workspace = current_workspace(true)
	---@cast workspace tabterm.Workspace
	local was_visible = workspace.runtime.visible
	if was_visible then
		M.hide()
		return
	end

	open_workspace_ui(workspace)
	if #workspace.terminal_order == 0 then
		create_and_start(workspace.runtime.tabpage, default_shell_spec())
	end
	M.focus_panel()
end

---@param spec tabterm.TerminalSpecInput?
function M.new_shell(spec)
	local workspace = current_workspace(true)
	---@cast workspace tabterm.Workspace
	create_at(workspace, default_shell_spec(spec), "last")
end

---@param placement tabterm.Placement?
---@param spec tabterm.TerminalSpecInput?
function M.insert_shell(placement, spec)
	local workspace = current_workspace(true)
	---@cast workspace tabterm.Workspace
	create_at(workspace, default_shell_spec(spec), placement)
end

---@param cmd string?
function M.new_command(cmd)
	return M.insert_command("last", cmd)
end

---@param placement tabterm.Placement?
---@param cmd string?
function M.insert_command(placement, cmd)
	local workspace = current_workspace(true)
	---@cast workspace tabterm.Workspace

	local create = function(value)
		value = tostring(value or "")
		if value == "" then
			return
		end

		create_at(workspace, {
			kind = "cmd",
			cmd = value,
			cwd = (vim.uv or vim.loop).cwd() or vim.fn.getcwd(),
		}, placement)
	end

	if cmd then
		create(cmd)
		return
	end

	vim.ui.input({ prompt = "Command: " }, create)
end

function M.start_active()
	local workspace = current_workspace(true)
	---@cast workspace tabterm.Workspace
	if not workspace.active_terminal_id then
		M.new_shell()
		return
	end

	open_workspace_ui(workspace)
	dispatch({
		type = types.events.TERMINAL_START_REQUESTED,
		tabpage = workspace.runtime.tabpage,
		terminal_id = workspace.active_terminal_id,
	})
	M.focus_panel()
end

function M.confirm_active_terminal()
	local workspace = current_workspace(false)
	local terminal = active_terminal(workspace)
	if not workspace or not terminal then
		return
	end

	if terminal.spec.kind == "cmd" and terminal.runtime.phase == "exited" then
		delete_terminal(workspace, terminal.id)
		return
	end

	if terminal.runtime.phase == "live" then
		vim.cmd("startinsert")
		return
	end

	if terminal.runtime.phase == "stopped" or terminal.runtime.phase == "exited" then
		M.start_active()
	end
end

---@param name_override string?
function M.rename_active(name_override)
	local workspace = current_workspace(false)
	local terminal_id = workspace and workspace.active_terminal_id or nil
	if not workspace or not terminal_id then
		return
	end

	local apply_name = function(value)
		dispatch({
			type = types.events.TERMINAL_RENAME_REQUESTED,
			tabpage = workspace.runtime.tabpage,
			terminal_id = terminal_id,
			payload = { name_override = value ~= "" and value or nil },
		})
	end

	if name_override ~= nil then
		apply_name(name_override)
		return
	end

	local terminal = workspace.terminals_by_id[terminal_id]
	vim.ui.input({ prompt = "Terminal name: ", default = terminal.spec.name_override or "" }, function(value)
		if value ~= nil then
			apply_name(value)
		end
	end)
end

function M.delete_active()
	local workspace = current_workspace(false)
	if not workspace or not workspace.active_terminal_id then
		return
	end

	delete_terminal(workspace, workspace.active_terminal_id)
end

function M.next_terminal()
	local workspace = current_workspace(false)
	if not workspace then
		return
	end
	M.open()
	dispatch({ type = types.events.TERMINAL_NEXT_REQUESTED, tabpage = workspace.runtime.tabpage })
end

function M.prev_terminal()
	local workspace = current_workspace(false)
	if not workspace then
		return
	end
	M.open()
	dispatch({ type = types.events.TERMINAL_PREV_REQUESTED, tabpage = workspace.runtime.tabpage })
end

function M.select_sidebar_cursor()
	local workspace = current_workspace(false)
	local terminal_id = sidebar_terminal_id(workspace)
	if not workspace or not terminal_id then
		return
	end

	dispatch({
		type = types.events.TERMINAL_SELECT_REQUESTED,
		tabpage = workspace.runtime.tabpage,
		terminal_id = terminal_id,
	})
end

function M.rename_sidebar_cursor()
	local workspace = current_workspace(false)
	local terminal_id = sidebar_terminal_id(workspace)
	if not workspace or not terminal_id then
		return
	end
	dispatch({
		type = types.events.TERMINAL_SELECT_REQUESTED,
		tabpage = workspace.runtime.tabpage,
		terminal_id = terminal_id,
	})
	M.rename_active()
end

function M.delete_sidebar_cursor()
	local workspace = current_workspace(false)
	local terminal_id = sidebar_terminal_id(workspace)
	if not workspace or not terminal_id then
		return
	end

	delete_terminal(workspace, terminal_id)
end

---@param delta integer
function M.move_sidebar_cursor(delta)
	local workspace = current_workspace(false)
	local terminal_id = sidebar_terminal_id(workspace)
	if not workspace or not terminal_id then
		return
	end

	local current_index = 1
	for index, id in ipairs(workspace.terminal_order) do
		if id == terminal_id then
			current_index = index
			break
		end
	end

	dispatch({
		type = types.events.TERMINAL_MOVE_REQUESTED,
		tabpage = workspace.runtime.tabpage,
		terminal_id = terminal_id,
		payload = { to_index = current_index + delta },
	})
end

---@param delta integer
function M.sidebar_step(delta)
	local workspace = current_workspace(false)
	local row = sidebar_target_row(workspace, delta)
	local ui = ui_state.get(workspace and workspace.runtime and workspace.runtime.tabpage or nil)
	if not workspace or not row or not vim.api.nvim_win_is_valid(ui.sidebar.winid) then
		return
	end

	vim.api.nvim_win_set_cursor(ui.sidebar.winid, { row, 0 })
end

---@param index integer|string?
function M.sidebar_goto(index)
	local workspace = current_workspace(false)
	local ui = ui_state.get(workspace and workspace.runtime and workspace.runtime.tabpage or nil)
	if not workspace or not workspace.runtime.visible or not vim.api.nvim_win_is_valid(ui.sidebar.winid) then
		return
	end

	if #workspace.terminal_order == 0 then
		return
	end

	index = math.max(1, math.min(#workspace.terminal_order, tonumber(index) or 1))
	local terminal_id = workspace.terminal_order[index]
	local row = sidebar_row_for_terminal(workspace, terminal_id)
	if not row then
		return
	end

	vim.api.nvim_win_set_cursor(ui.sidebar.winid, { row, 0 })

	if workspace.active_terminal_id ~= terminal_id then
		dispatch({
			type = types.events.TERMINAL_SELECT_REQUESTED,
			tabpage = workspace.runtime.tabpage,
			terminal_id = terminal_id,
		})
	end
end

function M.sync_sidebar_cursor()
	local workspace = current_workspace(false)
	local terminal_id = sidebar_terminal_id(workspace)
	if not workspace or not terminal_id or workspace.active_terminal_id == terminal_id then
		return
	end

	dispatch({
		type = types.events.TERMINAL_SELECT_REQUESTED,
		tabpage = workspace.runtime.tabpage,
		terminal_id = terminal_id,
	})
end

function M.focus_sidebar()
	local workspace = current_workspace(false)
	local ui = ui_state.get(workspace and workspace.runtime and workspace.runtime.tabpage or nil)
	if not workspace or not workspace.runtime.visible or not ui.sidebar.winid then
		return
	end

	if vim.api.nvim_win_is_valid(ui.sidebar.winid) then
		local row = sidebar_row_for_terminal(workspace, workspace.active_terminal_id)
		if row then
			vim.api.nvim_win_set_cursor(ui.sidebar.winid, { row, 0 })
		end
		vim.api.nvim_set_current_win(ui.sidebar.winid)
	end
end

function M.focus_panel()
	local workspace = current_workspace(false)
	if not workspace or not workspace.runtime.visible then
		return
	end

	local tabpage = workspace.runtime.tabpage
	local ui = ui_state.get(tabpage)
	if not util.valid_win(ui.panel.winid) then
		return
	end

	local terminal = workspace.active_terminal_id and workspace.terminals_by_id[workspace.active_terminal_id] or nil
	if terminal then
		dispatch({
			type = types.events.TERMINAL_READ_REQUESTED,
			tabpage = tabpage,
			terminal_id = terminal.id,
		})
	end

	if vim.api.nvim_win_is_valid(ui.panel.winid) then
		vim.api.nvim_set_current_win(ui.panel.winid)

		if
			ui.panel.kind == "terminal"
			and terminal
			and terminal.spec.kind == "shell"
			and terminal.runtime.phase == "live"
			and not has_normal_mode_intent(terminal)
		then
			vim.cmd("startinsert")
		elseif
			ui.panel.kind == "terminal"
			and terminal
			and terminal.spec.kind == "cmd"
			and terminal.runtime.phase == "exited"
		then
			vim.cmd("stopinsert")
		end
	end
end

---@param keys string
function M.scroll_panel(keys)
	local workspace = current_workspace(false)
	if not workspace or not workspace.runtime.visible then
		return
	end

	local ui = ui_state.get(workspace.runtime.tabpage)
	if not util.valid_win(ui.panel.winid) then
		return
	end

	local terminal = active_terminal(workspace)
	if ui.panel.kind == "terminal" then
		set_normal_mode_intent(terminal, true)
	end

	vim.api.nvim_win_call(ui.panel.winid, function()
		local termcodes = vim.api.nvim_replace_termcodes(keys, true, false, true)
		vim.cmd.normal({ termcodes, bang = true })
	end)
end

return M
