if vim.g.loaded_tabterm_plugin == 1 then
	return
end

vim.g.loaded_tabterm_plugin = 1

---@class tabterm.UserCommandArgs
---@field args string

---@class tabterm.Subcommand
---@field run fun(args: string|nil)

---@type table<string, tabterm.Subcommand>
local subcommands = {
	toggle = {
		run = function()
			require("tabterm").toggle()
		end,
	},
	open = {
		run = function()
			require("tabterm").open()
		end,
	},
	close = {
		run = function()
			require("tabterm").hide()
		end,
	},
	shell = {
		run = function()
			require("tabterm").new_shell()
		end,
	},
	command = {
		run = function(args)
			require("tabterm").new_command(args ~= "" and args or nil)
		end,
	},
	start = {
		run = function()
			require("tabterm").start_active()
		end,
	},
	rename = {
		run = function()
			require("tabterm").rename_active()
		end,
	},
	delete = {
		run = function()
			require("tabterm").delete_active()
		end,
	},
	next = {
		run = function()
			require("tabterm").next_terminal()
		end,
	},
	prev = {
		run = function()
			require("tabterm").prev_terminal()
		end,
	},
}

local subcommand_names = {
	"toggle",
	"open",
	"close",
	"shell",
	"command",
	"start",
	"rename",
	"delete",
	"next",
	"prev",
}

---@param arg_lead string
---@param cmd_line string
---@param cursor_pos integer
---@return string[]
local function complete_subcommands(arg_lead, cmd_line, cursor_pos)
	local before_cursor = cmd_line:sub(1, cursor_pos)
	if before_cursor:match("^%s*Tabterm%s+%S+%s") then
		return {}
	end

	return vim.tbl_filter(function(name)
		return name:sub(1, #arg_lead) == arg_lead
	end, subcommand_names)
end

---@param opts tabterm.UserCommandArgs
local function tabterm_dispatch(opts)
	local subcommand, args = opts.args:match("^(%S+)%s*(.-)$")
	if not subcommand then
		vim.notify("Usage: Tabterm <subcommand>", vim.log.levels.ERROR)
		return
	end

	local command = subcommands[subcommand]
	if not command then
		vim.notify("Unknown Tabterm subcommand: " .. subcommand, vim.log.levels.ERROR)
		return
	end

	command.run(args)
end

vim.api.nvim_create_user_command("Tabterm", tabterm_dispatch, {
	nargs = "*",
	complete = complete_subcommands,
})
