return {
  -- Add alabaster.nvim
  {
    "p00f/alabaster.nvim",
    lazy = false,
    priority = 1000,
  },

  -- Configure LazyVim to load alabaster
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "alabaster",
    },
  },
}
