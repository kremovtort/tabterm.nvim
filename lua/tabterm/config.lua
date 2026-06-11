local M = {}

---@alias tabterm.BorderStyle "single"|"double"|"round"|"none"

---@class tabterm.FloatConfig
---@field width number
---@field height number

---@class tabterm.UIConfig
---@field border tabterm.BorderStyle
---@field sidebar_width integer
---@field float tabterm.FloatConfig

---@class tabterm.ShellIntegrationShellsConfig
---@field bash boolean
---@field zsh boolean

---@class tabterm.ShellIntegrationConfig
---@field enabled boolean
---@field shells tabterm.ShellIntegrationShellsConfig

---@class tabterm.Config
---@field ui tabterm.UIConfig
---@field shell_integration tabterm.ShellIntegrationConfig

---@class tabterm.FloatConfigInput
---@field width number?
---@field height number?

---@class tabterm.UIConfigInput
---@field border boolean|tabterm.BorderStyle?
---@field sidebar_width integer?
---@field float tabterm.FloatConfigInput?

---@class tabterm.ShellIntegrationShellsConfigInput
---@field bash boolean?
---@field zsh boolean?

---@class tabterm.ShellIntegrationConfigInput
---@field enabled boolean?
---@field shells tabterm.ShellIntegrationShellsConfigInput?

---@class tabterm.ConfigInput
---@field ui tabterm.UIConfigInput?
---@field shell_integration tabterm.ShellIntegrationConfigInput?

local valid_borders = {
	single = true,
	double = true,
	round = true,
	none = true,
}

---@type tabterm.Config
M.defaults = {
	ui = {
		border = "single",
		sidebar_width = 30,
		float = {
			width = 0.70,
			height = 0.70,
		},
	},
	shell_integration = {
		enabled = true,
		shells = {
			bash = true,
			zsh = true,
		},
	},
}

---@param config tabterm.ConfigInput?
---@return tabterm.Config
function M.normalize(config)
	local normalized = vim.deepcopy(config or {})
	normalized.ui = normalized.ui or {}

	if normalized.ui.border == true then
		normalized.ui.border = "single"
	elseif normalized.ui.border == false then
		normalized.ui.border = "none"
	elseif normalized.ui.border == nil then
		normalized.ui.border = M.defaults.ui.border
	elseif not valid_borders[normalized.ui.border] then
		normalized.ui.border = M.defaults.ui.border
	end

	normalized.ui.sidebar_width = math.max(20, tonumber(normalized.ui.sidebar_width) or M.defaults.ui.sidebar_width)

	normalized.ui.float = normalized.ui.float or {}
	normalized.ui.float.width = tonumber(normalized.ui.float.width) or M.defaults.ui.float.width
	normalized.ui.float.height = tonumber(normalized.ui.float.height) or M.defaults.ui.float.height

	normalized.shell_integration = normalized.shell_integration or {}
	if normalized.shell_integration.enabled == nil then
		normalized.shell_integration.enabled = M.defaults.shell_integration.enabled
	else
		normalized.shell_integration.enabled = normalized.shell_integration.enabled == true
	end

	normalized.shell_integration.shells = normalized.shell_integration.shells or {}
	if normalized.shell_integration.shells.bash == nil then
		normalized.shell_integration.shells.bash = M.defaults.shell_integration.shells.bash
	else
		normalized.shell_integration.shells.bash = normalized.shell_integration.shells.bash == true
	end
	if normalized.shell_integration.shells.zsh == nil then
		normalized.shell_integration.shells.zsh = M.defaults.shell_integration.shells.zsh
	else
		normalized.shell_integration.shells.zsh = normalized.shell_integration.shells.zsh == true
	end

	return normalized
end

---@param opts tabterm.ConfigInput?
---@return tabterm.Config
function M.merge(opts)
	return M.normalize(vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {}))
end

return M
