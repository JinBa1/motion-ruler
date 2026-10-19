-- Run from the project directory: nvim -u examples/init.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.wrap = false
vim.opt.termguicolors = true
vim.opt.swapfile = false
vim.opt.laststatus = 2
vim.opt.statusline = " motion-ruler.nvim | <Space>r toggle | w/b words | h/l characters %=%l:%c "
vim.g.mapleader = " "
require("motion-ruler").setup()
vim.keymap.set("n", "<leader>r", "<cmd>MotionRulerToggle<CR>", { desc = "Toggle motion ruler" })

if vim.fn.argc() == 0 then
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      vim.cmd.edit(vim.fn.fnameescape(root .. "/examples/demo.txt"))
      vim.api.nvim_win_set_cursor(0, { 1, 15 })
      require("motion-ruler").refresh()
    end,
  })
end
