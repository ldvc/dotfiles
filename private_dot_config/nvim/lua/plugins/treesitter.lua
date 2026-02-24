return {
  "nvim-treesitter/nvim-treesitter",
  opts = function(_, opts)
    require("nvim-treesitter.install").compilers = { "gcc", "clang", "cc" }
    return opts
  end,
}
