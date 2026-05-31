# DTTD Pi Node

Raspberry Pi node software for Dance Thru The Decades Spotify/DMX player nodes.

## Quick install

```bash
git clone https://github.com/YOURACCOUNT/dttd-pi-node.git
cd dttd-pi-node
sudo ./scripts/install.sh --deck a
```

For Deck B:

```bash
sudo ./scripts/install.sh --deck b
```

## Important Spotify behaviour

Raspotify/librespot works as a Spotify Connect speaker. The Pi does not use the DJ portal Web API token as a librespot login.

After install or rebuild, open Spotify on a phone using the DJ Spotify account, select the Pi speaker once, and play for 5-10 seconds so credentials/discovery are cached.

## Healthcheck

```bash
sudo /opt/dttd-pi-node/scripts/healthcheck.sh
```
