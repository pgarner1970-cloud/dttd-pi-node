# USB Audio Setup

Plug the USB sound card into the Raspberry Pi, then run:

```bash
sudo /opt/dttd-pi-node/scripts/set-usb-audio.sh
```

The script will detect the first obvious USB ALSA playback device and set Raspotify/librespot to use it.

To specify a device manually:

```bash
sudo /opt/dttd-pi-node/scripts/set-usb-audio.sh plughw:1,0
```

Check the active Raspotify environment:

```bash
sudo systemctl show raspotify -p Environment --no-pager -l
```

You should see something like:

```text
LIBRESPOT_BACKEND=alsa
LIBRESPOT_DEVICE=plughw:1,0
```

Test by selecting the Pi in Spotify and playing audio.
