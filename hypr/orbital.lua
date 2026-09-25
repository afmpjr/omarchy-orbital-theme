-- Orbital: Hyprland side of the theme. `omarchy theme install` drops theme
-- .lua files, so this lives outside the theme and is loaded from
-- ~/.config/hypr/hyprland.lua by install.sh (`require("hypr.orbital")`, last).

-- Glass: blur only behind the translucent Orbital popups (namespaces
-- orbital-*) and Omarchy KeyboardPanel popups. ignore_alpha keeps the blur off
-- their fully transparent full-screen surface. Kept light (2 passes) for iGPUs.
hl.config({ decoration = { blur = { enabled = true, size = 6, passes = 2, noise = 0.02 } } })
hl.layer_rule({ match = { namespace = "^(orbital-.*|omarchy-keyboard-panel)$" }, blur = true, ignore_alpha = 0.6 })

-- Active border follows the accent picker (orbital.appearance), which writes
-- the color into this state file; falls back to the default blue.
local activeBorder = "rgba(7cc8ff44)"
do
  local f = io.open(os.getenv("HOME") .. "/.local/state/omarchy/orbital-accent.json", "r")
  if f then
    local m = f:read("*a"):match('"border"%s*:%s*"(rgba%(%x+%))"')
    f:close()
    if m then activeBorder = m end
  end
end

-- Rounded windows, hairline border, soft shadow. (No global window opacity:
-- browsers and video stay opaque.)
hl.config({
  general = {
    border_size = 1,
    col = { active_border = activeBorder, inactive_border = "rgba(ffffff14)" },
  },
  decoration = {
    rounding = 14,
    rounding_power = 2,
    shadow = { enabled = true, range = 28, render_power = 3, color = "rgba(00000070)" },
  },
})

-- Terminals are glass (translucent over the blurred wallpaper).
o.window({ class = "^(com\\.mitchellh\\.ghostty|foot|Alacritty|kitty)$" }, { opacity = "0.88 0.82" })

-- Animations: eased horizontal workspace slide (CSS easeInOutCubic).
hl.curve("orbitalEase", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1 } } })
hl.curve("orbitalInOut", { type = "bezier", points = { { 0.65, 0 }, { 0.35, 1 } } })
hl.curve("orbitalSnap", { type = "bezier", points = { { 0.34, 1.56 }, { 0.64, 1 } } })
hl.curve("smoothFade", { type = "bezier", points = { { 0.25, 0.46 }, { 0.45, 0.94 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "orbitalEase", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3.5, bezier = "orbitalEase", style = "slide" })
hl.animation({ leaf = "border", enabled = true, speed = 4, bezier = "smoothFade" })
hl.animation({ leaf = "fade", enabled = true, speed = 3, bezier = "smoothFade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4.5, bezier = "orbitalInOut", style = "slide" })
hl.animation({ leaf = "layers", enabled = true, speed = 3, bezier = "orbitalSnap" })

-- With workspace_wraparound on, Hyprland treats "first -> a later workspace"
-- as a wrap and reverses the slide; off keeps the direction consistent.
hl.config({ animations = { workspace_wraparound = false } })
