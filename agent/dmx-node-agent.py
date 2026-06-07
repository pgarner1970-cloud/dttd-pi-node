#!/usr/bin/env python3
import json
import os
import re
import socket
import subprocess
import shutil
import time
import traceback
import urllib.request
import urllib.error

CONFIG_FILE = "/etc/dmx-node.conf"
HEARTBEAT_INTERVAL_SECONDS = 15
COMMAND_POLL_INTERVAL_SECONDS = 1

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
DISPLAY_URL_FULL = CONFIG.get("DISPLAY_URL_FULL", "https://live.dancethruthedecades.co.uk/")
DISPLAY_URL_LITE = CONFIG.get("DISPLAY_URL_LITE", "https://live.dancethruthedecades.co.uk/?mode=lite")
DISPLAY_BROWSER = CONFIG.get("DISPLAY_BROWSER", "").strip()
DISPLAY_PROFILE_BASE = CONFIG.get("DISPLAY_PROFILE_BASE", "/home/disco/.config/dttd-display-chromium")
DISPLAY_LOG = CONFIG.get("DISPLAY_LOG", "/tmp/dttd-display.log")


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

def mpc_current_playlist_files():
    ok, out = run_mpc(["playlist", "-f", "%file%"], timeout=20)
    if not ok:
        return []
    return [line.strip() for line in out.splitlines() if line.strip()]

def mpc_status_text():
    ok, out = run_mpc(["status"], timeout=15)
    return out if ok else ""

def mpc_volume_value(default=85):
    status = mpc_status_text()
    match = re.search(r"volume:\s*(\d+)%", status)
    if match:
        try:
            return max(0, min(100, int(match.group(1))))
        except Exception:
            pass
    return default

def local_playlist_has_track(rel):
    files = mpc_current_playlist_files()
    return bool(files) and files[0] == rel

def seconds_from_ms(value):
    try:
        return max(0, int(int(value) / 1000))
    except Exception:
        return 0

def local_prepare(payload):
    payload = ensure_payload_dict(payload)
    rel, full = local_absolute_path(payload.get("relative_path") or payload.get("local_path") or payload.get("path"))
    if not local_mount_ready():
        return False, "Local music mount is not ready: " + LOCAL_MUSIC_MOUNT
    if not os.path.isfile(full):
        return False, "Local track file not found: " + rel

    try:
        # Safe cue-only prepare. Do not start muted playback here: on some MPD
        # builds that advanced the track silently and caused delayed/offset audio.
        run_mpc_required(["stop"], timeout=20)
        run_mpc_required(["clear"], timeout=20)
        ok, add_out = run_mpc(["add", rel], timeout=30)
        if not ok:
            # The MPD database may not have seen newly synced files yet.
            run_mpc(["update", "--wait"], timeout=180)
            ok, add_out = run_mpc(["add", rel], timeout=30)
            if not ok:
                raise RuntimeError(add_out)
        run_mpc(["stop"], timeout=20)

        title = payload.get("title") or rel
        artist = payload.get("artist") or ""
        label = (str(artist) + " - " if artist else "") + str(title)
        return True, "Local track queued ready via MPD: " + label
    except Exception as e:
        return False, "Local prepare failed: " + str(e)

def local_play(payload):
    payload = ensure_payload_dict(payload)
    rel, full = local_absolute_path(payload.get("relative_path") or payload.get("local_path") or payload.get("path"))
    if not local_mount_ready():
        return False, "Local music mount is not ready: " + LOCAL_MUSIC_MOUNT
    if not os.path.isfile(full):
        return False, "Local track file not found: " + rel

    position_seconds = seconds_from_ms(payload.get("position_ms", 0))

    try:
        if local_playlist_has_track(rel):
            # Prepared path: the track is already queued and paused by local_prepare.
            if position_seconds > 0:
                run_mpc_required(["seek", str(position_seconds)], timeout=20)
            run_mpc_required(["play"], timeout=20)
        else:
            # Fallback path: still works if prepare was missed or failed.
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

def display_browser_path():
    candidates = []
    if DISPLAY_BROWSER:
        candidates.append(DISPLAY_BROWSER)
    candidates += [
        "/usr/lib/chromium/chromium",
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
    ]
    for candidate in candidates:
        if candidate and os.path.exists(candidate) and os.access(candidate, os.X_OK):
            return candidate
    found = shutil.which("chromium") or shutil.which("chromium-browser")
    if found:
        return found
    raise RuntimeError("No Chromium browser binary was found")

def display_mode_from_payload(payload):
    payload = ensure_payload_dict(payload)
    mode = str(payload.get("mode", "lite") or "lite").strip().lower()
    return "full" if mode == "full" else "lite"

def display_url_for_mode(mode):
    return DISPLAY_URL_FULL if mode == "full" else DISPLAY_URL_LITE

def display_profile_for_mode(mode):
    suffix = "full" if mode == "full" else "lite"
    return DISPLAY_PROFILE_BASE + "-" + suffix

def display_process_lines():
    try:
        result = subprocess.run(
            ["pgrep", "-af", "dttd-display-chromium"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=10,
        )
        return [line.strip() for line in result.stdout.splitlines() if line.strip()]
    except Exception:
        return []

def display_running():
    return bool(display_process_lines())

def display_stop(payload=None):
    lines = display_process_lines()
    if not lines:
        return True, "Display browser was not running"
    subprocess.run(["pkill", "-f", "dttd-display-chromium"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
    time.sleep(1)
    if display_running():
        return False, "Display browser stop requested but process is still running"
    return True, "Display browser stopped"

def display_start(payload=None):
    payload = ensure_payload_dict(payload)
    mode = display_mode_from_payload(payload)
    url = str(payload.get("url") or display_url_for_mode(mode))
    browser = display_browser_path()
    profile = display_profile_for_mode(mode)
    os.makedirs(profile, exist_ok=True)

    # Stop any previous kiosk instance using our dedicated profile first.
    display_stop()

    env = os.environ.copy()
    env.setdefault("DISPLAY", ":0")
    env.setdefault("XDG_RUNTIME_DIR", "/run/user/%s" % os.getuid())

    command = [
        browser,
        "--kiosk",
        "--ozone-platform=x11",
        "--noerrdialogs",
        "--disable-infobars",
        "--disable-session-crashed-bubble",
        "--disable-features=TranslateUI,MediaRouter,OptimizationHints",
        "--password-store=basic",
        "--no-first-run",
        "--disable-save-password-bubble",
        "--disable-gpu",
        "--disable-dev-shm-usage",
        "--disable-extensions",
        "--disable-background-networking",
        "--disable-sync",
        "--metrics-recording-only",
        "--user-data-dir=" + profile,
        url,
    ]

    with open(DISPLAY_LOG, "a", encoding="utf-8") as log:
        log.write("\n--- starting display mode=%s url=%s at %s ---\n" % (mode, url, time.strftime("%Y-%m-%d %H:%M:%S")))
        subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, env=env, start_new_session=True)

    time.sleep(3)
    if not display_running():
        return False, "Display browser start command ran but no display process is running"
    return True, "Display browser started in %s mode: %s" % (mode, url)

def display_restart(payload=None):
    payload = ensure_payload_dict(payload)
    mode = display_mode_from_payload(payload)
    ok, out = display_start({"mode": mode})
    return ok, "Display restart: " + out

def display_blank(payload=None):
    ok, out = run_shell(["/usr/bin/env", "bash", "-lc", "DISPLAY=:0 xset dpms force off || DISPLAY=:0 xset s activate"], timeout=20)
    return ok, out

def display_wake(payload=None):
    ok, out = run_shell(["/usr/bin/env", "bash", "-lc", "DISPLAY=:0 xset dpms force on || DISPLAY=:0 xset s reset"], timeout=20)
    return ok, out

def display_status(payload=None):
    lines = display_process_lines()
    mode = "unknown"
    url = ""
    if lines:
        joined = " ".join(lines)
        if "mode=lite" in joined or "-lite" in joined:
            mode = "lite"
        elif "-full" in joined:
            mode = "full"
        if "https://" in joined:
            url = joined[joined.find("https://"):].split()[0]
    return True, json.dumps({
        "running": bool(lines),
        "mode": mode,
        "url": url,
        "process_count": len(lines),
        "browser": display_browser_path() if (DISPLAY_BROWSER or shutil.which("chromium") or os.path.exists("/usr/lib/chromium/chromium")) else "",
    }, sort_keys=True)

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

    if command_name == "local_prepare":
        return local_prepare(payload)

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

    if command_name == "display_start":
        return display_start(payload)

    if command_name == "display_stop":
        return display_stop(payload)

    if command_name == "display_restart":
        return display_restart(payload)

    if command_name == "display_lite":
        return display_start({"mode": "lite"})

    if command_name == "display_full":
        return display_start({"mode": "full"})

    if command_name == "display_blank":
        return display_blank(payload)

    if command_name == "display_wake":
        return display_wake(payload)

    if command_name == "display_status":
        return display_status(payload)

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
        "display_browser_running": display_running(),
        "display_status": json.loads(display_status()[1]),
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
    last_heartbeat = 0
    while True:
        try:
            now = time.time()
            if now - last_heartbeat >= HEARTBEAT_INTERVAL_SECONDS:
                send_heartbeat()
                last_heartbeat = now
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

        time.sleep(COMMAND_POLL_INTERVAL_SECONDS)

if __name__ == "__main__":
    main()
