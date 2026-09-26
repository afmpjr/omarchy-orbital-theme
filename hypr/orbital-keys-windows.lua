-- Orbital: Windows-style shortcuts (opt-in: install.sh --windows-keys).
--
-- Super is the Windows key. This replaces some Omarchy defaults, so read the list:
--   Super+L            lock the screen                     (layout toggle moves to Super+Alt+L)
--   Super+R            run / app menu
--   Super+A            audio panel        Super+N notification center (if installed)
--   Super+I            system menu        Super+X quick-link menu    Ctrl+Alt+Del system menu
--   Super+P            display panel      (pseudo window moves to Super+Alt+P)
--   Super+Ctrl+D       new empty workspace
--   Super+C            capture menu       Super+Shift+S region screenshot
--   Super+V            clipboard history  (replaces Omarchy's universal paste)
--   Super+.            emojis             Super+H dictation (if voxtype is installed)
--   Alt+F4 close       F11 full screen
--   Super+Alt+S        toggle scratchpad  Super+Shift+Alt+S move window to it
-- Super+S (search) is bound by orbital-bindings.lua. Check for clashes with your own keys:
--   scripts/keybind-audit.sh          Live list: omarchy menu keybindings --print
-- Remove this file and its require() line in hyprland.lua (or run install.sh --uninstall) to go back.

-- System
hl.unbind("SUPER + L")
o.bind("SUPER + L", "Lock system", "omarchy-system-lock")
o.bind("SUPER + ALT + L", "Toggle workspace layout", "omarchy-hyprland-workspace-layout-toggle")
o.bind("SUPER + R", "Run", "omarchy-menu toggle apps")
o.bind("SUPER + A", "Quick settings (audio)", "omarchy-shell shell toggle omarchy.audio")
o.bind("SUPER + I", "System menu", "omarchy-menu toggle system")
hl.unbind("SUPER + P")
o.bind("SUPER + P", "Projection (display panel)", "omarchy-shell shell toggle omarchy.monitor")
o.bind("SUPER + ALT + P", "Pseudo window", hl.dsp.window.pseudo())
hl.unbind("SUPER + CTRL + D")
o.bind("SUPER + CTRL + D", "New empty workspace", hl.dsp.focus({ workspace = "empty" }))
hl.unbind("CTRL + ALT + DELETE")
o.bind("CTRL + ALT + DELETE", "System menu", "omarchy-menu toggle system")
o.bind("CTRL + SHIFT + ALT + DELETE", "Close all windows", "omarchy-hyprland-window-close-all")

-- Notification center, only when that plugin is installed
do
  local home = os.getenv("HOME") or ""
  local f = io.open(home .. "/.config/omarchy/plugins/jankeesvw.notification-center/manifest.json", "r")
  if f then
    f:close()
    o.bind("SUPER + N", "Notification center", "omarchy-shell jankeesvw.notification-center toggle")
  end
end

-- Capture, clipboard, emojis
hl.unbind("SUPER + C")
o.bind("SUPER + C", "Capture menu", "omarchy-menu toggle capture")
hl.unbind("SUPER + V")
o.bind("SUPER + V", "Clipboard history", "omarchy-shell shell toggle omarchy.clipboard")
hl.unbind("SUPER + X")
o.bind("SUPER + X", "Quick-link menu", "omarchy-menu toggle system")
hl.unbind("SUPER + SHIFT + S")
o.bind("SUPER + SHIFT + S", "Snipping (region screenshot)", "omarchy-capture-screenshot region")
hl.unbind("SUPER + PERIOD")
o.bind("SUPER + PERIOD", "Emojis", "omarchy-shell shell toggle omarchy.emojis")
if o.cmd_present("voxtype") then
  o.bind("SUPER + H", "Toggle dictation", "voxtype record toggle")
end

-- Windows
o.bind("ALT + F4", "Close window", hl.dsp.window.close())
o.bind("F11", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.unbind("SUPER + ALT + S")
o.bind("SUPER + ALT + S", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
hl.unbind("SUPER + SHIFT + ALT + S")
o.bind("SUPER + SHIFT + ALT + S", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))
