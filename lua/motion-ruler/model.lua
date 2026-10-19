local M = {}

-- split(\zs) keeps combining marks with their base character, as h/l do.
-- charclass() uses Neovim's own word classes and the current 'iskeyword'.
function M.build(line, byte_col, opts)
  local chars, starts = {}, {}
  local byte, cell, current, previous_class = 0, 0, nil, 0
  for _, text in ipairs(vim.fn.split(line, [[\zs]])) do
    local class = vim.fn.charclass(text)
    if opts.word_mode == "WORD" and class ~= 0 then
      class = 1
    end
    local width = vim.fn.strdisplaywidth(text, cell)
    chars[#chars + 1] = { byte = byte, cell = cell, class = class }
    if byte_col >= byte and byte_col < byte + #text then
      current = #chars
    end
    if class ~= 0 and class ~= previous_class then
      starts[#starts + 1] = #chars
    end
    previous_class = class
    byte, cell = byte + #text, cell + width
  end

  local result = { labels = {}, width = cell }
  if not current then
    return result
  end

  local first, last = current, current
  local class = chars[current].class
  if class ~= 0 then
    while first > 1 and chars[first - 1].class == class do
      first = first - 1
    end
    while last < #chars and chars[last + 1].class == class do
      last = last + 1
    end
  end

  local function label(index, count, kind, motion)
    if count <= opts.max_count then
      result.labels[#result.labels + 1] = {
        byte = chars[index].byte,
        cell = chars[index].cell,
        count = count,
        kind = kind,
        motion = motion,
      }
    end
  end

  local count = 0
  for i = #starts, 1, -1 do
    local index = starts[i]
    if index < current then
      count = count + 1
      -- The current word's start still consumes one b, but receives a
      -- character label instead. The preceding word therefore takes 2b.
      if class == 0 or index < first then
        label(index, count, "word", opts.word_mode == "WORD" and "B" or "b")
      end
    end
  end
  count = 0
  for _, index in ipairs(starts) do
    if index > current then
      count = count + 1
      label(index, count, "word", opts.word_mode == "WORD" and "W" or "w")
    end
  end

  for index = first, last do
    local distance = math.abs(index - current)
    label(index, distance, distance == 0 and "cursor" or "character", index < current and "h" or "l")
  end
  table.sort(result.labels, function(a, b)
    return a.cell < b.cell
  end)
  return result
end

return M
