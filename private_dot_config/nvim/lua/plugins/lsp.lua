return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        nil_ls = {
          mason = false, -- Disable Mason for this server
        },
      },
    },
  },
}
