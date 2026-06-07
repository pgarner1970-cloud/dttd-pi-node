# DTTD Display Control

The node agent can now manage the HDMI display browser as well as the player service.

Supported portal commands:

- `display_start` - start the display browser using the requested mode payload (`lite` or `full`).
- `display_restart` - restart the display browser using the requested mode payload.
- `display_lite` - start/restart the display in lite mode.
- `display_full` - start/restart the display in full mode.
- `display_stop` - stop the HDMI display browser only.
- `display_blank` - ask the HDMI output to sleep/blank.
- `display_wake` - wake the HDMI output.
- `display_status` - return JSON status for the display browser.

The display controls do not stop `librespot`, `raspotify`, MPD or local music playback.

Recommended low-memory Raspberry Pi URL:

```text
https://live.dancethruthedecades.co.uk/?mode=lite
```

The agent auto-detects Chromium in this order:

1. `DISPLAY_BROWSER` from `/etc/dmx-node.conf`
2. `/usr/lib/chromium/chromium`
3. `/usr/bin/chromium`
4. `/usr/bin/chromium-browser`

On low-memory Raspberry Pis, `/usr/lib/chromium/chromium` avoids the Raspberry Pi browser launcher prompt.
