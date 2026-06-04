#!/usr/bin/env python3
import json
import os
import re
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
LOCAL_MUSIC_MOUNT = CONFIG.get("LOCAL_MUSIC_MOUNT", "/mnt/dttd-music").rstrip("/")
MPD_HOST = CONFIG.get("MPD_HOST", "localhost")
MPD_PORT = CONFIG.get("MPD_PORT", "6600")


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

def ensure_payload_dict(payload):
    if isinstance(payload, str):
        try:
            payload = json.loads(payload or "{}")
        except Exception:
            payload = {}
    return payload if isinstance(payload, dict) else {}

def safe_relative_path(path):
    path = str(path or "").replace("\\", "/").strip()
    path = re.sub(r"/+", "/", path).lstrip("/")
    if not path or "\x00" in path or path.startswith("../") or "/../" in path or path == "..":
        raise ValueError("Local track path is missing or unsafe")
    return path

def local_absolute_path(relative_path):
    rel = safe_relative_path(relative_path)
    base = os.path.abspath(LOCAL_MUSIC_MOUNT)
    full = os.path.abspath(os.path.join(base, rel))
    if full != base and not full.startswith(base + os.sep):
        raise ValueError("Local track path escaped music mount")
    return rel, full

def local_mount_ready():
    return os.path.isdir(LOCAL_MUSIC_MOUNT) and os.path.ismount(LOCAL_MUSIC_MOUNT)

def run_mpc(args, timeout=60):
    env = os.environ.copy()
    env["MPD_HOST"] = MPD_HOST
    env["MPD_PORT"] = MPD_PORT
    result = subprocess.run(
        ["mpc"] + list(args),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
        env=env,
    )
    return result.returncode == 0, result.stdout.strip() or "mpc command executed"

def run_mpc_required(args, timeout=60):
    ok, out = run_mpc(args, timeout=timeout)
    if not ok:
        raise RuntimeError(out)
    return out

def seconds_from_ms(value):
    try:
        return max(0, int(int(value) / 1000))
    except Exception:
        return 0

def local_play(payload):
    payload = ensure_payload_dict(payload)
    rel, full = local_absolute_path(payload.get("relative_path") or payload.get("local_path") or payload.get("path"))
    if not local_mount_ready():
        return False, "Local music mount is not ready: " + LOCAL_MUSIC_MOUNT
    if not os.path.isfile(full):
        return False, "Local track file not found: " + rel

    position_seconds = seconds_from_ms(payload.get("position_ms", 0))

    try:
        run_mpc_required(["stop"], timeout=20)
        run_mpc_required(["clear"], timeout=20)
        ok, add_out = run_mpc(["add", rel], timeout=30)
        if not ok:
            # The MPD database may not have seen newly synced files yet.
            run_mpc(["update", "--wait"], timeout=180)
            ok, add_out = run_mpc(["add", rel], timeout=30)
            if not ok:
                raise RuntimeError(add_out)
        run_mpc_required(["play"], timeout=20)
        if position_seconds > 0:
            run_mpc_required(["seek", str(position_seconds)], timeout=20)
        title = payload.get("title") or rel
        artist = payload.get("artist") or ""
        label = (str(artist) + " - " if artist else "") + str(title)
        return True, "Local playback started via MPD: " + label
    except Exception as e:
        return False, "Local playback failed: " + str(e)

def local_pause(payload=None):
    return run_mpc(["pause"], timeout=20)

def local_stop(payload=None):
    return run_mpc(["stop"], timeout=20)

def local_seek(payload):
    payload = ensure_payload_dict(payload)
    rel = payload.get("relative_path") or payload.get("local_path") or payload.get("path")
    play = bool(payload.get("play", False))
    position_seconds = seconds_from_ms(payload.get("position_ms", 0))

    # If a path is supplied and playback is requested, reload that file so seek
    # works even after a previous stop/clear.
    if rel and play:
        ok, out = local_play(payload)
        if not ok:
            return ok, out
        if position_seconds > 0:
            return run_mpc(["seek", str(position_seconds)], timeout=20)
        return True, out

    ok, out = run_mpc(["seek", str(position_seconds)], timeout=20)
    if not ok and rel:
        # Load the track paused at the requested point. This may briefly start
        # MPD on some builds but leaves the deck paused afterwards.
        payload["play"] = True
        ok, out = local_play(payload)
        if ok and position_seconds > 0:
            run_mpc(["seek", str(position_seconds)], timeout=20)
        run_mpc(["pause"], timeout=20)
        return ok, "Local track loaded/seeked and paused" if ok else out
    return ok, out

def local_status(payload=None):
    mount = "mounted" if local_mount_ready() else "not mounted"
    mpd = "active" if service_running("mpd") else "inactive"
    ok, status = run_mpc(["status"], timeout=15)
    return ok, "mount=%s; mpd=%s; %s" % (mount, mpd, status)

def payload_volume(payload):
    payload = ensure_payload_dict(payload)
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

    if command_name == "local_play":
        return local_play(payload)

    if command_name == "local_pause":
        return local_pause(payload)

    if command_name == "local_stop":
        return local_stop(payload)

    if command_name == "local_seek":
        return local_seek(payload)

    if command_name == "local_status":
        return local_status(payload)

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
        "mpd_running": service_running("mpd"),
        "local_music_mounted": local_mount_ready(),
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
