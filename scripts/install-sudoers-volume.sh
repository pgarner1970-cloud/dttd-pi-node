#!/bin/bash
set -eu

cat >/etc/sudoers.d/dttd-node-agent <<EOF
disco ALL=(root) NOPASSWD: /bin/systemctl restart raspotify, /bin/systemctl restart dmx-node-agent, /bin/systemctl restart mpd, /bin/systemctl is-active raspotify, /bin/systemctl is-active mpd, /sbin/reboot, /usr/sbin/reboot, /usr/sbin/shutdown, /sbin/shutdown, /opt/dttd-pi-node/scripts/healthcheck.sh, /opt/dttd-pi-node/scripts/update.sh, /opt/dttd-pi-node/scripts/set-usb-audio.sh, /opt/dttd-pi-node/scripts/set-volume.sh, /opt/dttd-pi-node/scripts/install-local-mpd.sh
EOF

chmod 440 /etc/sudoers.d/dttd-node-agent
echo "Updated dttd-node-agent sudoers for volume control."
