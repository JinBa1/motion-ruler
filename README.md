# motion-ruler.nvim

A dependency-free Lua plugin that adds a horizontal relative-motion ruler below
your current line in Neovim.

With the cursor on the **r** in `charlie`:

```text
alpha bravo charlie delta echo
3─────2─────3210123─1─────2─────────────────
               ↑
```

- Outside the current word, numbers count `w` to the right and `b` to the left.
- Inside the current word, numbers count `h` and `l`; `0` marks your cursor.
- `2w` reaches `echo`, `2b` reaches `bravo`, and `3h` reaches `c`.
- The first `b` from inside a word reaches that word's start. That step is included
  when counting previous words.

The plugin reads Neovim's native character classes, respecting punctuation,
Unicode, combining accents, and buffer-local `iskeyword`. Tabs and wide
characters use display columns; counts use cursor movements, not UTF-8 bytes.
It never moves your cursor to calculate labels or remaps your motion keys.

Requires **Neovim 0.10+**. Tested on Neovim 0.12.5. No package downloads or build
steps are needed.

## Try it

```sh
cd ~/sideproject/motion-ruler.nvim
make demo
```

This opens the sample file using an isolated configuration. Move around with
`w`, `b`, `h`, and `l`. Press `<Space>r` to toggle. It does not load or change your
normal Neovim configuration. Quit with `:q!` if you edited the sample.

To try it on your own file:

```sh
nvim -u ~/sideproject/motion-ruler.nvim/examples/init.lua path/to/file
```

## Install locally

Your current setup uses lazy.nvim. Add this entry inside its plugin list:

```lua
{
  dir = vim.fn.expand("~/sideproject/motion-ruler.nvim"),
  name = "motion-ruler.nvim",
  main = "motion-ruler",
  lazy = false,
  opts = {},
  keys = {
    { "<leader>mr", "<cmd>MotionRulerToggle<CR>", desc = "Toggle motion ruler" },
  },
},
```

Or load it directly from `init.lua`, without a package manager:

```lua
vim.opt.runtimepath:prepend(vim.fn.expand("~/sideproject/motion-ruler.nvim"))
require("motion-ruler").setup()
```

## Options

```lua
require("motion-ruler").setup({
  enabled = true,
  word_mode = "word",         -- "word" = w/b; "WORD" = W/B
  max_count = 99,              -- larger distances have no label; counts never wrap
  fill_char = "─",             -- use " " for numbers without the horizontal rule
  max_line_length = 10000,     -- skip very long lines (UTF-8 bytes)
  disabled_filetypes = {},     -- e.g. { "markdown", "text" }
})
```

The ruler always occupies one row. Counts above nine read horizontally, with
their first digit aligned beneath the target character. If labels would overlap
or merge into a multi-digit number, nearer targets take priority and some farther
labels are omitted:

```text
abcdefghijklmnop
0123456789─11─14
```

For example, `11` starts beneath `l`: press `11l`. The highlighted `0` always
takes priority. Set `max_count = 9` to show only single-digit distances.

## Commands and colors

```vim
:MotionRulerToggle
:MotionRulerEnable
:MotionRulerDisable
```

Lua equivalents: `require("motion-ruler").toggle()`, `.enable()`, `.disable()`,
and `.refresh()`. Call `.setup()` to register commands and automatic updates.

| Highlight | Default link | Meaning |
| --- | --- | --- |
| `MotionRulerLine` | `NonText` | Horizontal rule |
| `MotionRulerWord` | `Special` | Word movement counts |
| `MotionRulerCharacter` | `Comment` | Character movement counts |
| `MotionRulerCursor` | `CursorLineNr` | Zero beneath the cursor |

Override them with `vim.api.nvim_set_hl(0, "MotionRulerWord", { fg = "#e6c384" })`.

## Display behavior and limits

- Shows in Normal, Visual, and operator-pending modes. Hides in Insert and
  command-line modes, special buffers, floating windows, and closed folds.
- Labels cover only the current buffer line and its visible columns. With
  `nowrap`, they follow horizontal scrolling.
- Virtual lines cannot be inserted between a buffer line's wrapped screen rows.
  The ruler therefore hides when the current line wraps; use `:set nowrap` for
  long lines. It also hides with `conceallevel > 0`, `rightleft`, or a cursor in
  virtual space because the simple column mapping would be misleading.
- Splits displaying the same buffer share its ruler, positioned for the active
  window. Different widths and horizontal scroll positions in those splits can
  produce different alignment. The active window is the reference.
- Other plugins' inline virtual text (such as inlay hints) can shift the source
  text away from its ruler columns.
- Counts describe built-in motions. If you remap `w/b/h/l` to custom motions,
  their destinations can differ. Operator-specific behavior such as `cw` is
  separate from these navigation counts.

## Development

```sh
make test
```

The headless Lua tests compare generated labels against actual Neovim `w/b`,
`W/B`, and `h/l` motions, including Unicode and customized `iskeyword`. They also
check alignment, multi-digit counts, toggling, lifecycle cleanup, and preservation
of cursor position, buffer text, registers, search, marks, undo, and viewport.

Code: `lua/motion-ruler/model.lua` calculates labels,
`lua/motion-ruler/render.lua` lays out the ruler, and `lua/motion-ruler/init.lua`
handles setup, commands, and editor events.
