#!/usr/bin/env python3
import json
import socket
import subprocess
import time
import traceback
import urllib.request
import urllib.error

CONFIG_FILE = "/etc/dmx-node.conf"
INTERVAL_SECONDS = 15

def read_config(path=CONFIG_FILE):
    config = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            config[key.strip()] = value.strip().strip('"').strip("'")
    return config

CONFIG = read_config()
PORTAL_BASE = CONFIG.get("PORTAL_BASE", "https://dj.dancethruthedecades.co.uk/api").rstrip("/")
HEARTBEAT_URL = PORTAL_BASE + "/player-heartbeat.php"
COMMAND_URL = PORTAL_BASE + "/node-command.php"
SECRET = CONFIG.get("SECRET", "")
NODE_KEY = CONFIG.get("NODE_KEY", "dmx-desk-a")
DISPLAY_NAME = CONFIG.get("DISPLAY_NAME", "DMX Deck A")
SPOTIFY_NAME = CONFIG.get("SPOTIFY_NAME", DISPLAY_NAME)

def post_json(url, payload):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "X-DMX-Node-Secret": SECRET,
            "User-Agent": "DMX-Node-Agent/2.3",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as response:
        return json.loads(response.read().decode("utf-8"))

def get_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return ""

def service_running(service_name):
    try:
        result = subprocess.run(
            ["systemctl", "is-active", service_name],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        return result.stdout.strip() == "active"
    except Exception:
        return False

def run_shell(command, timeout=180):
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )
    return result.returncode == 0, result.stdout.strip() or "Command executed"

def payload_volume(payload):
    if isinstance(payload, str):
        try:
            payload = json.loads(payload or "{}")
        except Exception:
            payload = {}
    if not isinstance(payload, dict):
        payload = {}
    try:
        volume = int(payload.get("volume", 85))
    except Exception:
        volume = 85
    return max(0, min(100, volume))

def run_command(command_name, payload):
    if command_name == "configure_spotify_account":
        return False, "configure_spotify_account disabled"

    if command_name == "set_volume":
        return run_shell(["sudo", "/opt/dttd-pi-node/scripts/set-volume.sh", str(payload_volume(payload))], timeout=120)

    if command_name == "update_agent":
        return run_shell(["sudo", "/opt/dttd-pi-node/scripts/update.sh"], timeout=300)

    allowed = {
        "restart_raspotify": ["sudo", "systemctl", "restart", "raspotify"],
        "restart_agent": ["sudo", "systemctl", "restart", "dmx-node-agent"],
        "reboot": ["sudo", "reboot"],
        "shutdown": ["sudo", "shutdown", "-h", "now"],
        "healthcheck": ["sudo", "/opt/dttd-pi-node/scripts/healthcheck.sh"],
    }

    if command_name not in allowed:
        return False, "Command not allowed: " + command_name

    return run_shell(allowed[command_name], timeout=180)

def send_heartbeat():
    payload = {
        "node_key": NODE_KEY,
        "hostname": socket.gethostname(),
        "display_name": DISPLAY_NAME,
        "spotify_name": SPOTIFY_NAME,
        "ip_address": get_ip(),
        "raspotify_running": service_running("raspotify"),
    }
    print("Heartbeat:", post_json(HEARTBEAT_URL, payload), flush=True)

def poll_command():
    response = post_json(COMMAND_URL, {"mode": "poll", "node_key": NODE_KEY})
    command = response.get("command")

    if not command:
        return

    command_id = command["id"]
    command_name = command["name"]
    payload = command.get("payload")

    print("Command received:", command_name, flush=True)

    try:
        success, result = run_command(command_name, payload)
        status = "completed" if success else "failed"
    except Exception as e:
        status = "failed"
        result = str(e)
        traceback.print_exc()

    if command_name == "reboot":
        result = "Reboot command accepted"
    elif command_name == "shutdown":
        result = "Shutdown command accepted"

    post_json(COMMAND_URL, {
        "mode": "complete",
        "node_key": NODE_KEY,
        "command_id": command_id,
        "status": status,
        "result": result,
    })

    # Load the newly pulled agent code automatically after a successful update.
    # This happens after the command result has been reported to the portal.
    if command_name == "update_agent" and status == "completed":
        subprocess.Popen(["sudo", "systemctl", "restart", "dmx-node-agent"])

def main():
    print("DMX node agent starting...", flush=True)
    while True:
        try:
            send_heartbeat()
            poll_command()
        except urllib.error.HTTPError as e:
            print("HTTP error:", e.code, e.reason, flush=True)
            try:
                print(e.read().decode("utf-8"), flush=True)
            except Exception:
                pass
        except Exception as e:
            print("Agent error:", str(e), flush=True)
            traceback.print_exc()

        time.sleep(INTERVAL_SECONDS)

if __name__ == "__main__":
    main()
