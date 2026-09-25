# Super tap = app drawer (optional)

With [keyd](https://github.com/rvaiya/keyd), a bare tap on Super can send `SUPER+S`, which `hypr/orbital-bindings.lua`
binds to the Orbital launcher:

```
[ids]
*

[global]
disable_modifier_guard = 1

[main]
# Super (meta): tap sends SUPER+S (opens the app drawer);
# hold acts as the meta modifier (SUPER+... shortcuts).
meta = overload(tapmeta, M-s)

[tapmeta:M]
```

Then `sudo systemctl enable --now keyd`. Holding Super still works as a modifier. Not installed automatically (needs root).
