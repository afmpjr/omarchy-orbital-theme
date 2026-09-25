-- Four-finger horizontal swipe on the touchpad switches workspaces. Loaded by install.sh --full
-- (skipped with --no-gestures, or when your own config already defines this gesture).
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
