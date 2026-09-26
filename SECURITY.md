# Security

Orbital runs code in your Quickshell session and edits files under `~/.config/omarchy`, `~/.config/hypr` and `~/.config/systemd/user`, so
please report anything that could run untrusted input, leak local data or leave a system unusable (for example a lock-screen or Hyprland
config problem).

**How to report:** open a private security advisory on GitHub (Security tab of this repository), or, if that is not available, an issue that
says "security" without the details, and I will reply with a private channel. Please do not post exploit details publicly first.

Scope: this repository only. Bugs in Omarchy, Hyprland or Quickshell themselves belong to those projects.

The installer never sends data anywhere; the only network use is the weather in the clock panel (`wttr.in`) and what you run yourself.
