# orbital.notifications — notification center bell

Kind: `bar-widget`. Entry: `BarWidget.qml` (history popout: `Panel.qml`).

A bell with an unread badge. Click opens the notification history this plugin
keeps itself, newest first: sender, subject, message, relative age, and the
sender's icon or picture when one survived.

## Why it keeps its own archive

Omarchy already records every popup on disk
(`~/.local/state/omarchy/notifications/`, moved to `history/` when the toast
leaves the screen), but that history holds 10 files and deletes the 11th —
and the icon with it. This widget polls those directories, merges what it
finds into its own archive at
`~/.local/state/omarchy/orbital-notifications/archive.jsonl` (capped by the
`keepDays` / `maxItems` settings, whichever hits first), and copies referenced
pictures into its own `images/` dir before omarchy's trim deletes them.

The archive is a file, not a service, on purpose: under a plugin bar such as
`orbital.floating-bar` a widget's `bar.shell.serviceFor()` cannot reach another
plugin's live service object (the facade is scoped to the bar plugin's own
id), so cross-plugin state lives on disk. File watchers keep every
per-monitor instance converged; appends are keyed (`timestamp-originalId`) so
concurrent writers dedupe instead of duplicating.

On first run the widget performs a one-time, read-only import of the retired
`jankeesvw.notification-center` archive (entries are copied, never moved; that
directory is never written to), then records an `imported` marker.

## Do Not Disturb

The bell dims while DND is on. The toggle goes through the first-party proxy
`bar.shell.firstPartyServiceFor("omarchy.notifications")` — the same narrow
proxy the stock bar's own Dnd indicator uses — which the floating bar's shell
facade provides. Under the stock bar a third-party widget gets a
capability-less facade, so the proxy is null there: the panel still shows the
real state (read from omarchy's `notifications.json`) but the toggle stays
disabled. The panel never touches `serviceFor()`.

## Behavior

- Opening the center marks everything seen (the badge clears on the click).
- `Clear all` empties the archive; `×` dismisses one row.
- Text is English via `tr()`, with pt-BR in `orbital.ui/I18n.js`. Icons are
  SVG (`notifications-bell-symbolic` in `orbital.ui/icons/`); never emoji.
- No loading state exists: the list renders immediately, possibly empty
  (`No notifications yet`). Failures degrade to that empty state, never a
  stuck spinner.
- The list shows the newest 300 rows of the archive; the archive itself keeps
  up to `maxItems` (default 1000).

## Verifying without the GUI (`IpcHandler: orbital.notifications`)

- `state` → `{"total":N,"unread":M,"newest":"..."}`.
- `seed <count>` → appends deterministic synthetic entries (app
  `orbital-seed`) for volume checks; `clear` removes everything.
- `reload` → re-polls omarchy's directories now on every monitor.
- `dismiss <key>` → removes one entry.
- `open` / `close` / `toggle` follow the standard panel routing.

Example: `notify-send "orbital test" "hello"`, wait ~5 s, then check the bell
badge and `state`. Note the shell caches QML by URL for the session, so this
plugin (all new file names) only takes effect after a shell restart.

## Tests

- `bash scripts/test-notifications-model.sh` — node unit tests for
  `NotificationsModel.js` (shapes, merge/dedupe, trim caps, unread, filter,
  relative age, archive round-trip, image-copy planning, seed determinism, and
  a 5000-entry ingest well under a second).
- `bash scripts/test-qml-lint.sh`, `bash scripts/test-i18n.sh` — repo gates.
