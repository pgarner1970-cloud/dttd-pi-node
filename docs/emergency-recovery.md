# Emergency Recovery Guide

## If Deck A/B is missing from the DJ portal

1. Check the Pi has power and network.
2. In the portal, use Spotify Tools > Restart Spotify.
3. Wait 20 seconds and refresh Spotify Tools.
4. If still missing:
   - Open Spotify on your phone.
   - Select `DMX Deck A` or `DMX Deck B`.
   - Play any track for 5-10 seconds.
   - Refresh the portal.
5. If still missing, SSH into the Pi and run:

   ```bash
   sudo systemctl status raspotify --no-pager
   sudo systemctl status dmx-node-agent --no-pager
   sudo /opt/dttd-pi-node/scripts/healthcheck.sh
   ```

## If there is no audio

```bash
aplay -l
sudo systemctl restart raspotify
```

Then select the device from Spotify on your phone and test audio.

## If the Pi is online but commands do not work

```bash
sudo systemctl restart dmx-node-agent
sudo journalctl -u dmx-node-agent -n 80 --no-pager -o cat
```

## Full reboot

From the portal use Reboot Node, or via SSH:

```bash
sudo reboot
```


## Safe shutdown

Use the DJ portal Shutdown Deck button where possible, or via SSH:

```bash
sudo shutdown -h now
```

Wait for the Pi activity LED to stop flashing before removing power.
