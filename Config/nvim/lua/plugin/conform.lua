local conform = require("conform")
conform.setup({
    formatters_by_ft = {
        lua = { "stylua" },
        python = { "isort", "black" },
        javascript = { "deno" },
        typescript = { "deno" },
        bash = { "beautysh" },
        css = { "stylelint" },
        java = { "astyle" },
    },
    format_on_save = {
        timeout_ms = 500,
        lsp_fallback = true,
    },
})

vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = "*",
    callback = function(args)
        require("conform").format({ bufnr = args.buf })
    end,
})

vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
