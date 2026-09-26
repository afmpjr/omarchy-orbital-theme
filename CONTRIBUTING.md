# Contributing

Thanks for looking. Orbital is an Omarchy theme plus a set of Quickshell plugins and an installer; small, focused changes are easiest to review.

## Before you open a pull request

- Run the tests that need nothing but this repo: `scripts/test-install.sh` (sandbox: fake `HOME`, stubbed `omarchy`/`quickshell`/`hyprctl`, it never
  touches your session), `scripts/test-i18n.sh` and `scripts/test-keyboard-model.sh` (needs `node`).
- Anything that changes the installer or a plugin's look should also be checked on a clean Omarchy VM. `scripts/e2e-*.sh` drive one
  (they need a checkout of the separate omarchy-testbed harness in `TESTBED`); if you cannot run them, say so in the PR.
- Keep the installer all-or-nothing and idempotent: it must roll back on any failure, never overwrite what you own, and never add a second
  copy of something your Hyprland config already does.
- User-visible text goes through `tr("...")` with an entry in `plugins/orbital.ui/I18n.js` (English is the source, pt-BR the translation);
  `scripts/test-i18n.sh` fails if the two drift.
- Icons are SVG, never emoji. Do not add wallpapers or fonts without a compatible license (see `CREDITS.md`).

## Reporting a bug

Use the bug report template. Include your Omarchy version (`omarchy version`), what you ran (`./install.sh` flags) and the output of
`omarchy debug --no-sudo --print`, without secrets.

## License

By contributing you agree your work is released under the MIT License of this repository.
