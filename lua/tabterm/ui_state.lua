---@alias tabterm.PanelKind "placeholder"|"terminal"
---@alias tabterm.UIRole "backdrop"|"sidebar"|"panel"

---@class tabterm.WindowBufferRef
---@field bufnr integer?
---@field winid integer?

---@class tabterm.SidebarState: tabterm.WindowBufferRef
---@field line_map (string|false)[]

---@class tabterm.PanelState: tabterm.WindowBufferRef
---@field kind tabterm.PanelKind

---@class tabterm.TabUIState
---@field backdrop tabterm.WindowBufferRef
---@field sidebar tabterm.SidebarState
---@field panel tabterm.PanelState

---@class tabterm.TerminalBufferRef
---@field bufnr integer?
---@field tabpage integer?
---@field terminal_id string

---@class tabterm.UIState
---@field by_tabpage table<integer, tabterm.TabUIState>
---@field terminal_bufnr table<integer, tabterm.TerminalBufferRef>
---@field terminal_id_bufnr table<string, integer>
---@field terminal_winid table<string, integer>
---@field suppress_winclosed table<integer, boolean>
---@field suppress_bufdelete table<integer, boolean>
---@field tab_key? fun(tabpage: integer?): integer
---@field get? fun(tabpage: integer?): tabterm.TabUIState
---@field reset? fun(tabpage: integer?)
---@field set_window? fun(tabpage: integer?, role: tabterm.UIRole, winid: integer?)
---@field set_buffer? fun(tabpage: integer?, role: tabterm.UIRole, bufnr: integer?)
---@field set_terminal_buffer? fun(tabpage: integer?, terminal_id: string, bufnr: integer?)
---@field clear_terminal_buffer? fun(bufnr: integer?)
---@field get_terminal_bufnr? fun(terminal_id: string): integer?
---@field lookup_buffer? fun(bufnr: integer?): tabterm.TerminalBufferRef?
---@field terminal_refs_for_tabpage? fun(tabpage: integer?): tabterm.TerminalBufferRef[]
---@field set_terminal_winid? fun(terminal_id: string, winid: integer?)
---@field get_terminal_winid? fun(terminal_id: string): integer?
---@field set_suppress_winclosed? fun(winid: integer?)
---@field clear_suppress_winclosed? fun(winid: integer?)
---@field is_suppress_winclosed? fun(winid: integer?): boolean
---@field set_suppress_bufdelete? fun(bufnr: integer?)
---@field clear_suppress_bufdelete? fun(bufnr: integer?)
---@field is_suppress_bufdelete? fun(bufnr: integer?): boolean
---@field snapshot? fun(tabpage: integer?): tabterm.TabUIState

---@type tabterm.UIState
local M = {
	by_tabpage = {},
	terminal_bufnr = {},
	terminal_id_bufnr = {},
	terminal_winid = {},
	suppress_winclosed = {},
	suppress_bufdelete = {},
}

---@param tabpage integer?
---@return integer
function M.tab_key(tabpage)
	return tabpage or vim.api.nvim_get_current_tabpage()
end

---@param tabpage integer?
---@return tabterm.TabUIState
function M.get(tabpage)
	local key = M.tab_key(tabpage)
	if not M.by_tabpage[key] then
		M.by_tabpage[key] = {
			backdrop = { bufnr = nil, winid = nil },
			sidebar = { bufnr = nil, winid = nil, line_map = {} },
			panel = { kind = "placeholder", bufnr = nil, winid = nil },
		}
	end
	return M.by_tabpage[key]
end

---@param tabpage integer?
function M.reset(tabpage)
	M.by_tabpage[M.tab_key(tabpage)] = nil
end

---@param tabpage integer?
---@param role tabterm.UIRole
---@param winid integer?
function M.set_window(tabpage, role, winid)
	local ui = M.get(tabpage)
	if ui[role] then
		ui[role].winid = winid
	end
end

---@param tabpage integer?
---@param role tabterm.UIRole
---@param bufnr integer?
function M.set_buffer(tabpage, role, bufnr)
	local ui = M.get(tabpage)
	if ui[role] then
		ui[role].bufnr = bufnr
	end
end

---@param tabpage integer?
---@param terminal_id string
---@param bufnr integer?
function M.set_terminal_buffer(tabpage, terminal_id, bufnr)
	if bufnr and bufnr > 0 then
		M.terminal_bufnr[bufnr] = {
			tabpage = M.tab_key(tabpage),
			terminal_id = terminal_id,
		}
		M.terminal_id_bufnr[terminal_id] = bufnr
	end
end

---@param bufnr integer?
function M.clear_terminal_buffer(bufnr)
	if bufnr then
		local ref = M.terminal_bufnr[bufnr]
		if ref then
			M.terminal_bufnr[bufnr] = nil
			M.terminal_id_bufnr[ref.terminal_id] = nil
		end
	end
end

---@param terminal_id string
---@return integer?
function M.get_terminal_bufnr(terminal_id)
	return M.terminal_id_bufnr[terminal_id]
end

---@param bufnr integer?
---@return tabterm.TerminalBufferRef?
function M.lookup_buffer(bufnr)
	return M.terminal_bufnr[bufnr]
end

---@param tabpage integer?
---@return tabterm.TerminalBufferRef[]
function M.terminal_refs_for_tabpage(tabpage)
	local refs = {}
	local key = M.tab_key(tabpage)

	for bufnr, ref in pairs(M.terminal_bufnr) do
		if ref.tabpage == key then
			table.insert(refs, {
				bufnr = bufnr,
				tabpage = ref.tabpage,
				terminal_id = ref.terminal_id,
			})
		end
	end

	table.sort(refs, function(left, right)
		if left.terminal_id == right.terminal_id then
			return left.bufnr < right.bufnr
		end
		return left.terminal_id < right.terminal_id
	end)

	return refs
end

---@param terminal_id string
---@param winid integer?
function M.set_terminal_winid(terminal_id, winid)
	if winid and winid > 0 then
		M.terminal_winid[terminal_id] = winid
	else
		M.terminal_winid[terminal_id] = nil
	end
end

---@param terminal_id string
---@return integer?
function M.get_terminal_winid(terminal_id)
	return M.terminal_winid[terminal_id]
end

---@param winid integer?
function M.set_suppress_winclosed(winid)
	if winid then
		M.suppress_winclosed[winid] = true
	end
end

---@param winid integer?
function M.clear_suppress_winclosed(winid)
	if winid then
		M.suppress_winclosed[winid] = nil
	end
end

---@param winid integer?
---@return boolean
function M.is_suppress_winclosed(winid)
	return winid ~= nil and M.suppress_winclosed[winid] == true
end

---@param bufnr integer?
function M.set_suppress_bufdelete(bufnr)
	if bufnr then
		M.suppress_bufdelete[bufnr] = true
	end
end

---@param bufnr integer?
function M.clear_suppress_bufdelete(bufnr)
	if bufnr then
		M.suppress_bufdelete[bufnr] = nil
	end
end

---@param bufnr integer?
---@return boolean
function M.is_suppress_bufdelete(bufnr)
	return bufnr ~= nil and M.suppress_bufdelete[bufnr] == true
end

---@param tabpage integer?
---@return tabterm.TabUIState
function M.snapshot(tabpage)
	return M.get(tabpage)
end

return M
