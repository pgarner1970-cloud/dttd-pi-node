# USB Audio Notes

For the AB13X USB Audio adapter, use the stable ALSA device name:

```text
plughw:Audio,0
```

Do not rely on card numbers such as `plughw:1,0` or `plughw:2,0`, because HDMI/card numbering changes depending on whether the USB adapter is present during boot.

The AB13X adapter exposes a `PCM` mixer control, not `Master`.

Local commands:

```bash
sudo /opt/dttd-pi-node/scripts/set-usb-audio.sh
sudo /opt/dttd-pi-node/scripts/set-volume.sh 85
```
