local M = {}

---@alias tabterm.TerminalKind "shell"|"cmd"
---@alias tabterm.TerminalPhase "stopped"|"starting"|"live"|"exited"
---@alias tabterm.CommandPhase "unknown"|"prompt"|"editing"|"running"
---@alias tabterm.IntegrationKind "none"|"prompt_only"|"rich"
---@alias tabterm.ResultKind "unknown"|"success"|"error"
---@alias tabterm.ResultSource "unknown"|"process"|"shell"
---@alias tabterm.NotificationKind "unknown"|"success"|"error"

---@class tabterm.WorkspaceRuntime
---@field tabpage integer
---@field visible boolean
---@field last_editor_winid integer?
---@field next_terminal_seq integer

---@class tabterm.Workspace
---@field active_terminal_id string?
---@field terminal_order string[]
---@field terminals_by_id table<string, tabterm.Terminal>
---@field runtime tabterm.WorkspaceRuntime

---@class tabterm.TerminalSpec
---@field kind tabterm.TerminalKind
---@field cmd string
---@field cwd string
---@field name_override string?
---@field title string?

---@class tabterm.TerminalSpecInput
---@field kind tabterm.TerminalKind?
---@field cmd string?
---@field cwd string?
---@field name_override string?
---@field title string?

---@class tabterm.TerminalLastResult
---@field kind tabterm.ResultKind
---@field code integer?
---@field source tabterm.ResultSource

---@class tabterm.TerminalNotification
---@field unread boolean
---@field kind tabterm.NotificationKind
---@field line string?

---@class tabterm.TerminalSnapshot
---@field title string?
---@field cwd string
---@field last_result tabterm.TerminalLastResult
---@field last_output_line string?
---@field notification tabterm.TerminalNotification

---@class tabterm.TerminalCommandRuntime
---@field integration tabterm.IntegrationKind
---@field phase tabterm.CommandPhase

---@class tabterm.TerminalRuntime
---@field phase tabterm.TerminalPhase
---@field channel_id integer?
---@field command tabterm.TerminalCommandRuntime

---@class tabterm.Terminal
---@field id string
---@field spec tabterm.TerminalSpec
---@field snapshot tabterm.TerminalSnapshot
---@field runtime tabterm.TerminalRuntime

---@class tabterm.SidebarDecoration
---@field line integer
---@field start_col integer
---@field end_col integer
---@field hl string

---@class tabterm.SidebarBadge
---@field text string
---@field hl string

---@class tabterm.PlaceholderModel
---@field kind "empty"|"inconsistent"|"stopped"|"exited"
---@field title string
---@field context string?
---@field status string?
---@field detail string?
---@field hint string

local TERMINAL_ICON = " "
local DIRECTORY_ICON = " "

---@param path any
---@return string
local function tail(path)
	path = tostring(path or "")
	if path == "" then
		return ""
	end
	return vim.fn.fnamemodify(path, ":t")
end

---@param title any
---@param fallback_cmd any
---@param cwd_tail string
---@return string
local function normalize_title(title, fallback_cmd, cwd_tail)
	title = tostring(title or "")

	if title == "" then
		title = tostring(fallback_cmd or "")
	end

	if cwd_tail ~= "" and (title == cwd_tail or title:find(cwd_tail, 1, true)) then
		title = tail(vim.env.SHELL or "")
	end

	if title:sub(1, 5) == "/nix/" then
		title = tail(title)
	end

	if title == "" then
		title = "term"
	end

	return title
end

---@param path any
---@return string
local function strip_trailing_slash(path)
	path = tostring(path or "")
	if path == "/" then
		return path
	end
	return (path:gsub("/+$", ""))
end

---@param tabpage integer
---@return string
local function effective_tabpage_cwd(tabpage)
	local ok, cwd = pcall(vim.api.nvim_tabpage_call, tabpage, function()
		return strip_trailing_slash((vim.uv or vim.loop).cwd() or vim.fn.getcwd())
	end)
	if ok then
		return cwd
	end
	return strip_trailing_slash((vim.uv or vim.loop).cwd() or vim.fn.getcwd())
end

---@param text any
---@param max_width integer?
---@return string, boolean
local function truncate_display(text, max_width)
	text = tostring(text or "")
	max_width = math.max(0, max_width or 0)
	if max_width == 0 or text == "" then
		return "", false
	end

	if vim.fn.strdisplaywidth(text) <= max_width then
		return text, false
	end

	local chars = vim.fn.strchars(text)
	while chars > 0 do
		local candidate = vim.fn.strcharpart(text, 0, chars)
		if vim.fn.strdisplaywidth(candidate) <= max_width then
			return candidate, true
		end
		chars = chars - 1
	end

	return "", true
end

---@param text any
---@param width integer?
---@return string
local function pad_display_right(text, width)
	text = tostring(text or "")
	width = math.max(0, width or 0)
	local display_width = vim.fn.strdisplaywidth(text)
	if display_width >= width then
		return text
	end
	return text .. string.rep(" ", width - display_width)
end

---@param path any
---@param max_width integer
---@return string
local function maybe_shorten_path(path, max_width)
	path = tostring(path or "")
	if path == "" then
		return ""
	end

	if vim.fn.strdisplaywidth(path) <= max_width then
		return path
	end

	local is_absolute = path:sub(1, 1) == "/"
	local parts = vim.split(path, "/", { plain = true, trimempty = true })
	if #parts <= 1 then
		return path
	end

	for index = 1, #parts - 1 do
		local part = parts[index]
		if part ~= "" then
			parts[index] = vim.fn.strcharpart(part, 0, 1)
		end
	end

	local shortened = table.concat(parts, "/")
	if is_absolute then
		shortened = "/" .. shortened
	end
	return shortened
end

---@param tabpage integer
---@return tabterm.Workspace
function M.new_workspace(tabpage)
	return {
		active_terminal_id = nil,
		terminal_order = {},
		terminals_by_id = {},
		runtime = {
			tabpage = tabpage,
			visible = false,
			last_editor_winid = nil,
			next_terminal_seq = 1,
		},
	}
end

---@param id string
---@param spec tabterm.TerminalSpecInput?
---@return tabterm.Terminal
function M.new_terminal(id, spec)
	spec = spec or {}
	local kind = spec.kind == "cmd" and "cmd" or "shell"
	local cmd = spec.cmd or (kind == "shell" and (vim.env.SHELL or vim.o.shell or "sh") or "")
	local cwd = spec.cwd or (vim.uv or vim.loop).cwd() or vim.fn.getcwd()

	return {
		id = id,
		spec = {
			kind = kind,
			cmd = cmd,
			cwd = cwd,
			name_override = spec.name_override,
		},
		snapshot = {
			title = spec.title,
			cwd = cwd,
			last_result = {
				kind = "unknown",
				code = nil,
				source = "unknown",
			},
			last_output_line = nil,
			notification = {
				unread = false,
				kind = "unknown",
				line = nil,
			},
		},
		runtime = {
			phase = "stopped",
			channel_id = nil,
			command = {
				integration = "none",
				phase = "unknown",
			},
		},
	}
end

---@return string
local function default_shell_cmd()
	return vim.env.SHELL or vim.o.shell or "sh"
end

---@return string
local function default_cwd()
	return (vim.uv or vim.loop).cwd() or vim.fn.getcwd()
end

---@param id string
---@param terminal tabterm.Terminal?
---@return tabterm.Terminal
function M.ensure_terminal_shape(id, terminal)
	if not terminal then
		terminal = M.new_terminal(id, {})
	end

	terminal.id = id

	terminal.spec = terminal.spec or {}
	terminal.spec.kind = terminal.spec.kind == "cmd" and "cmd" or "shell"
	if terminal.spec.cmd == nil then
		terminal.spec.cmd = terminal.spec.kind == "shell" and default_shell_cmd() or ""
	end
	if not terminal.spec.cwd or terminal.spec.cwd == "" then
		terminal.spec.cwd = default_cwd()
	end

	terminal.snapshot = terminal.snapshot or {}
	terminal.snapshot.last_output_line = terminal.snapshot.last_output_line or nil
	terminal.snapshot.cwd = terminal.snapshot.cwd and terminal.snapshot.cwd ~= "" and terminal.snapshot.cwd
		or terminal.spec.cwd
	terminal.snapshot.last_result = terminal.snapshot.last_result or {}
	if terminal.snapshot.last_result.kind == nil then
		terminal.snapshot.last_result.kind = "unknown"
	end
	if terminal.snapshot.last_result.code == nil then
		terminal.snapshot.last_result.code = nil
	end
	if terminal.snapshot.last_result.source == nil then
		terminal.snapshot.last_result.source = "unknown"
	end
	terminal.snapshot.notification = terminal.snapshot.notification or {}
	if terminal.snapshot.notification.unread == nil then
		terminal.snapshot.notification.unread = false
	end
	if terminal.snapshot.notification.kind == nil then
		terminal.snapshot.notification.kind = "unknown"
	end
	if terminal.snapshot.notification.line == nil then
		terminal.snapshot.notification.line = nil
	end

	terminal.runtime = terminal.runtime or {}
	if terminal.runtime.phase == nil then
		terminal.runtime.phase = "stopped"
	end
	if terminal.runtime.channel_id == nil then
		terminal.runtime.channel_id = nil
	end
	terminal.runtime.command = terminal.runtime.command or {}
	if terminal.runtime.command.integration == nil then
		terminal.runtime.command.integration = "none"
	end
	if terminal.runtime.command.phase == nil then
		terminal.runtime.command.phase = "unknown"
	end

	return terminal
end

---@param terminal tabterm.Terminal?
---@return string
function M.display_name(terminal)
	if not terminal then
		return "term"
	end

	if terminal.spec.name_override and terminal.spec.name_override ~= "" then
		return terminal.spec.name_override
	end

	local cwd_tail = tail(terminal.snapshot.cwd or terminal.spec.cwd)
	local title = normalize_title(terminal.snapshot.title, terminal.spec.cmd, cwd_tail)

	if cwd_tail ~= "" then
		return cwd_tail .. " " .. title
	end

	return title
end

---@param terminal tabterm.Terminal?
---@return string
function M.context_line(terminal)
	if not terminal then
		return ""
	end

	local cwd_tail = tail(terminal.snapshot.cwd or terminal.spec.cwd)
	local cmd = tostring(terminal.spec.cmd or "")

	if cmd:sub(1, 5) == "/nix/" then
		cmd = tail(cmd)
	end

	if cwd_tail ~= "" and cmd ~= "" then
		return cwd_tail .. "  " .. cmd
	end
	if cwd_tail ~= "" then
		return cwd_tail
	end
	return cmd
end

---@param terminal tabterm.Terminal?
---@return string
function M.command_label(terminal)
	if not terminal then
		return "term"
	end

	if terminal.spec.name_override and terminal.spec.name_override ~= "" then
		return terminal.spec.name_override
	end

	if terminal.spec.kind == "shell" then
		local cwd_tail = tail(terminal.snapshot.cwd or terminal.spec.cwd)
		return normalize_title(terminal.snapshot.title, terminal.spec.cmd, cwd_tail)
	end

	local cmd = tostring(terminal.spec.cmd or "")
	if cmd == "" then
		return "term"
	end

	if cmd:sub(1, 5) == "/nix/" then
		return tail(cmd)
	end

	if not cmd:find(" ", 1, true) and cmd:find("/", 1, true) then
		return tail(cmd)
	end

	return cmd
end

---@param terminal tabterm.Terminal?
---@return string
function M.cwd_label(terminal)
	if not terminal then
		return ""
	end

	return tostring(terminal.snapshot.cwd or terminal.spec.cwd or "")
end

---@param workspace tabterm.Workspace?
---@param terminal tabterm.Terminal
---@param max_width integer
---@return string, boolean
local function format_cwd_label(workspace, terminal, max_width)
	local cwd = strip_trailing_slash(M.cwd_label(terminal))
	if cwd == "" then
		return "", false
	end

	local base = workspace
			and workspace.runtime
			and workspace.runtime.tabpage
			and effective_tabpage_cwd(workspace.runtime.tabpage)
		or strip_trailing_slash((vim.uv or vim.loop).cwd() or vim.fn.getcwd())

	if base ~= "" then
		if cwd == base then
			cwd = "-/"
		elseif cwd:sub(1, #base + 1) == base .. "/" then
			cwd = "-/" .. cwd:sub(#base + 2)
		end
	end

	if cwd ~= "-/" then
		cwd = strip_trailing_slash(cwd)
	end
	if cwd == "" then
		cwd = tail(base)
	end

	cwd = maybe_shorten_path(cwd, max_width)
	return truncate_display(cwd, max_width)
end

---@param terminal tabterm.Terminal?
---@return boolean
function M.is_waiting(terminal)
	if not terminal or terminal.runtime.phase ~= "live" then
		return false
	end

	if terminal.spec.kind == "cmd" then
		return true
	end

	return terminal.runtime.command.phase == "running"
end

---@param terminal tabterm.Terminal?
---@return string
function M.result_label(terminal)
	if M.is_waiting(terminal) then
		return "waiting"
	end

	local result = terminal and terminal.snapshot and terminal.snapshot.last_result or nil
	local kind = result and result.kind or "unknown"

	if kind == "success" then
		return "success"
	end
	if kind == "error" then
		return "error"
	end
	if terminal and terminal.runtime.phase == "stopped" then
		return "not started"
	end
	if terminal and terminal.runtime.phase == "exited" then
		return "finished"
	end
	return "unknown"
end

---@param terminal tabterm.Terminal?
---@return tabterm.SidebarBadge?
function M.sidebar_badge(terminal)
	if not terminal then
		return nil
	end

	if M.is_waiting(terminal) then
		local spinner = require("tabterm.state").current_spinner_frame()
		return {
			text = spinner,
			hl = "TabtermSidebarLoader",
		}
	end

	local notification = terminal.snapshot and terminal.snapshot.notification or nil
	if not notification or not notification.unread then
		return nil
	end

	if notification.kind == "error" then
		return {
			text = "●",
			hl = "TabtermSidebarError",
		}
	end

	if notification.kind == "success" then
		return {
			text = "●",
			hl = "TabtermSidebarSuccess",
		}
	end

	return {
		text = "●",
		hl = "TabtermSidebarUnknown",
	}
end

---@param terminal tabterm.Terminal?
---@return string
function M.detail_line(terminal)
	if not terminal then
		return ""
	end

	local detail = terminal.snapshot.last_output_line
	if detail and detail ~= "" then
		return detail
	end

	if terminal.runtime.phase == "exited" and terminal.snapshot.last_result.code ~= nil then
		return ("exited with code %d"):format(terminal.snapshot.last_result.code)
	end

	return M.context_line(terminal)
end

---@param text string
---@param line_idx integer
---@param start_col integer
---@param end_col integer
---@param fallback_start_col integer?
---@param fade1_hl string?
---@param fade2_hl string?
---@return tabterm.SidebarDecoration[]
local function fade_decorations(text, line_idx, start_col, end_col, fallback_start_col, fade1_hl, fade2_hl)
	local deco = {}
	fade1_hl = fade1_hl or "TabtermSidebarCommandFade1"
	fade2_hl = fade2_hl or "TabtermSidebarCommandFade2"
	local chars = vim.fn.strchars(text)
	if chars < 1 then
		return deco
	end
	if chars == 1 then
		table.insert(deco, {
			line = line_idx,
			start_col = fallback_start_col or start_col,
			end_col = end_col,
			hl = fade2_hl,
		})
		return deco
	end
	local fade1_char = chars - 2
	local fade2_char = chars - 1
	table.insert(deco, {
		line = line_idx,
		start_col = start_col + vim.str_byteindex(text, "utf-32", fade1_char, true),
		end_col = start_col + vim.str_byteindex(text, "utf-32", fade1_char + 1, true),
		hl = fade1_hl,
	})
	table.insert(deco, {
		line = line_idx,
		start_col = start_col + vim.str_byteindex(text, "utf-32", fade2_char, true),
		end_col = end_col,
		hl = fade2_hl,
	})
	return deco
end

---@param text string?
---@param line_idx integer
---@param badge_start_col integer?
---@param fade1_hl string?
---@param fade2_hl string?
---@return tabterm.SidebarDecoration[]
local function fade_before_badge_decorations(text, line_idx, badge_start_col, fade1_hl, fade2_hl)
	if not text or text == "" or not badge_start_col or badge_start_col <= 0 then
		return {}
	end

	local prefix = text:sub(1, badge_start_col)
	local prefix_chars = vim.fn.strchars(prefix)
	local adjacent = vim.fn.strcharpart(prefix, math.max(0, prefix_chars - 2), 2)
	if adjacent == "" or adjacent:match("%s") then
		return {}
	end

	local adjacent_start = #prefix - #adjacent
	return fade_decorations(
		adjacent,
		line_idx,
		adjacent_start,
		adjacent_start + #adjacent,
		adjacent_start,
		fade1_hl,
		fade2_hl
	)
end

---@param workspace tabterm.Workspace
---@param terminal tabterm.Terminal
---@param index integer
---@param width integer
---@param line_idx integer
---@return string, tabterm.SidebarDecoration[]
local function build_command_line(workspace, terminal, index, width, line_idx)
	local is_active = terminal.id == workspace.active_terminal_id
	local prefix = ("%d "):format(index)
	local command_prefix = TERMINAL_ICON
	local command_max_width = width - vim.fn.strdisplaywidth(prefix) - vim.fn.strdisplaywidth(command_prefix)
	local badge = M.sidebar_badge(terminal)
	local badge_width = badge and vim.fn.strdisplaywidth(badge.text) or 0
	command_max_width = math.max(1, command_max_width - badge_width)

	local command, truncated = truncate_display(M.command_label(terminal), command_max_width)
	local title = prefix .. command_prefix .. command
	local command_start = #prefix + #command_prefix
	local deco = {}

	table.insert(deco, {
		line = line_idx,
		start_col = 0,
		end_col = #tostring(index),
		hl = is_active and "TabtermSidebarNumberActive" or "TabtermSidebarNumberInactive",
	})
	table.insert(deco, {
		line = line_idx,
		start_col = #prefix,
		end_col = #prefix + #command_prefix,
		hl = "TabtermSidebarCommand",
	})

	if command ~= "" then
		table.insert(deco, {
			line = line_idx,
			start_col = command_start,
			end_col = command_start + #command,
			hl = "TabtermSidebarCommand",
		})
	end

	if truncated then
		vim.list_extend(
			deco,
			fade_decorations(
				command,
				line_idx,
				command_start,
				command_start + #command,
				#prefix,
				"TabtermSidebarCommandFade1",
				"TabtermSidebarCommandFade2"
			)
		)
	end

	if badge then
		title = pad_display_right(title, math.max(0, width - badge_width)) .. badge.text
		local badge_start = #title - #badge.text
		vim.list_extend(
			deco,
			fade_before_badge_decorations(
				title,
				line_idx,
				badge_start,
				"TabtermSidebarCommandFade1",
				"TabtermSidebarCommandFade2"
			)
		)
		table.insert(deco, {
			line = line_idx,
			start_col = badge_start,
			end_col = #title,
			hl = badge.hl,
		})
	else
		title = pad_display_right(title, width)
	end

	return title, deco
end

---@param workspace tabterm.Workspace
---@param terminal tabterm.Terminal
---@param width integer
---@param line_idx integer
---@return string, tabterm.SidebarDecoration[]
local function build_cwd_line(workspace, terminal, width, line_idx)
	local cwd_prefix = "  " .. DIRECTORY_ICON
	local cwd, cwd_truncated =
		format_cwd_label(workspace, terminal, math.max(1, width - vim.fn.strdisplaywidth(cwd_prefix)))
	local cwd_line = pad_display_right(cwd_prefix .. cwd, width)
	local deco = {}

	table.insert(deco, {
		line = line_idx,
		start_col = 2,
		end_col = 2 + #DIRECTORY_ICON,
		hl = "TabtermSidebarCwd",
	})

	if cwd ~= "" then
		table.insert(deco, {
			line = line_idx,
			start_col = #cwd_prefix,
			end_col = #cwd_prefix + #cwd,
			hl = "TabtermSidebarCwd",
		})
	end

	if cwd_truncated then
		vim.list_extend(
			deco,
			fade_decorations(
				cwd,
				line_idx,
				#cwd_prefix,
				#cwd_prefix + #cwd,
				#cwd_prefix,
				"TabtermSidebarCwdFade1",
				"TabtermSidebarCwdFade2"
			)
		)
	end

	return cwd_line, deco
end

---@param workspace tabterm.Workspace
---@param width integer?
---@return string[] lines
---@return (string|false)[] line_map
---@return tabterm.SidebarDecoration[] decorations
function M.sidebar_lines(workspace, width)
	local lines = {}
	local line_map = {}
	local decorations = {}
	width = math.max(8, width or 30)

	for index, id in ipairs(workspace.terminal_order) do
		local terminal = workspace.terminals_by_id[id]
		if terminal then
			local cmd_line, cmd_deco = build_command_line(workspace, terminal, index, width, #lines)
			vim.list_extend(decorations, cmd_deco)
			table.insert(lines, cmd_line)
			table.insert(line_map, id)

			local cwd_line, cwd_deco = build_cwd_line(workspace, terminal, width, #lines)
			vim.list_extend(decorations, cwd_deco)
			table.insert(lines, cwd_line)
			table.insert(line_map, id)
		end
	end

	if #lines == 0 then
		table.insert(lines, "No terminals")
		table.insert(line_map, false)
	end

	return lines, line_map, decorations
end

---@param workspace tabterm.Workspace
---@return tabterm.PlaceholderModel
function M.placeholder_model(workspace)
	local id = workspace.active_terminal_id
	local terminal = id and workspace.terminals_by_id[id] or nil

	if not terminal then
		return {
			kind = workspace.active_terminal_id == nil and "empty" or "inconsistent",
			title = workspace.active_terminal_id == nil and "No terminals in this tab"
				or "Terminal state is unavailable",
			context = nil,
			status = nil,
			detail = workspace.active_terminal_id == nil and "Create a shell or command terminal"
				or "Select another terminal or reopen the workspace",
			hint = workspace.active_terminal_id == nil and "i/a/I/A shell   c[iaIA] cmd" or "q close",
		}
	end

	if terminal.runtime.phase == "stopped" then
		local start_failed = terminal.snapshot.last_result.kind == "error" and terminal.snapshot.last_output_line ~= nil
		return {
			kind = "stopped",
			title = M.display_name(terminal),
			context = M.context_line(terminal),
			status = start_failed and "failed to start" or "not started",
			detail = start_failed and terminal.snapshot.last_output_line or nil,
			hint = "<CR> start   i/a/I/A shell   c[iaIA] cmd",
		}
	end

	if terminal.runtime.phase == "exited" then
		return {
			kind = "exited",
			title = M.display_name(terminal),
			context = M.context_line(terminal),
			status = M.result_label(terminal),
			detail = M.detail_line(terminal),
			hint = "<CR> start again   i/a/I/A shell   c[iaIA] cmd",
		}
	end

	return {
		kind = "inconsistent",
		title = M.display_name(terminal),
		context = M.context_line(terminal),
		status = nil,
		detail = "Terminal is not mounted in the panel",
		hint = "q close",
	}
end

return M
