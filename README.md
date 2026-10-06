# PingScope (pill)

A fork of [PingScope](https://github.com/sierrab1989/omarchy-pingscope) (MIT) with a bar face
that stands out on every Omarchy theme. The bar shows the focused site's latency, `58 ms` or
`no net`, in PingScope's colours (green up to 50 ms, yellow up to 99 ms, red from 100 ms and when
down) on a dark pill outlined in the bar's own text colour: the fill sets it off from a light bar
and keeps the colours readable, the outline sets it off from a dark one. The pill keeps its width
as the number changes. The panel is PingScope's, with a globe in place of the warning sign in its
header. Plugin id `io.github.stefanoconiglio.pingscope`; default site `google.com`.

The original README follows.

---

# PingScope

PingScope is an Omarchy bar widget that monitors current ICMP latency for up
to four hosts. It keeps every configured site's latest reading visible in a
compact panel and highlights response time at a glance.

![PingScope preview](preview.png)

## Features

- Shows current latency beside every configured host.
- Colors readings green from 1–50 ms, yellow from 51–99 ms, and red from
  100 ms upward.
- Marks unreachable hosts in red.
- Switches all probes between IPv4 and IPv6 immediately.
- Stops and starts probes without losing configuration.
- Continues sampling while the panel is closed.
- Supports up to four hostnames and follows the active Omarchy theme.

## Requirements

- Omarchy with Quickshell plugin support.
- The system `ping` command, normally provided by `iputils` on Omarchy.

PingScope has no external service, account, API key, or downloaded dependency.

## Installation

Install and enable PingScope from its public GitHub repository:

```bash
omarchy plugin add https://github.com/sierrab1989/omarchy-pingscope.git --enable
```

Choose the right bar section if Omarchy asks for placement. The manifest also
declares the right section as its default.

## Usage

- **Left-click** the bar widget to open PingScope.
- **Right-click** the bar widget to cycle the focused host.
- **Middle-click** the bar widget to refresh every host immediately.
- Hover over the bar widget to see all current readings.
- Use **IPv4 → IPv6** or **IPv6 → IPv4** to switch protocols immediately.
- Use **Stop** or **Start** to control all probes immediately.

The **Save** button applies only to changes in the Sites section. Protocol and
run-state controls apply as soon as they are pressed.

## Latency colors

| Displayed latency | Color |
|-------------------|-------|
| 1–50 ms | Green |
| 51–99 ms | Yellow |
| 100 ms or higher | Red |
| Unreachable | Red |

## Configuration

Open the panel to add, change, or remove hostnames, then select **Save**.
PingScope stores its settings in the widget's entry in
`~/.config/omarchy/shell.json`:

```json
{
  "id": "pingscope.latency",
  "sites": ["google.com", "github.com", "cloudflare.com", "reddit.com"],
  "focusedSite": 0,
  "closedRefreshSec": 1,
  "openRefreshSec": 1,
  "ipVersion": 4,
  "running": true
}
```

| Key | Meaning | Default |
|-----|---------|---------|
| `sites` | Hostnames to ping; duplicates are removed | Four common sites |
| `focusedSite` | Site displayed in the compact bar widget | `0` |
| `closedRefreshSec` | Probe interval while the panel is closed | `1` |
| `openRefreshSec` | Probe interval while the panel is open | `1` |
| `ipVersion` | Ping protocol: `4` or `6` | `4` |
| `running` | Whether probes are active | `true` |

## Updates

Update a Git-managed installation with:

```bash
omarchy plugin update pingscope.latency
```

## Removal

Remove PingScope with:

```bash
omarchy plugin remove pingscope.latency
```

Removing the plugin removes its installed source and bar entry. It does not
remove the system `ping` command or change network configuration.

## Privacy and security

PingScope runs `ping -4` or `ping -6` once per configured host at the selected
interval. ICMP traffic is sent only to those hosts. The plugin does not use
`sudo`, read credentials, collect telemetry, download code, or send results to
an external service. Hostnames and widget settings are stored by Omarchy in
`~/.config/omarchy/shell.json`.

Omarchy community plugins run with the current user's permissions. Review the
source before enabling any third-party plugin.

## Development

Validate a checkout before testing or publishing:

```bash
omarchy plugin validate .
```

The plugin files are:

| File | Purpose |
|------|---------|
| `manifest.json` | Omarchy plugin manifest for `pingscope.latency` |
| `Panel.qml` | Bar face, popup panel, controls, and configuration UI |
| `SitePinger.qml` | Repeating per-host `ping` process |
| `PingModel.js` | Host normalization, ping parsing, and status ranges |

## License

PingScope is available under the [MIT License](LICENSE).
