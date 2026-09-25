-- Orbital — Hyprland 4.x (Quattro) — spec §28 §22 §23
local activeBorderColor = {
  colors = { "rgb(57,169,255)", "rgb(91,192,255)", "rgb(168,187,212)" },
  angle = 45,
}
local inactiveBorderColor = "rgba(255,255,255,0.08)"

hl.config({
  general = {
    col = {
      active_border = activeBorderColor,
      inactive_border = inactiveBorderColor,
    },
    border_size = 2,
    gaps_in = 8,
    gaps_out = 12,
  },
  group = {
    col = {
      border_active = activeBorderColor,
      border_inactive = inactiveBorderColor,
    },
  },
  decoration = {
    rounding = 16,
    rounding_power = 2.5,
    blur = {
      enabled = true,
      size = 8,
      passes = 3,
      noise = 0.018,
      contrast = 0.88,
      brightness = 0.92,
      vibrancy = 0.08,
      vibrancy_darkness = 0.55,
      ignore_opacity = true,
    },
    shadow = {
      enabled = true,
      range = 28,
      render_power = 3,
      color = "rgba(0,0,0,0.40)",
    },
  },
  animations = {
    enabled = true,
  },
})

hl.curve("orbitalEase", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1 } } })
-- CSS easeInOutCubic: gentle start AND end (workspace slide only).
hl.curve("orbitalInOut", { type = "bezier", points = { { 0.65, 0 }, { 0.35, 1 } } })
hl.curve("orbitalSnap", { type = "bezier", points = { { 0.34, 1.56 }, { 0.64, 1 } } })
hl.curve("smoothFade", { type = "bezier", points = { { 0.25, 0.46 }, { 0.45, 0.94 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "orbitalEase", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3.5, bezier = "orbitalEase", style = "slide" })
hl.animation({ leaf = "border", enabled = true, speed = 4, bezier = "smoothFade" })
hl.animation({ leaf = "fade", enabled = true, speed = 3, bezier = "smoothFade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4.5, bezier = "orbitalInOut", style = "slide" })
hl.animation({ leaf = "layers", enabled = true, speed = 3, bezier = "orbitalSnap" })
