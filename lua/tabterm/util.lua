local M = {}

---@param bufnr integer?
---@return boolean
function M.valid_buf(bufnr)
	return bufnr ~= nil and bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr)
end

---@param winid integer?
---@return boolean
function M.valid_win(winid)
	return winid ~= nil and winid > 0 and vim.api.nvim_win_is_valid(winid)
end

return M
