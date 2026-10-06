# Log

## 2026-10-06 17:47 CEST — Plain bar face

Request (user): PingScope's bar icon (a warning triangle) and its green/yellow/red number are hard
to read against the bar, whose colours change with the theme; keep the plugin, simpler face.

- Forked from sierrab1989/omarchy-pingscope at 3881504 (1.4.2). New id
  `io.github.stefanoconiglio.pingscope` (manifest, `moduleName`, `ipcTarget`), name
  "PingScope (plain)", default site `google.com`.
- Panel.qml: the hand-made bar face (glyph + coloured number) replaced by the stock
  `WidgetButton`, as in the Memory widget: text in `bar.barForeground`, `active` (the theme's
  urgent colour) when the focused site is down or at 100 ms or more (PingScope's red threshold).
  Label `barLabel()`: "58 ms", "1.2 s", "no net", padded to six characters (monospace bar font)
  so the width never changes. The panel header shows a globe (󰖟) instead of the warning sign.
- Checked on the live bar (screenshots): "3 ms" in the bar colour; pointed for a few seconds at
  192.0.2.1 (TEST-NET-1, never answers), "no net" in the urgent colour; back to google.com.
  `omarchy plugin validate` passes; no QML error from the plugin in the shell's journal.

## 2026-10-06 17:55 CEST — Coloured text back, on a pill

Request (user): keep the green / yellow / red text, which tells the speed, but make the widget
stand out whatever the theme: a background, with a border.

- Bar face hand-made again (WidgetButton draws text only), with PingScope's click-target and
  tooltip handling: a Rectangle pill, fill `#18181b`, border in `bar.barForeground` (1.5 px
  scaled), radius half its height; inside, `barLabel()` in bold caption size, coloured by
  `statusColor()` (PingScope's `#22c55e` / `#eab308` / `#ef4444`; `#e4e4e7` and `#a1a1aa` for
  the neutral and idle states). Width from a TextMetrics of "888 ms", so it never changes.
  Why it stands out on any theme: the dark fill against a light bar, the outline (the theme's
  bar text colour, contrasting with the bar by design) against a dark one; the three colours
  are readable on the dark fill.
- Mistake: the Text's id was first `faceLabel`, the name of an existing function; renamed
  `pillLabel` before loading.
- Reloading: an edit inside the symlinked plugin folder is not picked up, and neither is
  `omarchy-shell shell rescanPlugins` enough (it kept the old QML); `omarchy restart shell` is.
- Checked on the live bar (light theme, screenshots): google.com "3 ms" green; time.nist.gov
  "143 ms" red; 192.0.2.1 "no net" red; same width each time; back to google.com. Not seen on a
  dark theme.

## 2026-10-06 18:00 CEST — Bigger number

Request (user): a bigger font for the latency in the pill. `Style.font.title` (14 px) instead of
`caption` (10 px; the bar's other text is `body`, 12 px); the pill's vertical padding down to
`Style.space(2)` and its height capped at the bar's size minus 2 so it fits the 26 px bar.
Checked on the live bar after `omarchy restart shell`: "3 ms" green and "142 ms" red
(time.nist.gov) inside the bar's height.
