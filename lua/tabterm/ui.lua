local model = require("tabterm.model")
local shell_integration = require("tabterm.shell_integration")
local state = require("tabterm.state")
local types = require("tabterm.types")
local ui_state = require("tabterm.ui_state")
local util = require("tabterm.util")

local M = {}
local sidebar_ns = vim.api.nvim_create_namespace("tabterm.sidebar")
local panel_placeholder_filetype = "tabterm-panel-placeholder"
local panel_shell_filetype = "tabterm-panel-shell"
local panel_command_filetype = "tabterm-panel-command"

---@class tabterm.FloatLayout
---@field row integer
---@field col integer
---@field total_w integer
---@field total_h integer
---@field sidebar_w integer
---@field panel_w integer
---@field panel_col integer

---@class tabterm.WindowConfig
---@field relative string
---@field row integer
---@field col integer
---@field width integer
---@field height integer
---@field style string
---@field border string?
---@field focusable boolean?
---@field zindex integer?
---@field noautocmd boolean?

---@param winid integer?
local function close_window(winid)
	if util.valid_win(winid) then
		ui_state.set_suppress_winclosed(winid)
		pcall(vim.api.nvim_win_close, winid, true)
		ui_state.clear_suppress_winclosed(winid)
	end
end

---@param ref tabterm.TerminalBufferRef?
local function dispose_terminal_buffer(ref)
	local bufnr = ref and ref.bufnr or nil
	if bufnr then
		ui_state.clear_terminal_buffer(bufnr)
	end
	if ref and ref.terminal_id then
		ui_state.set_terminal_winid(ref.terminal_id, nil)
	end

	if util.valid_buf(bufnr) then
		ui_state.set_suppress_bufdelete(bufnr)
		pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
		ui_state.clear_suppress_bufdelete(bufnr)
	end
end

---@return tabterm.UIConfig
local function config()
	local current = state.config
	---@cast current tabterm.Config
	return current.ui
end

---@return string
local function border()
	return config().border == "round" and "rounded" or config().border
end

---@param name string
---@return integer?
local function hl_fg(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if not ok or type(hl) ~= "table" then
		return nil
	end
	return hl.fg
end

---@param name string
---@return integer?
local function hl_bg(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if not ok or type(hl) ~= "table" then
		return nil
	end
	return hl.bg
end

---@param color any
---@return integer?
---@return integer?
---@return integer?
local function split_rgb(color)
	if type(color) ~= "number" then
		return nil
	end

	local r = math.floor(color / 0x10000) % 0x100
	local g = math.floor(color / 0x100) % 0x100
	local b = color % 0x100
	return r, g, b
end

---@param r integer
---@param g integer
---@param b integer
---@return integer
local function compose_rgb(r, g, b)
	return r * 0x10000 + g * 0x100 + b
end

---@param fg integer?
---@param bg integer?
---@param alpha number
---@return integer?
local function blend_colors(fg, bg, alpha)
	local fr, fg_g, fb = split_rgb(fg)
	local br, bg_g, bb = split_rgb(bg)
	if not fr or not br then
		return fg
	end

	local function blend_channel(foreground, background)
		return math.floor((foreground * alpha) + (background * (1 - alpha)) + 0.5)
	end

	return compose_rgb(blend_channel(fr, br), blend_channel(fg_g, bg_g), blend_channel(fb, bb))
end

---@param base_group string
---@param fallback_group string
---@param alpha number
---@return integer?
local function faded_hl(base_group, fallback_group, alpha)
	local fg = hl_fg(base_group) or hl_fg(fallback_group)
	local bg = hl_bg("Normal") or hl_bg("NormalFloat") or 0x000000
	if not fg then
		return nil
	end
	return blend_colors(fg, bg, alpha)
end

function M.setup_highlights()
	pcall(vim.api.nvim_set_hl, 0, "TabtermSidebarNumberActive", { default = true, link = "CursorLineNr" })
	pcall(vim.api.nvim_set_hl, 0, "TabtermSidebarNumberInactive", { default = true, link = "LineNr" })
	pcall(vim.api.nvim_set_hl, 0, "TabtermSidebarCommand", { default = true, link = "String" })
	pcall(vim.api.nvim_set_hl, 0, "TabtermSidebarCwd", { default = true, link = "Directory" })
	pcall(vim.api.nvim_set_hl, 0, "TabtermPanelHeaderMuted", { default = true, link = "Comment" })
	pcall(vim.api.nvim_set_hl, 0, "TabtermPanelHeaderSuccess", { default = true, link = "DiagnosticOk" })
	pcall(vim.api.nvim_set_hl, 0, "TabtermPanelHeaderUnknown", { default = true, link = "DiagnosticInfo" })
	pcall(vim.api.nvim_set_hl, 0, "TabtermPanelHeaderError", { default = true, link = "DiagnosticError" })
	pcall(vim.api.nvim_set_hl, 0, "TabtermSidebar", { default = true, link = "Normal" })
	pcall(vim.api.nvim_set_hl, 0, "TabtermPanel", { default = true, link = "NormalFloat" })
	vim.api.nvim_set_hl(0, "TabtermSidebarSuccess", {
		default = true,
		link = "DiagnosticOk",
	})
	vim.api.nvim_set_hl(0, "TabtermSidebarUnknown", {
		default = true,
		link = "DiagnosticInfo",
	})
	vim.api.nvim_set_hl(0, "TabtermSidebarLoader", {
		default = true,
		link = "Comment",
	})
	vim.api.nvim_set_hl(0, "TabtermSidebarError", {
		default = true,
		link = "DiagnosticError",
	})
	vim.api.nvim_set_hl(0, "TabtermSidebarCommandFade1", {
		fg = faded_hl("String", "Comment", 0.55),
		italic = false,
	})
	vim.api.nvim_set_hl(0, "TabtermSidebarCommandFade2", {
		fg = faded_hl("String", "NonText", 0.28),
		italic = false,
	})
	vim.api.nvim_set_hl(0, "TabtermSidebarCwdFade1", {
		fg = faded_hl("Directory", "Comment", 0.55),
		italic = false,
	})
	vim.api.nvim_set_hl(0, "TabtermSidebarCwdFade2", {
		fg = faded_hl("Directory", "NonText", 0.28),
		italic = false,
	})
	vim.api.nvim_set_hl(0, "TabtermSidebarHover", {
		default = true,
		link = "Visual",
	})
	pcall(vim.api.nvim_set_hl, 0, "TabtermBackdrop", {
		default = true,
		bg = "#000000",
	})
end

---@return tabterm.FloatLayout
local function float_layout()
	local total_w = math.max(60, math.floor(vim.o.columns * config().float.width))
	local total_h = math.max(12, math.floor(vim.o.lines * config().float.height))
	local row = math.max(1, math.floor((vim.o.lines - total_h) / 2) - 1)
	local col = math.max(0, math.floor((vim.o.columns - total_w) / 2))
	local window_border_extra = border() == "none" and 0 or 2
	local content_budget = math.max(40, total_w - (window_border_extra * 2))
	local sidebar_w = math.min(config().sidebar_width, math.max(20, content_budget - 20))
	local panel_w = math.max(20, content_budget - sidebar_w)
	return {
		row = row,
		col = col,
		total_w = total_w,
		total_h = total_h,
		sidebar_w = sidebar_w,
		panel_w = panel_w,
		panel_col = col + sidebar_w + window_border_extra,
	}
end

---@param layout tabterm.FloatLayout
---@return tabterm.WindowConfig
local function sidebar_win_config(layout)
	return {
		relative = "editor",
		row = layout.row,
		col = layout.col,
		width = layout.sidebar_w,
		height = layout.total_h,
		style = "minimal",
		border = border(),
		zindex = 100,
	}
end

---@param layout tabterm.FloatLayout
---@return tabterm.WindowConfig
local function panel_win_config(layout)
	return {
		relative = "editor",
		row = layout.row,
		col = layout.panel_col,
		width = layout.panel_w,
		height = layout.total_h,
		style = "minimal",
		border = border(),
		zindex = 100,
	}
end

---@param role "sidebar"|"panel"
---@return "TabtermSidebar"|"TabtermPanel"
local function window_highlight_group(role)
	if border() == "none" and role == "sidebar" then
		return "TabtermSidebar"
	end
	return "TabtermPanel"
end

---@param winid integer
---@param role "sidebar"|"panel"
local function apply_window_options(winid, role)
	if not util.valid_win(winid) then
		return
	end

	local group = window_highlight_group(role)
	vim.wo[winid].winhighlight = "Normal:" .. group .. ",NormalFloat:" .. group
	if role == "panel" then
		vim.wo[winid].foldcolumn = border() == "none" and "1" or "0"
	end
end

---@param message any
---@return string
local function single_line_message(message)
	message = tostring(message or "")
	message = message:gsub("\r", " "):gsub("\n+", " "):gsub("%s+", " ")
	return vim.trim(message)
end

---@param terminal tabterm.Terminal
---@return string
local function panel_terminal_filetype(terminal)
	return terminal.spec.kind == "shell" and panel_shell_filetype or panel_command_filetype
end

---@return tabterm.WindowConfig
local function backdrop_win_config()
	return {
		relative = "editor",
		row = 0,
		col = 0,
		width = vim.o.columns,
		height = vim.o.lines,
		style = "minimal",
		focusable = false,
		zindex = 1,
		noautocmd = true,
	}
end

---@param bufnr integer
local function sidebar_keymaps(bufnr)
	local opts = { buffer = bufnr, silent = true, nowait = true }
	local prefix_opts = { buffer = bufnr, silent = true }
	vim.keymap.set("n", "<CR>", function()
		require("tabterm").select_sidebar_cursor()
	end, opts)
	vim.keymap.set("n", "i", function()
		require("tabterm").insert_shell("before")
	end, opts)
	vim.keymap.set("n", "a", function()
		require("tabterm").insert_shell("after")
	end, opts)
	vim.keymap.set("n", "I", function()
		require("tabterm").insert_shell("first")
	end, opts)
	vim.keymap.set("n", "A", function()
		require("tabterm").insert_shell("last")
	end, opts)
	vim.keymap.set("n", "c", "<Nop>", prefix_opts)
	vim.keymap.set("n", "ci", function()
		require("tabterm").insert_command("before")
	end, prefix_opts)
	vim.keymap.set("n", "ca", function()
		require("tabterm").insert_command("after")
	end, prefix_opts)
	vim.keymap.set("n", "cI", function()
		require("tabterm").insert_command("first")
	end, prefix_opts)
	vim.keymap.set("n", "cA", function()
		require("tabterm").insert_command("last")
	end, prefix_opts)
	vim.keymap.set("n", "r", function()
		require("tabterm").rename_sidebar_cursor()
	end, opts)
	vim.keymap.set("n", "d", function()
		require("tabterm").delete_sidebar_cursor()
	end, opts)
	vim.keymap.set("n", "J", function()
		require("tabterm").move_sidebar_cursor(1)
	end, opts)
	vim.keymap.set("n", "K", function()
		require("tabterm").move_sidebar_cursor(-1)
	end, opts)
	vim.keymap.set("n", "q", function()
		require("tabterm").hide()
	end, opts)
	vim.keymap.set("n", "l", function()
		require("tabterm").focus_panel()
	end, opts)
	vim.keymap.set("n", "j", function()
		require("tabterm").sidebar_step(1)
	end, opts)
	vim.keymap.set("n", "k", function()
		require("tabterm").sidebar_step(-1)
	end, opts)
	vim.keymap.set("n", "gg", function()
		local count = vim.v.count > 0 and vim.v.count or 1
		require("tabterm").sidebar_goto(count)
	end, prefix_opts)
	vim.keymap.set("n", "G", function()
		local workspace = require("tabterm.state").get_workspace(require("tabterm.state").current_tabpage(), false)
		local count = vim.v.count > 0 and vim.v.count or (workspace and #workspace.terminal_order or 1)
		require("tabterm").sidebar_goto(count)
	end, opts)
	vim.keymap.set("n", "<Down>", function()
		require("tabterm").sidebar_step(1)
	end, opts)
	vim.keymap.set("n", "<Up>", function()
		require("tabterm").sidebar_step(-1)
	end, opts)
	vim.keymap.set("n", "<C-l>", function()
		require("tabterm").focus_panel()
	end, opts)
	vim.keymap.set("n", "<C-D>", function()
		require("tabterm").scroll_panel("<C-d>")
	end, opts)
	vim.keymap.set("n", "<C-U>", function()
		require("tabterm").scroll_panel("<C-u>")
	end, opts)
	vim.keymap.set("n", "<C-F>", function()
		require("tabterm").scroll_panel("<C-f>")
	end, opts)
	vim.keymap.set("n", "<C-B>", function()
		require("tabterm").scroll_panel("<C-b>")
	end, opts)
end

---@param bufnr integer
local function placeholder_keymaps(bufnr)
	local opts = { buffer = bufnr, silent = true, nowait = true }
	local prefix_opts = { buffer = bufnr, silent = true }
	vim.keymap.set("n", "<CR>", function()
		require("tabterm").start_active()
	end, opts)
	vim.keymap.set("n", "i", function()
		require("tabterm").insert_shell("before")
	end, opts)
	vim.keymap.set("n", "a", function()
		require("tabterm").insert_shell("after")
	end, opts)
	vim.keymap.set("n", "I", function()
		require("tabterm").insert_shell("first")
	end, opts)
	vim.keymap.set("n", "A", function()
		require("tabterm").insert_shell("last")
	end, opts)
	vim.keymap.set("n", "c", "<Nop>", prefix_opts)
	vim.keymap.set("n", "ci", function()
		require("tabterm").insert_command("before")
	end, prefix_opts)
	vim.keymap.set("n", "ca", function()
		require("tabterm").insert_command("after")
	end, prefix_opts)
	vim.keymap.set("n", "cI", function()
		require("tabterm").insert_command("first")
	end, prefix_opts)
	vim.keymap.set("n", "cA", function()
		require("tabterm").insert_command("last")
	end, prefix_opts)
	vim.keymap.set("n", "r", function()
		require("tabterm").rename_active()
	end, opts)
	vim.keymap.set("n", "d", function()
		require("tabterm").delete_active()
	end, opts)
	vim.keymap.set("n", "q", function()
		require("tabterm").hide()
	end, opts)
	vim.keymap.set("n", "<C-h>", function()
		require("tabterm").focus_sidebar()
	end, opts)
end

---@param bufnr integer
local function terminal_keymaps(bufnr)
	local opts = { buffer = bufnr, silent = true, nowait = true }
	vim.keymap.set("n", "<CR>", function()
		require("tabterm").confirm_active_terminal()
	end, opts)
	vim.keymap.set({ "n", "t" }, "<C-h>", function()
		require("tabterm").focus_sidebar()
	end, opts)
end

---@param bufnr integer
---@param filetype string
local function set_scratch_options(bufnr, filetype)
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "hide"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].modifiable = true
	vim.bo[bufnr].filetype = filetype
end

---@param text any
---@return string
local function stl_escape(text)
	text = tostring(text or "")
	text = text:gsub("%%", "%%%%")
	text = text:gsub("[\r\n]", " ")
	text = text:gsub("[%z\1-\31]", "")
	return text
end

---@param terminal tabterm.Terminal?
---@return string
---@return string
local function panel_header_status_hl(terminal)
	local kind = terminal and terminal.snapshot and terminal.snapshot.last_result and terminal.snapshot.last_result.kind
		or "unknown"
	if kind == "success" then
		return "TabtermPanelHeaderSuccess", "success"
	end
	if kind == "error" then
		return "TabtermPanelHeaderError", "error"
	end
	return "TabtermPanelHeaderUnknown", "finished"
end

---@param panel_winid integer?
---@param terminal tabterm.Terminal?
local function set_panel_winbar(panel_winid, terminal)
	if not util.valid_win(panel_winid) then
		return
	end

	if not terminal or terminal.spec.kind ~= "cmd" or terminal.runtime.phase ~= "exited" then
		vim.wo[panel_winid].winbar = ""
		return
	end

	local status_hl, status_text = panel_header_status_hl(terminal)
	local command = stl_escape(model.command_label(terminal))
	local cwd = stl_escape(model.cwd_label(terminal))
	local parts = {
		"%#" .. status_hl .. "# ",
		status_text,
		" %*",
	}

	if command ~= "" then
		table.insert(parts, "%#TabtermSidebarCommand#")
		table.insert(parts, command)
		table.insert(parts, "%*")
	end

	if cwd ~= "" then
		table.insert(parts, "%#TabtermPanelHeaderMuted# in %*")
		table.insert(parts, "%#TabtermSidebarCwd#")
		table.insert(parts, cwd)
		table.insert(parts, "%*")
	end

	table.insert(parts, "%#TabtermPanelHeaderMuted#   <CR> close%*")

	vim.wo[panel_winid].winbar = "%<" .. table.concat(parts)
end

---@param tabpage integer
function M.mount(tabpage)
	local layout = float_layout()
	local ui = ui_state.get(tabpage)

	if not util.valid_buf(ui.backdrop.bufnr) then
		ui.backdrop.bufnr = vim.api.nvim_create_buf(false, true)
		set_scratch_options(ui.backdrop.bufnr, "tabterm-backdrop")
		vim.bo[ui.backdrop.bufnr].modifiable = false
	end

	local backdrop_win = ui.backdrop.winid
	if util.valid_win(backdrop_win) then
		ui_state.set_suppress_winclosed(backdrop_win)
		pcall(vim.api.nvim_win_close, backdrop_win, true)
		ui_state.clear_suppress_winclosed(backdrop_win)
	end

	ui.backdrop.winid = vim.api.nvim_open_win(ui.backdrop.bufnr, false, backdrop_win_config())
	vim.wo[ui.backdrop.winid].winblend = 60
	vim.wo[ui.backdrop.winid].winhighlight = "Normal:TabtermBackdrop"

	if not util.valid_buf(ui.sidebar.bufnr) then
		ui.sidebar.bufnr = vim.api.nvim_create_buf(false, true)
		set_scratch_options(ui.sidebar.bufnr, "tabterm-sidebar")
		sidebar_keymaps(ui.sidebar.bufnr)
	end

	local sidebar_win = ui.sidebar.winid
	if util.valid_win(sidebar_win) then
		ui_state.set_suppress_winclosed(sidebar_win)
		pcall(vim.api.nvim_win_close, sidebar_win, true)
		ui_state.clear_suppress_winclosed(sidebar_win)
	end

	ui.sidebar.winid = vim.api.nvim_open_win(ui.sidebar.bufnr, false, sidebar_win_config(layout))
	apply_window_options(ui.sidebar.winid, "sidebar")

	local panel_buf = ui.panel.bufnr
	if not util.valid_buf(panel_buf) then
		panel_buf = vim.api.nvim_create_buf(false, true)
		---@cast panel_buf integer
		set_scratch_options(panel_buf, panel_placeholder_filetype)
		placeholder_keymaps(panel_buf)
	end
	ui.panel.bufnr = panel_buf

	local panel_win = ui.panel.winid
	if util.valid_win(panel_win) then
		ui_state.set_suppress_winclosed(panel_win)
		pcall(vim.api.nvim_win_close, panel_win, true)
		ui_state.clear_suppress_winclosed(panel_win)
	end

	ui.panel.winid = vim.api.nvim_open_win(panel_buf, false, panel_win_config(layout))
	apply_window_options(ui.panel.winid, "panel")
	ui.panel.kind = "placeholder"
end

---@param tabpage integer
function M.relayout(tabpage)
	local ui = ui_state.get(tabpage)
	if
		not util.valid_win(ui.backdrop.winid)
		or not util.valid_win(ui.sidebar.winid)
		or not util.valid_win(ui.panel.winid)
	then
		M.mount(tabpage)
		return
	end

	local layout = float_layout()
	vim.api.nvim_win_set_config(ui.backdrop.winid, backdrop_win_config())
	vim.api.nvim_win_set_config(ui.sidebar.winid, sidebar_win_config(layout))
	vim.api.nvim_win_set_config(ui.panel.winid, panel_win_config(layout))
	apply_window_options(ui.sidebar.winid, "sidebar")
	apply_window_options(ui.panel.winid, "panel")
end

---@param tabpage integer
function M.unmount(tabpage)
	local ui = ui_state.get(tabpage)
	local windows = {}
	local seen = {}

	for _, winid in ipairs({ ui.backdrop.winid, ui.sidebar.winid, ui.panel.winid }) do
		if util.valid_win(winid) and not seen[winid] then
			seen[winid] = true
			table.insert(windows, winid)
		end
	end

	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		if not seen[winid] then
			-- Legacy: if any other window still carries our buffer, close it.
			-- After full migration this second pass can be removed.
			local bufnr = vim.api.nvim_win_get_buf(winid)
			if bufnr == ui.backdrop.bufnr or bufnr == ui.sidebar.bufnr or bufnr == ui.panel.bufnr then
				seen[winid] = true
				table.insert(windows, winid)
			end
		end
	end

	for _, winid in ipairs(windows) do
		close_window(winid)
	end

	ui_state.reset(tabpage)
end

---@param tabpage integer
function M.ensure_open(tabpage)
	local ui = ui_state.get(tabpage)
	if not util.valid_win(ui.sidebar.winid) or not util.valid_win(ui.panel.winid) then
		M.mount(tabpage)
	end
end

---@param tabpage integer
---@param workspace tabterm.Workspace
function M.render_sidebar(tabpage, workspace)
	local ui = ui_state.get(tabpage)
	if not util.valid_buf(ui.sidebar.bufnr) then
		return
	end

	local width = util.valid_win(ui.sidebar.winid) and vim.api.nvim_win_get_width(ui.sidebar.winid)
		or config().sidebar_width
	local lines, line_map, decorations = model.sidebar_lines(workspace, width)
	ui.sidebar.line_map = line_map

	vim.bo[ui.sidebar.bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(ui.sidebar.bufnr, 0, -1, false, lines)
	vim.bo[ui.sidebar.bufnr].modifiable = false
	vim.api.nvim_buf_clear_namespace(ui.sidebar.bufnr, sidebar_ns, 0, -1)

	for _, decoration in ipairs(decorations) do
		vim.api.nvim_buf_add_highlight(
			ui.sidebar.bufnr,
			sidebar_ns,
			decoration.hl,
			decoration.line,
			decoration.start_col,
			decoration.end_col
		)
	end

	local row = nil
	if util.valid_win(ui.sidebar.winid) then
		local target_row = nil
		local active_terminal_id = workspace.active_terminal_id
		if active_terminal_id then
			for index, id in ipairs(line_map) do
				if id == active_terminal_id then
					target_row = index
					break
				end
			end
		end

		if target_row then
			local current_row = vim.api.nvim_win_get_cursor(ui.sidebar.winid)[1]
			if current_row ~= target_row then
				vim.api.nvim_win_set_cursor(ui.sidebar.winid, { target_row, 0 })
			end
			row = target_row
		else
			row = vim.api.nvim_win_get_cursor(ui.sidebar.winid)[1]
		end
	end

	local terminal_id = row and line_map[row] or nil
	if terminal_id then
		for index, id in ipairs(line_map) do
			if id == terminal_id then
				vim.api.nvim_buf_add_highlight(ui.sidebar.bufnr, sidebar_ns, "TabtermSidebarHover", index - 1, 0, -1)
			end
		end
	end

	if util.valid_win(ui.sidebar.winid) then
		vim.wo[ui.sidebar.winid].cursorline = false
	end
end

---@param tabpage integer
---@param workspace tabterm.Workspace
function M.render_placeholder(tabpage, workspace)
	local ui = ui_state.get(tabpage)
	if not util.valid_win(ui.panel.winid) then
		return
	end

	set_panel_winbar(ui.panel.winid, nil)

	local buf = ui.panel.bufnr
	if not util.valid_buf(buf) or vim.bo[buf].buftype == "terminal" then
		buf = vim.api.nvim_create_buf(false, true)
		---@cast buf integer
		set_scratch_options(buf, panel_placeholder_filetype)
		placeholder_keymaps(buf)
		ui.panel.bufnr = buf
	end
	vim.bo[buf].filetype = panel_placeholder_filetype

	local placeholder = model.placeholder_model(workspace)
	local lines = {
		placeholder.title or "",
	}

	if placeholder.context and placeholder.context ~= "" then
		table.insert(lines, placeholder.context)
	end
	if placeholder.status and placeholder.status ~= "" then
		local detail = placeholder.detail and placeholder.detail ~= "" and ("  " .. placeholder.detail) or ""
		table.insert(lines, placeholder.status .. detail)
	elseif placeholder.detail and placeholder.detail ~= "" then
		table.insert(lines, placeholder.detail)
	end
	if placeholder.hint and placeholder.hint ~= "" then
		table.insert(lines, "")
		table.insert(lines, placeholder.hint)
	end

	vim.api.nvim_win_set_buf(ui.panel.winid, buf)
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.api.nvim_win_set_cursor(ui.panel.winid, { 1, 0 })
end

---@param tabpage integer
---@param workspace tabterm.Workspace
function M.render_panel(tabpage, workspace)
	local ui = ui_state.get(tabpage)
	if ui.panel.kind == "terminal" then
		local terminal = workspace.active_terminal_id and workspace.terminals_by_id[workspace.active_terminal_id] or nil
		local bufnr = terminal and ui_state.get_terminal_bufnr(terminal.id) or nil
		if terminal and util.valid_win(ui.panel.winid) and util.valid_buf(bufnr) then
			ui.panel.bufnr = bufnr
			vim.api.nvim_win_set_buf(ui.panel.winid, bufnr)
			vim.bo[bufnr].bufhidden = "hide"
			set_panel_winbar(ui.panel.winid, terminal)
		end
		return
	end

	M.render_placeholder(tabpage, workspace)
end

---@param tabpage integer
---@param workspace tabterm.Workspace?
function M.refresh(tabpage, workspace)
	local ui = ui_state.get(tabpage)
	if not workspace or not workspace.runtime.visible then
		return
	end

	M.render_sidebar(tabpage, workspace)
	M.render_panel(tabpage, workspace)
end

---@param tabpage integer
---@param terminal tabterm.Terminal
---@return integer? bufnr
---@return integer? channel_id
---@return string? err
---@return integer? failed_bufnr
function M.start_terminal(tabpage, terminal)
	M.ensure_open(tabpage)

	local ui = ui_state.get(tabpage)
	if not util.valid_win(ui.panel.winid) then
		local message = terminal.spec.kind == "shell" and "Terminal panel is unavailable"
			or "Command panel is unavailable"
		return nil, nil, message, nil
	end

	local old_bufnr = ui_state.get_terminal_bufnr(terminal.id)
	if old_bufnr and util.valid_buf(old_bufnr) then
		dispose_terminal_buffer({ terminal_id = terminal.id, bufnr = old_bufnr })
	end

	local bufnr = vim.api.nvim_create_buf(false, true)
	ui.panel.bufnr = bufnr
	vim.bo[bufnr].bufhidden = "hide"
	vim.bo[bufnr].filetype = panel_terminal_filetype(terminal)
	vim.b[bufnr].tabterm_normal_mode_intent = false
	terminal_keymaps(bufnr)
	vim.api.nvim_win_set_buf(ui.panel.winid, bufnr)

	local job_cmd
	local job_env
	if terminal.spec.kind == "shell" then
		job_cmd, job_env = shell_integration.job(terminal)
	else
		job_cmd = { vim.o.shell, "-c", terminal.spec.cmd }
	end

	local ok, channel_id = pcall(vim.api.nvim_buf_call, bufnr, function()
		return vim.fn.jobstart(job_cmd, {
			term = true,
			term_finish = terminal.spec.kind == "cmd" and "open" or nil,
			cwd = terminal.spec.cwd,
			env = job_env,
		})
	end)

	if not ok or type(channel_id) ~= "number" or channel_id <= 0 then
		local message = ok and nil or single_line_message(channel_id)
		if not message or message == "" then
			message = terminal.spec.kind == "shell" and "Failed to start shell" or "Failed to start command"
		end
		if terminal.spec.cwd and terminal.spec.cwd ~= "" then
			message = ("%s in %s"):format(message, terminal.spec.cwd)
		end

		return nil, nil, message, bufnr
	end

	ui_state.set_terminal_buffer(tabpage, terminal.id, bufnr)
	return bufnr, channel_id, nil, nil
end

---@param terminal_refs tabterm.TerminalBufferRef[]?
function M.dispose_terminal_buffers(terminal_refs)
	for _, ref in ipairs(terminal_refs or {}) do
		dispose_terminal_buffer(ref)
	end
end

---@param cmd tabterm.UICommand
function M.execute(cmd)
	local type, args = cmd[1], cmd[2]
	if type == types.ui_commands.MOUNT then
		M.mount(args.tabpage)
	elseif type == types.ui_commands.UNMOUNT then
		M.unmount(args.tabpage)
	elseif type == types.ui_commands.RELAYOUT then
		M.relayout(args.tabpage)
	elseif type == types.ui_commands.RENDER_SIDEBAR then
		M.render_sidebar(args.tabpage, args.workspace)
	elseif type == types.ui_commands.RENDER_PLACEHOLDER then
		M.render_placeholder(args.tabpage, args.workspace)
	elseif type == types.ui_commands.MOUNT_TERMINAL then
		local ui = ui_state.get(args.tabpage)
		if util.valid_win(ui.panel.winid) and util.valid_buf(args.bufnr) then
			ui.panel.bufnr = args.bufnr
			ui.panel.kind = "terminal"
			vim.bo[args.bufnr].filetype = panel_terminal_filetype(args.terminal)
			vim.api.nvim_win_set_buf(ui.panel.winid, args.bufnr)
			vim.bo[args.bufnr].bufhidden = "hide"
			set_panel_winbar(ui.panel.winid, args.terminal)
		end
	elseif type == types.ui_commands.DISPOSE_TERMINAL_BUFFERS then
		M.dispose_terminal_buffers(args.terminal_refs)
	end
end

return M
