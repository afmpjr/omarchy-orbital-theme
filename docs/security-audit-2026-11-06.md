# Security Audit & Remediation Report (2026-11-06)

## Scope
- **Repository**: `afmpjr/omarchy-orbital-theme`
- **Visibility**: `PUBLIC` (GitHub Secret Scanning & Push Protection: `enabled`)
- **Scanner**: `repo-security-audit` (`/mnt/dados/projects/scripts/repo-security-audit.py`) & `scripts/security-check.sh`

## Findings & Remediations

| ID | Severity | Location | Finding | Status |
| :--- | :---: | :--- | :--- | :---: |
| **ORB-01** | Medium | `plugins/orbital.account/Account.qml:112` | Unquoted `$HOME` path concatenation in `Util.execDetached` when invoking `orbital-widgets-lock --toggle`. | **Fixed** (replaced with `Util.execArgv([..., "--toggle"])`) |
| **ORB-02** | Medium | `plugins/orbital.appearance/Appearance.qml:57,63` | Concatenated `root.script` and `name` inside `["bash", "-c", ...]` instead of passing argv directly. | **Fixed** (`[root.script, String(name)]` and `[root.script, "current"]`) |
| **ORB-03** | Low | `plugins/orbital.run/Run.qml:322` | Concatenated user command directly into `bash -lc` wrapper string instead of positional parameter `$1`. | **Fixed** (`eval -- "$1"` with positional arg) |
| **ORB-04** | Medium | `scripts/security-check.sh` | Security check previously only covered `plugins/orbital.lockscreen`. Added repository-wide `scripts/security-check.sh` covering all plugins. | **Fixed** |
| **ORB-05** | Info | Tracked files & Git History | Zero leaked secrets, tokens, or private keys in working tree or commit history. | **Clean** |
