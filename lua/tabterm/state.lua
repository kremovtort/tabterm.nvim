---@class tabterm.PendingTerminalDispose
---@field terminal_id string
---@field keep_open boolean
---@field panel_winid integer?

---@class tabterm.State
---@field initialized boolean
---@field config tabterm.Config?
---@field workspaces_by_tab table<integer, tabterm.Workspace>
---@field refresh_scheduled table<integer, boolean>
---@field suspend_autoclose_by_tab table<integer, boolean>
---@field pending_terminal_dispose table<integer, tabterm.PendingTerminalDispose>
---@field spinner_frames string[]
---@field spinner_frame_index integer
---@field spinner_interval integer
---@field spinner_timer any
---@field augroup integer?
---@field current_tabpage? fun(): integer
---@field tab_key? fun(tabpage: integer?): integer
---@field get_workspace? fun(tabpage: integer?, create: boolean?): tabterm.Workspace?, integer
---@field set_workspace? fun(tabpage: integer?, workspace: tabterm.Workspace?)
---@field set_autoclose_suspended? fun(tabpage: integer?, suspended: boolean)
---@field is_autoclose_suspended? fun(tabpage: integer?): boolean
---@field current_spinner_frame? fun(): string
---@field advance_spinner_frame? fun(): string
---@field reset_spinner_frame? fun()

---@type tabterm.State
local M = {
	initialized = false,
	config = nil,
	workspaces_by_tab = {},
	refresh_scheduled = {},
	suspend_autoclose_by_tab = {},
	pending_terminal_dispose = {},
	spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
	spinner_frame_index = 1,
	spinner_interval = 100,
	spinner_timer = nil,
}

---@return integer
function M.current_tabpage()
	return vim.api.nvim_get_current_tabpage()
end

---@param tabpage integer?
---@return integer
function M.tab_key(tabpage)
	return tabpage or M.current_tabpage()
end

---@param tabpage integer?
---@param create boolean?
---@return tabterm.Workspace?
---@return integer key
function M.get_workspace(tabpage, create)
	local key = M.tab_key(tabpage)
	local workspace = M.workspaces_by_tab[key]

	if not workspace and create then
		workspace = require("tabterm.model").new_workspace(key)
		M.workspaces_by_tab[key] = workspace
	end

	return workspace, key
end

---@param tabpage integer?
---@param workspace tabterm.Workspace?
function M.set_workspace(tabpage, workspace)
	M.workspaces_by_tab[M.tab_key(tabpage)] = workspace
end

---@param tabpage integer?
---@param suspended boolean
function M.set_autoclose_suspended(tabpage, suspended)
	local key = M.tab_key(tabpage)
	if suspended then
		M.suspend_autoclose_by_tab[key] = true
	else
		M.suspend_autoclose_by_tab[key] = nil
	end
end

---@param tabpage integer?
---@return boolean
function M.is_autoclose_suspended(tabpage)
	return M.suspend_autoclose_by_tab[M.tab_key(tabpage)] == true
end

---@return string
function M.current_spinner_frame()
	return M.spinner_frames[M.spinner_frame_index] or M.spinner_frames[1] or "…"
end

---@return string
function M.advance_spinner_frame()
	local count = #M.spinner_frames
	if count == 0 then
		return M.current_spinner_frame()
	end
	M.spinner_frame_index = (M.spinner_frame_index % count) + 1
	return M.current_spinner_frame()
end

function M.reset_spinner_frame()
	M.spinner_frame_index = 1
end

return M
