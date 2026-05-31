# DTTD Pi Node Setup Guide

## Brand new Pi rollout

1. Flash Raspberry Pi OS Lite.
2. Enable SSH.
3. Connect the Pi to the event WiFi/network.
4. SSH into the Pi.
5. Install Git:

   ```bash
   sudo apt update
   sudo apt install -y git
   ```

6. Clone the node repository:

   ```bash
   git clone https://github.com/YOURACCOUNT/dttd-pi-node.git
   cd dttd-pi-node
   ```

7. Install as Deck A or Deck B:

   ```bash
   sudo ./scripts/install.sh --deck a
   ```

   or:

   ```bash
   sudo ./scripts/install.sh --deck b
   ```

8. Open Spotify on a phone using the DJ Spotify account.
9. Select `DMX Deck A` or `DMX Deck B`.
10. Play a track for 5-10 seconds.
11. Refresh Spotify Tools in the DJ portal.
