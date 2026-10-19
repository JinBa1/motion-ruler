local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
local api = vim.api
local model = require("motion-ruler.model")
local render = require("motion-ruler.render")
local ruler = require("motion-ruler")
local ns = api.nvim_create_namespace("motion-ruler")
local total, failures, motion_checks = 0, {}, 0

local function equal(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    error(
      (message or "values differ")
        .. "\nexpected: " .. vim.inspect(expected)
        .. "\nactual: " .. vim.inspect(actual),
      2
    )
  end
end

local function test(name, fn)
  total = total + 1
  ruler.disable()
  vim.cmd("enew!")
  vim.opt_local.iskeyword = "@,48-57,_,192-255"
  vim.opt_local.tabstop = 8
  vim.opt_local.vartabstop = ""
  vim.opt_local.wrap = false
  vim.opt_local.conceallevel = 0
  vim.opt_local.rightleft = false
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    print("PASS " .. name)
  else
    failures[#failures + 1] = name .. ": " .. err
    print("FAIL " .. name .. "\n" .. err)
  end
end

local function set_line(line, col)
  api.nvim_buf_set_lines(0, 0, -1, false, { line, "sentinel" })
  api.nvim_win_set_cursor(0, { 1, col or 0 })
end

local function options(overrides)
  return vim.tbl_extend("force", { word_mode = "word", max_count = 999 }, overrides or {})
end

local function flatten(chunks)
  local text = {}
  for _, chunk in ipairs(chunks) do
    text[#text + 1] = chunk[1]
  end
  return table.concat(text)
end

local function native(line_col, count, motion)
  api.nvim_win_set_cursor(0, { 1, line_col })
  if count > 0 then
    vim.cmd("normal! " .. count .. motion)
  end
  return api.nvim_win_get_cursor(0)
end

local function verify_native(line, opts)
  set_line(line)
  local col = 0
  for _, char in ipairs(vim.fn.split(line, [[\zs]])) do
    local data = model.build(line, col, opts)
    local character_positions, words = {}, {}
    for _, label in ipairs(data.labels) do
      local destination = native(col, label.count, label.motion)
      equal(destination, { 1, label.byte },
        "native " .. label.count .. label.motion .. " from byte " .. col .. " in " .. line)
      motion_checks = motion_checks + 1
      if label.kind == "word" then
        words[label.motion .. ":" .. label.byte] = label.count
      else
        character_positions[label.byte] = true
      end
    end
    -- Check completeness too: every same-line native word destination outside
    -- the current word must have a label, including the asymmetric 2b case.
    for _, motion in ipairs(opts.word_mode == "WORD" and { "W", "B" } or { "w", "b" }) do
      local previous = col
      for count = 1, opts.max_count do
        local destination = native(col, count, motion)
        if destination[1] ~= 1 or destination[2] == previous then
          break
        end
        local target = destination[2]
        local target_text = line:sub(target + 1)
        if not character_positions[target] and vim.fn.charclass(target_text) ~= 0 then
          equal(words[motion .. ":" .. target], count,
            "missing " .. count .. motion .. " from byte " .. col .. " in " .. line)
        end
        previous = target
      end
    end
    col = col + #char
  end
end

test("example and backward count from inside a word", function()
  set_line("alpha bravo charlie delta echo", 15)
  local data = model.build(api.nvim_get_current_line(), 15, options())
  equal(flatten(render.lines(data, 0, 30, " ")[1]), "3     2     3210123 1     2   ")
  equal(data.labels[2].count, 2)
  equal(data.labels[2].motion, "b")
end)

test("all word and character labels agree with native motions", function()
  for _, line in ipairs({
    "alpha bravo charlie delta echo",
    "object.method(arg, other); a+=b--c",
    "  leading   spaces and trailing  ",
    "\talpha\tbravo\tcharlie\t",
    "one_word 123_thing mixedCASE",
    "--[]{}... != @#$%^&*()",
    "a b c d e f g h i j k l m n o p q r s t",
    "abcdefghijklmnopqrstuvwxyz0123456789",
    " ",
  }) do
    verify_native(line, options())
  end
end)

test("Unicode classes, wide characters, and combining accents match native motions", function()
  for _, line in ipairs({
    "café naïve Ελληνικά русский",
    "abc中文def 日本語 カタカナ ひらがな 한글",
    "ábc éfgh ấxyz",
    "abc🙂🙂def 🚀 test",
    "one\194\160two\227\128\128three",
  }) do
    verify_native(line, options())
  end
end)

test("buffer-local iskeyword changes are respected", function()
  vim.opt_local.iskeyword:append({ "-", "." })
  verify_native("some-name.other_name + next-item", options())
  vim.opt_local.iskeyword:remove("_")
  verify_native("some_name + other_name", options())
end)

test("WORD mode agrees with W/B", function()
  verify_native("foo.bar(x) + other_thing--again\tlast.word", options({ word_mode = "WORD" }))
  verify_native("abc中文🙂def ábc \t last", options({ word_mode = "WORD" }))
end)

test("empty input and off-line virtual cursor produce no labels", function()
  equal(model.build("", 0, options()).labels, {})
  equal(model.build("word", 4, options()).labels, {})
  equal(render.lines({ labels = {} }, 0, 80, "─"), {})
end)

test("tabs, wide characters, and combining marks have correct screen columns", function()
  set_line("\tá中abc\tdef", 1)
  local data = model.build(api.nvim_get_current_line(), 1, options())
  for _, label in ipairs(data.labels) do
    api.nvim_win_set_cursor(0, { 1, label.byte })
    equal(label.cell, vim.fn.virtcol(".", true)[1] - 1, "screen column at byte " .. label.byte)
  end
  vim.opt_local.vartabstop = "3,5"
  data = model.build(api.nvim_get_current_line(), 1, options())
  for _, label in ipairs(data.labels) do
    api.nvim_win_set_cursor(0, { 1, label.byte })
    equal(label.cell, vim.fn.virtcol(".", true)[1] - 1)
  end
end)

test("multi-digit character labels stay on one row without overlap", function()
  set_line("abcdefghijklmnop", 0)
  local data = model.build(api.nvim_get_current_line(), 0, options())
  local lines = render.lines(data, 0, 16, " ")
  equal(#lines, 1)
  equal(flatten(lines[1]), "0123456789 11 14")
  data = model.build(api.nvim_get_current_line(), 15, options())
  equal(flatten(render.lines(data, 0, 16, " ")[1]), "15 12 9876543210")
end)

test("multi-digit word counts read horizontally with a gap", function()
  local data = { labels = {
    { cell = 0, count = 10, kind = "word" },
    { cell = 5, count = 11, kind = "word" },
  } }
  local lines = render.lines(data, 0, 8, " ")
  equal(#lines, 1)
  equal(flatten(lines[1]), "10   11 ")
end)

test("multi-digit labels never overwrite zero or appear partially clipped", function()
  local data = { labels = {
    { cell = 0, count = 10, kind = "word" },
    { cell = 1, count = 0, kind = "cursor" },
    { cell = 4, count = 12, kind = "word" },
  } }
  equal(flatten(render.lines(data, 0, 5, " ")[1]), " 0   ")
  equal(render.lines({ labels = { data.labels[3] } }, 0, 5, " "), {})
end)

test("all demo lines use at most one row and keep each displayed count aligned", function()
  for _, line in ipairs(vim.fn.readfile(root .. "/examples/demo.txt")) do
    set_line(line)
    local col = 0
    for _, char in ipairs(vim.fn.split(line, [[\zs]])) do
      local data = model.build(line, col, options())
      local lines = render.lines(data, 0, 80, " ")
      assert(#lines <= 1, "extra ruler row in " .. line)
      if #lines == 1 then
        local targets = {}
        for _, label in ipairs(data.labels) do
          targets[label.cell] = label.count
        end
        local position = 0
        for _, chunk in ipairs(lines[1]) do
          if chunk[2] ~= "MotionRulerLine" then
            equal(tonumber(chunk[1]), targets[position], "label target in " .. line)
          end
          position = position + vim.fn.strdisplaywidth(chunk[1])
        end
        equal(position, 80)
      end
      col = col + #char
    end
  end
end)

test("horizontal scrolling clips labels into the viewport", function()
  set_line("alpha bravo charlie delta echo", 15)
  local lines = render.lines(model.build(api.nvim_get_current_line(), 15, options()), 10, 10, " ")
  equal(flatten(lines[1]), "  3210123 ")
  equal(vim.fn.strdisplaywidth(flatten(lines[1])), 10)
end)

test("count limit hides distant labels rather than wrapping their digits", function()
  set_line("abcdefghijklmno", 0)
  local data = model.build(api.nvim_get_current_line(), 0, options({ max_count = 9 }))
  equal(#data.labels, 10)
  equal(data.labels[#data.labels].count, 9)
  equal(#render.lines(data, 0, 30, "─"), 1)
end)

local function extmarks(buf)
  return api.nvim_buf_get_extmarks(buf or 0, ns, 0, -1, { details = true })
end

test("setup, cursor movement, toggle, and setup again", function()
  set_line("alpha bravo charlie delta echo", 15)
  ruler.setup({ fill_char = " " })
  equal(#extmarks(), 1)
  equal(extmarks()[1][4].virt_lines_above, false)
  equal(flatten(extmarks()[1][4].virt_lines[1]):sub(1, 30), "3     2     3210123 1     2   ")
  api.nvim_win_set_cursor(0, { 2, 2 })
  api.nvim_exec_autocmds("CursorMoved", {})
  vim.wait(100, function() return extmarks()[1][2] == 1 end)
  equal(extmarks()[1][2], 1)
  equal(ruler.toggle(), false)
  equal(#extmarks(), 0)
  vim.cmd("MotionRulerEnable")
  equal(#extmarks(), 1)
  ruler.setup({ max_count = 9 })
  equal(#extmarks(), 1)
  vim.cmd("MotionRulerDisable")
  equal(#extmarks(), 0)
end)

test("buffer changes clear stale rulers", function()
  set_line("one two three", 5)
  local old = api.nvim_get_current_buf()
  ruler.setup()
  vim.cmd("new")
  set_line("other text", 1)
  ruler.refresh()
  equal(#extmarks(old), 0)
  equal(#extmarks(), 1)
  vim.cmd("close!")
end)

test("special buffers, excluded filetypes, and insert entry hide the ruler", function()
  set_line("one two three", 5)
  ruler.setup({ disabled_filetypes = { "ruler_test" } })
  vim.bo.filetype = "ruler_test"
  ruler.refresh()
  equal(#extmarks(), 0)
  vim.bo.filetype = ""
  vim.bo.buftype = "nofile"
  ruler.refresh()
  equal(#extmarks(), 0)
  vim.bo.buftype = ""
  ruler.refresh()
  equal(#extmarks(), 1)
  api.nvim_exec_autocmds("InsertEnter", {})
  equal(#extmarks(), 0)
end)

test("wrapped, concealed, folded, and oversized lines hide the ruler", function()
  set_line(string.rep("word ", 40), 2)
  ruler.setup()
  vim.opt_local.wrap = true
  ruler.refresh()
  equal(#extmarks(), 0)
  vim.opt_local.wrap = false
  ruler.refresh()
  equal(#extmarks(), 1)
  vim.opt_local.conceallevel = 2
  ruler.refresh()
  equal(#extmarks(), 0)
  vim.opt_local.conceallevel = 0
  vim.opt_local.foldmethod = "manual"
  vim.cmd("1,2fold")
  ruler.refresh()
  equal(#extmarks(), 0)
  vim.cmd("normal! zE")
  ruler.setup({ max_line_length = 10 })
  equal(#extmarks(), 0)
end)

test("refresh preserves cursor, text, registers, marks, search, and undo history", function()
  set_line("alpha bravo charlie delta echo", 15)
  vim.fn.setreg("a", "keep this register")
  vim.fn.setreg("/", "keep this search")
  api.nvim_buf_set_mark(0, "a", 1, 4, {})
  local before = {
    cursor = api.nvim_win_get_cursor(0),
    lines = api.nvim_buf_get_lines(0, 0, -1, false),
    register = vim.fn.getreg("a"),
    search = vim.fn.getreg("/"),
    mark = api.nvim_buf_get_mark(0, "a"),
    undo = vim.fn.undotree().seq_cur,
    tick = api.nvim_buf_get_changedtick(0),
    view = vim.fn.winsaveview(),
    jumps = vim.fn.getjumplist(),
  }
  ruler.setup()
  for _ = 1, 20 do ruler.refresh() end
  equal({
    cursor = api.nvim_win_get_cursor(0),
    lines = api.nvim_buf_get_lines(0, 0, -1, false),
    register = vim.fn.getreg("a"),
    search = vim.fn.getreg("/"),
    mark = api.nvim_buf_get_mark(0, "a"),
    undo = vim.fn.undotree().seq_cur,
    tick = api.nvim_buf_get_changedtick(0),
    view = vim.fn.winsaveview(),
    jumps = vim.fn.getjumplist(),
  }, before)
end)

test("invalid options fail before changing the working configuration", function()
  set_line("one two three", 5)
  ruler.setup()
  for _, opts in ipairs({
    { word_mode = "invalid" }, { max_count = 0 }, { max_count = 1.5 },
    { fill_char = "中" }, { fill_char = "\t" }, { enabled = 1 },
    { disabled_filetypes = { 1 } }, { unknown_option = true },
  }) do
    equal(pcall(ruler.setup, opts), false)
    equal(#extmarks(), 1)
  end
end)

ruler.disable()
print(string.format(
  "\n%d/%d tests passed; %d labels checked against native motions",
  total - #failures, total, motion_checks
))
if #failures > 0 then
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
