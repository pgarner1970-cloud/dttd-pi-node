# USB Audio Notes

Use stable ALSA device naming for the AB13X USB Audio adapter:

```text
plughw:Audio,0
```

Do not rely on card numbers such as `plughw:1,0` or `plughw:2,0`.

The AB13X adapter exposes a `PCM` mixer control, not `Master`.

Local commands:

```bash
sudo /opt/dttd-pi-node/scripts/set-usb-audio.sh
sudo /opt/dttd-pi-node/scripts/set-volume.sh 85
```

`set-volume.sh` changes the live ALSA `PCM` mixer level and does not restart Raspotify.
