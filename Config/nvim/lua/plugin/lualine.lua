local lualine = require("lualine")

local colors = {
    background = "#080808",
    white = "#c6c6c6",
    black = "#323437",
    red = "#ff5454",
    yellow = "#e3c78a",
    green = "#8cc85f",
    cyan = "#79dac8",
    blue = "#80a0ff",
    magenta = "#cf87e8",
}

local custom = {
    normal = {
        a = { fg = colors.black, bg = colors.blue },
        b = { fg = colors.white, bg = colors.black },
        c = { fg = colors.white, bg = colors.background },
    },
    command = { a = { fg = colors.black, bg = colors.yellow } },
    insert = { a = { fg = colors.black, bg = colors.green } },
    visual = { a = { fg = colors.black, bg = colors.magenta } },
    replace = { a = { fg = colors.black, bg = colors.red } },
    inactive = {
        a = { fg = colors.white, bg = colors.black },
        b = { fg = colors.white, bg = colors.black },
    },
}

lualine.setup({
    options = {
        icons_enabled = true,
        theme = custom,
        disabled_filetypes = {
            statusline = {},
            winbar = {},
        },
        ignore_focus = {},
        always_divide_middle = true,
        globalstatus = false,
        refresh = {
            statusline = 1000,
            tabline = 1000,
            winbar = 1000,
        },
    },
    sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch" },
        lualine_c = { "diagnostics", "diff" },
        lualine_x = { "location" },
        lualine_y = { "filename" },
        lualine_z = { "progress" },
    },
    inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = {},
        lualine_x = { "location" },
        lualine_y = {},
        lualine_z = {},
    },
    tabline = {},
    winbar = {},
    inactive_winbar = {},
    extensions = {},
})
