local api = vim.api
local model = require("motion-ruler.model")
local render = require("motion-ruler.render")
local M = {}

local defaults = {
  enabled = true,
  word_mode = "word",
  max_count = 99,
  fill_char = "─",
  max_line_length = 10000,
  disabled_filetypes = {},
}

local config = vim.deepcopy(defaults)
local ns = api.nvim_create_namespace("motion-ruler")
local active_buf, mark_id, queued
local enabled = false

local function clear()
  if active_buf and api.nvim_buf_is_valid(active_buf) and mark_id then
    api.nvim_buf_del_extmark(active_buf, ns, mark_id)
  end
  active_buf, mark_id = nil, nil
end

local function highlights()
  api.nvim_set_hl(0, "MotionRulerLine", { default = true, link = "NonText" })
  api.nvim_set_hl(0, "MotionRulerWord", { default = true, link = "Special" })
  api.nvim_set_hl(0, "MotionRulerCharacter", { default = true, link = "Comment" })
  api.nvim_set_hl(0, "MotionRulerCursor", { default = true, link = "CursorLineNr" })
end

function M.refresh()
  local mode = api.nvim_get_mode().mode:sub(1, 1)
  if not enabled or not (mode == "n" or mode == "v" or mode == "V" or mode == "\22") then
    clear()
    return
  end

  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  if vim.bo[buf].buftype ~= ""
    or vim.tbl_contains(config.disabled_filetypes, vim.bo[buf].filetype)
    or api.nvim_win_get_config(win).relative ~= ""
    or vim.wo[win].rightleft
    or vim.wo[win].conceallevel > 0
  then
    clear()
    return
  end

  local cursor = api.nvim_win_get_cursor(win)
  local row, col = cursor[1] - 1, cursor[2]
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  if not line or #line == 0 or #line > config.max_line_length or vim.fn.foldclosed(row + 1) ~= -1 then
    clear()
    return
  end

  local info = vim.fn.getwininfo(win)[1]
  local width = api.nvim_win_get_width(win) - info.textoff
  local view = vim.fn.winsaveview()
  local data = model.build(line, col, config)
  -- Virtual lines are attached below an entire buffer line; they cannot be
  -- inserted between its wrapped screen rows. Hide rather than misalign.
  if width < 1 or (vim.wo[win].wrap and data.width > width) or view.skipcol > 0 or view.coladd > 0 then
    clear()
    return
  end

  local lines = render.lines(data, view.leftcol, width, config.fill_char)
  if #lines == 0 then
    clear()
    return
  end
  if active_buf ~= buf then
    clear()
  end
  mark_id = api.nvim_buf_set_extmark(buf, ns, row, 0, {
    id = mark_id,
    virt_lines = lines,
    virt_lines_above = false,
    right_gravity = false,
    priority = 100,
  })
  active_buf = buf
end

local function request_refresh()
  if queued then
    return
  end
  queued = true
  vim.schedule(function()
    queued = false
    M.refresh()
  end)
end

function M.enable()
  enabled = true
  M.refresh()
end

function M.disable()
  enabled = false
  clear()
end

function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
  return enabled
end

local function validate(opts)
  for key in pairs(opts) do
    assert(defaults[key] ~= nil, "motion-ruler: unknown option '" .. tostring(key) .. "'")
  end
  local merged = vim.tbl_deep_extend("force", defaults, opts)
  assert(type(merged.enabled) == "boolean", "motion-ruler: enabled must be a boolean")
  assert(
    merged.word_mode == "word" or merged.word_mode == "WORD",
    "motion-ruler: word_mode must be 'word' or 'WORD'"
  )
  for _, key in ipairs({ "max_count", "max_line_length" }) do
    local value = merged[key]
    assert(
      type(value) == "number" and value >= 1 and value < math.huge and value % 1 == 0,
      "motion-ruler: " .. key .. " must be a positive integer"
    )
  end
  assert(
    type(merged.fill_char) == "string"
      and vim.fn.strchars(merged.fill_char) == 1
      and vim.fn.strdisplaywidth(merged.fill_char) == 1
      and vim.fn.char2nr(merged.fill_char) >= 32,
    "motion-ruler: fill_char must be one printable screen cell"
  )
  assert(
    type(merged.disabled_filetypes) == "table" and vim.islist(merged.disabled_filetypes),
    "motion-ruler: disabled_filetypes must be a list of strings"
  )
  for _, ft in ipairs(merged.disabled_filetypes) do
    assert(type(ft) == "string", "motion-ruler: disabled_filetypes must be a list of strings")
  end
  return merged
end

function M.setup(opts)
  assert(vim.fn.has("nvim-0.10") == 1, "motion-ruler requires Neovim 0.10 or newer")
  assert(opts == nil or type(opts) == "table", "motion-ruler: setup expects a table")
  local new_config = validate(opts or {})
  clear()
  config, enabled = new_config, new_config.enabled
  highlights()
  local group = api.nvim_create_augroup("MotionRuler", { clear = true })
  api.nvim_create_autocmd({
    "CursorMoved", "TextChanged", "BufEnter", "WinEnter", "WinScrolled",
    "WinResized", "VimResized", "ModeChanged", "InsertLeave", "CmdlineLeave",
  }, {
    group = group,
    callback = request_refresh,
  })
  api.nvim_create_autocmd({ "BufLeave", "WinLeave", "InsertEnter", "CmdlineEnter" }, {
    group = group,
    callback = clear,
  })
  api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = {
      "iskeyword", "tabstop", "vartabstop", "wrap", "number", "relativenumber", "numberwidth",
      "signcolumn", "foldcolumn", "conceallevel", "rightleft", "filetype", "buftype",
      "ambiwidth", "display",
    },
    callback = request_refresh,
  })
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      highlights()
      request_refresh()
    end,
  })
  api.nvim_create_user_command("MotionRulerToggle", M.toggle, {
    desc = "Toggle the horizontal motion ruler", force = true,
  })
  api.nvim_create_user_command("MotionRulerEnable", M.enable, {
    desc = "Show the horizontal motion ruler", force = true,
  })
  api.nvim_create_user_command("MotionRulerDisable", M.disable, {
    desc = "Hide the horizontal motion ruler", force = true,
  })
  M.refresh()
  return M
end

return M
