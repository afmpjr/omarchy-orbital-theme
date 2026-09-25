return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",
      transparent = false,
      styles = { sidebars = "dark", floats = "dark" },
      on_colors = function(c)
        c.bg = "#050B14"
        c.bg_dark = "#03080F"
        c.bg_float = "#0A1422"
        c.bg_highlight = "#101E30"
        c.bg_popup = "#0A1422"
        c.bg_search = "#1769AA"
        c.bg_sidebar = "#050B14"
        c.bg_statusline = "#0A1422"
        c.bg_visual = "#1769AA"
        c.border = "#1A2E4A"
        c.fg = "#F4F8FF"
        c.fg_dark = "#91A4BB"
        c.fg_float = "#F4F8FF"
        c.fg_gutter = "#60758C"
        c.blue = "#39A9FF"
        c.cyan = "#5BC0FF"
        c.green = "#7BC29A"
        c.magenta = "#8A7BC2"
        c.orange = "#E8A06A"
        c.red = "#E86A6A"
        c.yellow = "#D9B66A"
        c.comment = "#60758C"
      end,
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd.colorscheme("tokyonight")
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "tokyonight" },
  },
}
