# orbital.worldclock — world clock, alarms, timer

One overlay with three tabs: **Clock** (other time zones), **Alarms** and **Timer**.

- **Kind:** `overlay` · **Entry point:** `WorldClock.qml` · **Version:** 1.0.0
- **Installed by:** `install.sh` (always, as an overlay)

## Cities

Added by time-zone name (`Europe/Dublin`), so there is no city database to update and no network call. The list of added
zones is kept by the plugin; the first entry is treated as the local reference.

## Tabs

Switch with the tab bar, or cycle from the keyboard with the tab-order helper. Alarms and the timer are independent tabs, so
a running timer is not lost when you look at the clock.

## License

MIT (see the repository `LICENSE`).
