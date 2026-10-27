# Orbital Doctor Widget (`orbital.doctor`)

- **Kind:** `bar-widget`
- **Entry Point:** `BarWidget.qml` (Indicator) & `Panel.qml` (Diagnostics Flyout)
- **Model:** `DoctorModel.js` (Pure logic, Qt-free, unit-tested under Node.js)
- **Theme:** Orbital (Modern Sci-Fi OS)

---

## 1. Overview & Architecture

The `orbital.doctor` plugin provides situational awareness and diagnostics flyouts for the Omarchy workstation health daemon (`omarchy-doctor`).

It integrates natively with the Orbital desktop shell (`omarchy-shell` / Quickshell), conforming strictly to the Orbital Glass aesthetic, design tokens (`colors.toml`, `shell.toml`), and accessibility standards.

### Key Architectural Tenets:
1. **Passive Situational Awareness:** The bar indicator stays minimal and quiet when the system is healthy. Alerts are indicated via reactive status dots (amber for warnings, pulsing red for critical states).
2. **Strict Vector SVG Policy (Zero Emojis):** Every icon is an SVG asset rendered via `OrbitalUi.OrbitalIcon`. Emojis and emoticons are strictly prohibited in code and interface.
3. **Operational Safety (Zero Destructive GUI Buttons):** The GUI is exclusively informative. It never triggers `--apply` cleanups directly. Interactive buttons dispatch dedicated floating terminals (`foot` or `omarchy-launch-floating-terminal-with-presentation`) running safe inspection (`scan --full`) or simulation (`fix --dry-run`).
4. **I/O Resilience:** Safe parsing (`DoctorModel.js`) ensures that truncated JSON, missing files, or locked handles never crash the shell or degrade compositor performance.

---

## 2. File Structure

```
plugins/orbital.doctor/
├── manifest.json       # Plugin metadata and bar-widget declaration
├── BarWidget.qml       # Compact bar indicator (32x38px, SVG icon, status dot)
├── Panel.qml           # Expandable diagnostics flyout (KeyboardPanel, 440px wide)
├── DoctorModel.js      # Pure data parser, PSI calculations, formatters
└── README.md           # Technical documentation and integration guide
```

---

## 3. Data Ingestion & State Contract

The widget observes `${XDG_STATE_HOME:-~/.local/state}/omarchy-doctor/state.json`, which is periodically written by the resident daemon `omarchy-doctor watch`.

- **Atomic Writes:** The daemon updates `state.json` via POSIX `os.replace` preceded by `fsync`, preventing partial or torn reads.
- **Reactive Observation:** Loaded via `Quickshell.Io.FileView` with `watchChanges: true` and a relaxed 3-second fallback timer to pick up inode changes seamlessly.
- **Stale Detection:** If `state.json` has not been refreshed within 60 seconds (>2 monitor cycles), the widget automatically shifts from `ok` to `stale` (dimmed icon and muted dot).

---

## 4. Visual State Matrix

| State | Condition | Bar Indicator | Tooltip | Flyout Pill Tag |
| :--- | :--- | :--- | :--- | :--- |
| **OK** | `status: "ok"`, disk <80%, PSI <15%, 0 failed units | Normal icon (`#F4F8FF`), dot hidden | `"omarchy-doctor: Sistema Saudável"` | Green `"SISTEMA SAUDÁVEL"` |
| **Warning** | `status: "warning"` OR disk 80–89% OR PSI 15–24% | Amber dot (`#D9B66A`) | `"omarchy-doctor: Atenção (Disco em 84%)"` | Amber `"ATENÇÃO NECESSÁRIA"` |
| **Critical** | `status: "critical"` OR disk >=90% OR failed units | Pulsing red dot (`#E86A6A`) | `"omarchy-doctor: CRÍTICO (1 unit falha)"` | Red `"CONDIÇÃO CRÍTICA"` |
| **Stale** | Data older than 60s | Dimmed icon (45%), muted dot (`#60758C`) | `"omarchy-doctor: Dados Desatualizados"` | Grey `"DADOS DESATUALIZADOS"` |
| **Stopped** | `state.json` missing OR `service.active: false` | Dimmed icon (35%), muted dot | `"omarchy-doctor: Monitor Inativo"` | Muted `"MONITOR DESCONECTADO"` |

---

## 5. Keyboard Navigation & Accessibility

- **Open/Toggle:** Left-click on the bar icon or invoke via IPC `omarchy-shell shell toggle orbital.doctor`.
- **Keyboard Focus:** Press `Tab` or `Shift+Tab` to cycle between action buttons ("Abrir Relatório" and "Simular Limpeza").
- **Focus Rings:** Focused buttons receive a distinct 2px outline in accent blue (`#39A9FF`).
- **Activation:** Press `Return` or `Space` on a focused button to trigger the terminal action.
- **Dismissal:** Press `Escape` to immediately close the flyout and return focus cleanly to the desktop.

---

## 6. Unit Testing

The pure logic model `DoctorModel.js` is covered by automated unit tests validating against canonical test fixtures:

```bash
# Execute unit tests
bash scripts/test-doctor-model.sh
```

---

## 7. IPC Commands

The widget registers the `orbital.doctor` IPC target:

```bash
# Toggle the diagnostics flyout
omarchy-shell shell toggle orbital.doctor

# Explicit show/hide
omarchy-shell shell summon orbital.doctor '{}'
omarchy-shell shell hide orbital.doctor

# Force state reload
omarchy-shell shell run orbital.doctor reload
```
