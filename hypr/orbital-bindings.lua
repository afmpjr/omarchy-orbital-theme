-- Orbital app drawer on Super+S (Super *tap* too, if keyd forwards it as
-- SUPER+S; see docs/keyd.md). Loaded by install.sh --full.
hl.unbind("SUPER + S")
o.bind("SUPER + S", "Search (Orbital Launcher)", "omarchy-shell shell toggle orbital.launcher")
