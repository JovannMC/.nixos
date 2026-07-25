{
  pkgs,
  ...
}:

# ts was made by ai. idle detection doesn't work on wayland
# ts watches kb/m input and folds/pauses FAH over the local websocket

# Folding@home v8's built-in on-idle uses PowerManagement idle seconds,
# which does not work on Linux/Wayland (KDE Plasma). This watches real
# keyboard/mouse/touchpad input and fold/pauses FAH over the local websocket.
#
# idle   -> fah fold  (only if paused and not in manual-hold)
# active -> fah pause (only if *we* started the fold for idle)
# manual fold is sticky "hands off" until FAH is paused again
# session stop -> fah fold (keep folding when logged out)
let
  fahIdle = pkgs.writers.writePython3Bin "fah-idle" {
    libraries = with pkgs.python3Packages; [ websocket-client ];
    flakeIgnore = [
      "E501"
      "E303"
      "W503"
    ];
  } ''
    import glob
    import json
    import logging
    import os
    import select
    import signal
    import struct
    import time
    from pathlib import Path

    from websocket import create_connection

    # input_event: timeval(ll) type(H) code(H) value(i)
    EVENT_FORMAT = "llHHi"
    EVENT_SIZE = struct.calcsize(EVENT_FORMAT)

    EV_KEY = 0x01
    EV_REL = 0x02
    EV_ABS = 0x03

    # Bump when behavior changes — shows in journal so you can tell rebuild applied
    FAH_IDLE_VERSION = "2-manual-hold"

    FAH_WS = os.environ.get("FAH_WS", "ws://127.0.0.1:7396/api/websocket")
    IDLE_SECONDS = float(os.environ.get("FAH_IDLE_SECONDS", "300"))
    POLL_INTERVAL = float(os.environ.get("FAH_POLL_INTERVAL", "2"))
    DEVICE_RESCAN_SECONDS = float(os.environ.get("FAH_DEVICE_RESCAN_SECONDS", "30"))

    # Joysticks/gamepads spam EV_ABS and would never look idle
    SKIP_NAME_SUBSTR = (
        "joystick",
        "gamepad",
        "controller",
        "x-box",
        "xbox",
        "dualshock",
        "dualsense",
        "wireless controller",
        "steam",
        "imu",
        "accelerometer",
        "gyro",
        "lis2mdl",
        "bmi",
        "consumer control",  # Media keys alone; real keys are on the main keyboard node
        "system control",
        "power button",
        "lid switch",
        "video bus",
        "hdmi",
        "hda ",
        "pcspkr",
    )

    running = True
    # True only when *this* service started folding due to idle.
    managed_fold = False
    # Sticky: user (or something else) is folding outside idle management.
    # While set, we never fold or pause. Cleared only when FAH is paused.
    manual_hold = False
    # Throttle FAH status polls while active and not managing
    last_status_poll = 0.0
    STATUS_POLL_SECONDS = float(os.environ.get("FAH_STATUS_POLL_SECONDS", "5"))


    def log(msg: str) -> None:
        logging.info(msg)


    def fah_connect():
        ws = create_connection(FAH_WS, timeout=5)
        # First message is full client snapshot
        snapshot = json.loads(ws.recv())
        return ws, snapshot


    def _group_paused(group: dict) -> bool | None:
        """Return paused flag for a group, or None if unknown."""
        cfg = group.get("config")
        if isinstance(cfg, dict) and "paused" in cfg:
            return bool(cfg.get("paused"))
        if "paused" in group:
            return bool(group.get("paused"))
        return None


    def fah_is_folding(snapshot: dict) -> bool:
        """True if the client is folding (any group not paused)."""
        groups = snapshot.get("groups")
        if isinstance(groups, dict) and groups:
            saw_explicit = False
            any_folding = False
            for group in groups.values():
                if not isinstance(group, dict):
                    continue
                paused = _group_paused(group)
                if paused is None:
                    continue
                saw_explicit = True
                if not paused:
                    any_folding = True
            if saw_explicit:
                return any_folding

        # Top-level paused (some builds / empty groups)
        if "paused" in snapshot:
            return not bool(snapshot.get("paused"))

        # Units present and not all finished -> treat as folding if any active state
        units = snapshot.get("units")
        if isinstance(units, list):
            active_states = {"RUN", "CORE", "DOWNLOAD", "UPLOAD", "ASSIGN"}
            for unit in units:
                if not isinstance(unit, dict):
                    continue
                state = str(unit.get("state", "")).upper()
                if state in active_states and not unit.get("paused", False):
                    return True
            if units:
                return False

        # Unknown — assume not folding so we don't steal a running WU incorrectly (prefer missing a fold start over pausing a manual fold)
        logging.warning("could not determine FAH pause state from snapshot; assuming paused")
        return False


    def fah_set_state(state: str, *, only_if_paused: bool = False) -> str:
        """Send state command. Returns 'ok', 'skipped', or raises."""
        ws, snapshot = fah_connect()
        try:
            folding = fah_is_folding(snapshot)
            if only_if_paused and folding:
                return "skipped"
            if state == "pause" and not folding:
                return "skipped"
            ws.send(json.dumps({"cmd": "state", "state": state}))
            return "ok"
        finally:
            ws.close()


    def try_set_state(
        state: str, reason: str, *, only_if_paused: bool = False
    ) -> str:
        """Returns 'ok', 'skipped', or 'error'."""
        try:
            result = fah_set_state(state, only_if_paused=only_if_paused)
        except Exception as exc:
            logging.error(f"failed to set FAH state={state} ({reason}): {exc}")
            return "error"

        if result == "skipped":
            log(f"FAH {state} skipped ({reason}; already in desired state)")
        else:
            log(f"FAH {state} ({reason})")
        return result


    def query_folding() -> bool | None:
        """Return whether FAH is currently folding, or None on error."""
        try:
            ws, snapshot = fah_connect()
            ws.close()
            return fah_is_folding(snapshot)
        except Exception as exc:
            logging.error(f"failed to query FAH state: {exc}")
            return None


    def device_name(event_path: str) -> str:
        base = os.path.basename(event_path)
        name_path = Path(f"/sys/class/input/{base}/device/name")
        try:
            return name_path.read_text(encoding="utf-8", errors="replace").strip()
        except OSError:
            return ""


    def should_monitor(event_path: str) -> bool:
        name = device_name(event_path).lower()
        if not name:
            return True
        return not any(s in name for s in SKIP_NAME_SUBSTR)


    def open_devices() -> dict[int, str]:
        fds: dict[int, str] = {}
        for path in sorted(glob.glob("/dev/input/event*")):
            if not should_monitor(path):
                continue
            try:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            except OSError as exc:
                logging.debug(f"cannot open {path}: {exc}")
                continue
            fds[fd] = path
        return fds


    def close_devices(fds: dict[int, str]) -> None:
        for fd in list(fds):
            try:
                os.close(fd)
            except OSError:
                pass
        fds.clear()



    def is_user_activity(ev_type: int, ev_value: int) -> bool:
        # Key press/repeat only (ignore release)
        if ev_type == EV_KEY and ev_value != 0:
            return True
        # Mouse move/scroll
        if ev_type == EV_REL:
            return True
        # Touchpad/tablet absolute motion (filtered devices already skip gamepads)
        if ev_type == EV_ABS:
            return True
        return False


    def handle_signal(signum, _frame) -> None:
        global running
        log(f"got signal {signum}, shutting down")
        running = False


    def main() -> None:
        global managed_fold, manual_hold, last_status_poll

        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s %(levelname)s %(message)s",
        )

        signal.signal(signal.SIGTERM, handle_signal)
        signal.signal(signal.SIGINT, handle_signal)

        last_activity = time.time()
        fds = open_devices()
        next_rescan = time.time() + DEVICE_RESCAN_SECONDS

        log(
            f"fah-idle {FAH_IDLE_VERSION}: watching {len(fds)} input device(s); "
            f"idle_seconds={IDLE_SECONDS}; ws={FAH_WS}"
        )

        # If FAH is already folding, treat as manual hands-off (never force-pause a running fold on start)
        already = query_folding()
        last_status_poll = time.time()
        if already is True:
            managed_fold = False
            manual_hold = True
            log("FAH already folding at startup — manual hold (hands off)")
        elif already is False:
            managed_fold = False
            manual_hold = False
            log("FAH paused at startup — idle will manage fold later")
        else:
            log("could not query FAH at startup — will retry in loop")

        try:
            while running:
                now = time.time()

                if now >= next_rescan:
                    close_devices(fds)
                    fds = open_devices()
                    next_rescan = now + DEVICE_RESCAN_SECONDS
                    logging.debug(f"rescanned input devices: {len(fds)}")

                if fds:
                    readable, _, _ = select.select(list(fds.keys()), [], [], POLL_INTERVAL)
                    for fd in readable:
                        try:
                            data = os.read(fd, EVENT_SIZE * 64)
                        except OSError:
                            continue

                        offset = 0
                        while offset + EVENT_SIZE <= len(data):
                            _sec, _usec, ev_type, _code, ev_value = struct.unpack_from(
                                EVENT_FORMAT, data, offset
                            )
                            offset += EVENT_SIZE
                            if is_user_activity(ev_type, ev_value):
                                last_activity = time.time()
                else:
                    time.sleep(POLL_INTERVAL)

                idle_for = time.time() - last_activity
                want_fold = idle_for >= IDLE_SECONDS

                # Poll often when we might act; otherwise periodically to catch manual folds
                need_status = (
                    managed_fold
                    or want_fold
                    or (now - last_status_poll) >= STATUS_POLL_SECONDS
                )
                if not need_status:
                    continue

                is_folding = query_folding()
                last_status_poll = time.time()
                if is_folding is None:
                    continue

                # Sticky manual hold: folding we did not start => hands off
                if is_folding and not managed_fold:
                    if not manual_hold:
                        manual_hold = True
                        log("detected non-idle fold — manual hold (hands off until pause)")
                elif (not is_folding) and manual_hold and not managed_fold:
                    manual_hold = False
                    log("FAH paused — cleared manual hold; idle management enabled")

                if manual_hold:
                    # Never fold/pause while user (or other UI) owns the client
                    continue

                if want_fold:
                    if is_folding:
                        # managed_fold path keeps running; unmanaged caught above
                        pass
                    else:
                        # Atomic: only claim ownership if client was paused
                        result = try_set_state(
                            "fold",
                            f"idle for {idle_for:.0f}s",
                            only_if_paused=True,
                        )
                        if result == "ok":
                            managed_fold = True
                            manual_hold = False
                        elif result == "skipped":
                            # Raced with a manual/other fold — do not claim it
                            manual_hold = True
                            managed_fold = False
                            log("fold skipped (already running) — manual hold")
                elif managed_fold:
                    # User is active — only pause folds *we* started for idle
                    if is_folding:
                        result = try_set_state("pause", "user activity (idle-managed)")
                        if result in ("ok", "skipped"):
                            managed_fold = False
                    else:
                        managed_fold = False
                        log("FAH already paused — dropped idle management")
        finally:
            close_devices(fds)
            # Session gone / service stopped -> keep folding unattended
            # Only force fold if we were managing or client is not in manual hold
            if managed_fold or not manual_hold:
                try_set_state("fold", "service stop", only_if_paused=True)
            else:
                log("service stop with manual hold — leaving FAH state unchanged")
            managed_fold = False


    if __name__ == "__main__":
        main()
  '';
in
{
  environment.systemPackages = [ fahIdle ];

  services.udev.extraRules = ''
    KERNEL=="event*", SUBSYSTEM=="input", MODE="0660", GROUP="input"
  '';

  systemd.user.services.fah-idle = {
    description = "Pause Folding@home while active; fold when idle (Wayland-safe)";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${fahIdle}/bin/fah-idle";
      Restart = "on-failure";
      RestartSec = 5;
    };

    # Tweak without rebuilding the script:
    # FAH_IDLE_SECONDS=600 systemctl --user restart fah-idle
    environment = {
      FAH_WS = "ws://127.0.0.1:7396/api/websocket";
      FAH_IDLE_SECONDS = "300"; # 5 minutes
      FAH_POLL_INTERVAL = "2";
      FAH_DEVICE_RESCAN_SECONDS = "30";
      PYTHONUNBUFFERED = "1";
    };
  };
}
