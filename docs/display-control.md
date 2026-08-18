# DTTD Display Control

The HDMI display now uses one persistent Chromium kiosk process. Normal event screen changes happen inside the live-display web application rather than by closing and relaunching Chromium.

## Normal screen modes

The DJ portal controls these per-node modes through the shared web application state:

- **Show Live** — normal live event display/rotation.
- **Show Logo** — black holding screen with website QR, DTTD logo and Facebook QR.
- **Blank** — pure black screen.

Switching Live / Logo / Blank does **not** stop or restart Chromium.

## Process controls

The node agent retains true browser recovery controls:

- `display_start` — launch Chromium if it is not already running. Payload render profile: `lite` or `full`.
- `display_restart` — deliberately stop and relaunch Chromium using the requested render profile.
- `display_stop` — deliberately close the HDMI Chromium process.
- `display_status` — return JSON browser status.

Legacy `display_logo`, `display_blank` and `display_wake` commands are retained safely for compatibility but no longer restart Chromium; normal mode selection is handled by the portal/web page.

The display controls do not stop `librespot`, `raspotify`, MPD or local music playback.

## Persistent display URL

The agent appends its node key to the configured display URL, for example:

```text
https://live.dancethruthedecades.co.uk/?mode=lite&node=dmx-desk-a
```

The live page polls the display-control state for that node and overlays Live / Logo / Blank immediately without navigating away.

## Boot policy

`scripts/configure-display-autostart.sh` applies the current event policy:

- **Deck A / dmx-desk-a** — DTTD Chromium display starts automatically with the desktop session.
- **Deck B / dmx-desk-b** — no automatic DTTD Chromium launch; all display-control capability remains available from the DJ portal.

The update script reapplies this policy after Pi-node updates and removes legacy direct DTTD Chromium lines from the user's labwc autostart file when present.

## Chromium binary

The agent auto-detects Chromium in this order:

1. `DISPLAY_BROWSER` from `/etc/dmx-node.conf`
2. `/usr/lib/chromium/chromium`
3. `/usr/bin/chromium`
4. `/usr/bin/chromium-browser`

On low-memory Raspberry Pis, `/usr/lib/chromium/chromium` avoids the Raspberry Pi browser launcher prompt.

## Deck-specific boot policy

The display policy is enforced by `scripts/configure-display-autostart.sh` on install and update:

- `dmx-desk-a`: default target is `graphical.target`; the DTTD kiosk starts automatically with the `disco` desktop session.
- `dmx-desk-b`: default target is `multi-user.target`; no DTTD kiosk is auto-launched after reboot. `Start Display` invokes `scripts/start-display-session.sh`, starts `graphical.target` for that session, waits for X11 display `:0`, and then starts Chromium.
- `Stop Display` closes Chromium only. It does not change Deck B's boot target; the next reboot returns it to headless mode.
- `unclutter` is installed and started with the kiosk so the mouse pointer disappears during Live, Logo and Blank screens.
