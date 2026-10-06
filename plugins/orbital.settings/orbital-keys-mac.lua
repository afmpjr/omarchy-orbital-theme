-- Orbital Mac-style application shortcuts for Linux apps.
-- Super is Command (⌘); Alt remains Option (⌥). App shortcuts are sent as Ctrl.

local app_shortcuts = {
  { "A", "A" }, { "C", "C" }, { "X", "X" }, { "V", "V" },
  { "Z", "Z" }, { "SHIFT + Z", "Z" }, { "S", "S" }, { "O", "O" },
  { "N", "N" }, { "W", "W" }, { "Q", "Q" }, { "F", "F" },
  { "P", "P" }, { "R", "R" }, { "L", "L" }, { "I", "I" },
}

local function bind_app_shortcut(chord, key)
  hl.unbind("SUPER + " .. chord)
  hl.bind("SUPER + " .. chord, function()
    hl.dispatch(hl.dsp.send_shortcut({ mods = "CTRL", key = key }))
  end)
end

for _, shortcut in ipairs(app_shortcuts) do
  bind_app_shortcut(shortcut[1], shortcut[2])
end

-- Keep Omarchy actions available on a secondary chord while their usual keys
-- act as Command shortcuts in applications.
o.bind("SUPER + ALT + A", "Quick settings (audio)", "omarchy-shell shell toggle omarchy.audio")
o.bind("SUPER + ALT + C", "Capture menu", "omarchy-menu toggle capture")
o.bind("SUPER + ALT + V", "Clipboard history", "omarchy-shell shell toggle omarchy.clipboard")
o.bind("SUPER + ALT + X", "Quick-link menu", "omarchy-menu toggle system")
o.bind("SUPER + ALT + S", "Search (Orbital Launcher)", "omarchy-shell shell toggle orbital.launcher")
do
  local home = os.getenv("HOME") or ""
  local f = io.open(home .. "/.config/omarchy/plugins/jankeesvw.notification-center/manifest.json", "r")
  if f then
    f:close()
    o.bind("SUPER + ALT + N", "Notification center", "omarchy-shell jankeesvw.notification-center toggle")
  end
end
o.bind("SUPER + ALT + P", "Projection (display panel)", "omarchy-shell shell toggle omarchy.monitor")
o.bind("SUPER + ALT + R", "Run", "omarchy-menu toggle apps")
o.bind("SUPER + ALT + I", "System menu", "omarchy-menu toggle system")
o.bind("SUPER + ALT + SHIFT + L", "Lock system", "omarchy-system-lock")
