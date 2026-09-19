#!/usr/bin/python3
"""Minimal FStack guest supervisor for the opt-in Firecracker backend."""

import json
import os
import re
import signal
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

children: list[subprocess.Popen[str]] = []
stopping = threading.Event()


def log(message: str) -> None:
    print(message, flush=True)


def mount(source: str, target: str, read_only: bool) -> None:
    if os.path.ismount(target):
        return
    Path(target).mkdir(parents=True, exist_ok=True)
    command = ["mount"]
    if read_only:
        command.extend(["-o", "ro"])
    command.extend([source, target])
    subprocess.run(command, check=True)


def stream(pipe, node: str, command: str, ready, pattern) -> None:
    assert pipe is not None
    for line in pipe:
        sys.stdout.write(f"[{node}/{command}] {line}")
        sys.stdout.flush()
        if pattern is not None and pattern.search(line):
            ready.set()


def environment(values: dict[str, str]) -> dict[str, str]:
    result = {
        "HOME": "/root",
        "PATH": "/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "SHELL": "/bin/sh",
        "USER": "root",
    }
    certificates = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt"
    if Path(certificates).is_file():
        result.update(SSL_CERT_FILE=certificates, NIX_SSL_CERT_FILE=certificates)
    result.update({key: str(value) for key, value in values.items()})
    return result


def run_prepare(node: dict, command: dict) -> None:
    cwd = Path(node["root"]) / command.get("cwd", ".")
    log(f"FSTACK_PREPARE_START node={node['id']} command={command['id']}")
    completed = subprocess.run(
        ["/bin/sh", "-c", command["command"]],
        cwd=cwd,
        env=environment(node.get("env", {})),
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"prepare {node['id']}/{command['id']} exited {completed.returncode}"
        )
    log(f"FSTACK_PREPARE_READY node={node['id']} command={command['id']}")


def start_command(node: dict, command: dict) -> None:
    cwd = Path(node["root"]) / command.get("cwd", ".")
    process = subprocess.Popen(
        ["/bin/sh", "-c", command["command"]],
        cwd=cwd,
        env=environment(node.get("env", {})),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        start_new_session=True,
    )
    children.append(process)
    raw_pattern = command.get("readyPattern")
    pattern = re.compile(raw_pattern) if raw_pattern else None
    ready = threading.Event()
    threading.Thread(
        target=stream,
        args=(process.stdout, node["id"], command["id"], ready, pattern),
        daemon=True,
    ).start()
    if pattern is not None:
        timeout = float(command.get("readyTimeoutMs", 120000)) / 1000
        deadline = time.monotonic() + timeout
        while not ready.is_set() and time.monotonic() < deadline:
            status = process.poll()
            if status is not None:
                raise RuntimeError(
                    f"command {node['id']}/{command['id']} exited {status} before ready"
                )
            ready.wait(0.025)
        if not ready.is_set():
            raise RuntimeError(
                f"command {node['id']}/{command['id']} readiness timed out"
            )
    elif process.poll() is not None:
        raise RuntimeError(
            f"command {node['id']}/{command['id']} exited before startup completed"
        )
    log(f"FSTACK_COMMAND_READY node={node['id']} command={command['id']}")


def stop(_signal=None, _frame=None) -> None:
    if stopping.is_set():
        return
    stopping.set()
    for process in children:
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline and any(p.poll() is None for p in children):
        time.sleep(0.05)
    for process in children:
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def serve_control(listener: socket.socket) -> None:
    while not stopping.is_set():
        try:
            connection, peer = listener.accept()
        except TimeoutError:
            continue
        with connection:
            # Only the host CID may request lifecycle operations.
            if peer[0] != socket.VMADDR_CID_HOST:
                continue
            connection.settimeout(2)
            try:
                with connection.makefile("rb") as incoming:
                    if incoming.readline(64) == b"shutdown\n":
                        if Path("/run/systemd/system").is_dir():
                            subprocess.run(["systemctl", "poweroff", "--no-block"], check=True)
                        else:
                            # BusyBox init maps SIGUSR2 to an orderly poweroff.
                            os.kill(1, signal.SIGUSR2)
                        return
            except (OSError, subprocess.CalledProcessError) as error:
                log(f"FSTACK_CONTROL_ERROR {error}")


def main() -> int:
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    mount("/dev/vdb", "/run/fstack-config", True)
    mount("/dev/vdc", "/workspace", False)
    plan = json.loads(Path("/run/fstack-config/plan.json").read_text())
    if plan.get("version") != 1:
        raise RuntimeError("unsupported FStack guest plan version")
    for node in plan["nodes"]:
        for command in node.get("prepare", []):
            run_prepare(node, command)
        for command in node.get("commands", []):
            start_command(node, command)
    control = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    control.bind((socket.VMADDR_CID_ANY, 10000))
    control.listen(1)
    control.settimeout(0.5)
    threading.Thread(target=serve_control, args=(control,), daemon=True).start()
    log("FSTACK_STACK_READY")
    while not stopping.is_set():
        for process in children:
            status = process.poll()
            if status is not None:
                raise RuntimeError(f"required child {process.pid} exited {status}")
        stopping.wait(0.05)
    stop()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        log(f"FSTACK_GUEST_FAILED {error}")
        stop()
        raise
