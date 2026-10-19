local M = {}

local highlights = {
  word = "MotionRulerWord",
  character = "MotionRulerCharacter",
  cursor = "MotionRulerCursor",
}

-- Keep the ruler to one row. Print whole numbers starting at their target
-- column; retain nearer targets when labels compete for the same space.
function M.lines(model, leftcol, width, fill_char)
  if width < 1 then
    return {}
  end

  local visible = {}
  for _, label in ipairs(model.labels) do
    local length = #tostring(label.count)
    if label.cell >= leftcol and label.cell + length <= leftcol + width then
      visible[#visible + 1] = label
    end
  end
  if #visible == 0 then
    return {}
  end

  table.sort(visible, function(a, b)
    if a.kind == "cursor" or b.kind == "cursor" then
      if a.kind ~= b.kind then
        return a.kind == "cursor"
      end
    end
    if a.count ~= b.count then
      return a.count < b.count
    end
    return a.cell < b.cell
  end)

  local selected, occupied, padding = {}, {}, {}
  for _, label in ipairs(visible) do
    local column, number = label.cell - leftcol, tostring(label.count)
    local last = column + #number - 1
    local fits = true
    for cell = column, last do
      if occupied[cell] or padding[cell] then
        fits = false
        break
      end
    end
    -- Separate multi-digit labels from adjacent numbers so "10" is read as
    -- one count. Single-digit character distances may remain contiguous.
    if #number > 1 and (occupied[column - 1] or occupied[last + 1]) then
      fits = false
    end
    if fits then
      selected[#selected + 1] = label
      for cell = column, last do
        occupied[cell] = true
      end
      if #number > 1 then
        padding[column - 1], padding[last + 1] = true, true
      end
    end
  end

  table.sort(selected, function(a, b)
    return a.cell < b.cell
  end)
  local chunks, position = {}, 0
  for _, label in ipairs(selected) do
    local column, number = label.cell - leftcol, tostring(label.count)
    if column > position then
      chunks[#chunks + 1] = { string.rep(fill_char, column - position), "MotionRulerLine" }
    end
    chunks[#chunks + 1] = { number, highlights[label.kind] }
    position = column + #number
  end
  if position < width then
    chunks[#chunks + 1] = { string.rep(fill_char, width - position), "MotionRulerLine" }
  end
  return { chunks }
end

return M
