-- Orbital window gaps. Loaded BEFORE Omarchy's toggles (install.sh inserts the
-- require ahead of `default.hypr.toggles`), so Super+Shift+Backspace (window
-- gaps toggle) still wins, and the floating bar follows it.
hl.config({ general = { gaps_in = 8, gaps_out = 12 } })
