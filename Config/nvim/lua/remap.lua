vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)

vim.opt.scrolloff = 20
vim.opt.number = true
vim.opt.relativenumber = true

vim.o.clipboard = 'unnamedplus' -- Sync clipboard between OS and Neovim.
vim.o.completeopt = 'menuone,noselect' -- Completion options
vim.o.termguicolors = true     -- True color support

vim.o.breakindent = true        -- Enable break indent
vim.o.undofile = true           -- Save undo history

vim.o.tabstop = 4               -- Number of spaces tabs count for
vim.o.shiftwidth = 4            -- Size of an indent
vim.o.expandtab = true          -- Use spaces instead of tabs
