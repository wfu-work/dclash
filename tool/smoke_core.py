#!/usr/bin/env python3
"""Exercise a task-built sidecar with a temporary home and no network listeners."""
import argparse
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile


CONFIG = """mixed-port: 0
port: 0
socks-port: 0
redir-port: 0
tproxy-port: 0
allow-lan: false
ipv6: false
mode: direct
log-level: error
external-controller: ""
external-controller-tls: ""
external-controller-unix: ""
external-controller-pipe: ""
geo-auto-update: false
dns:
  enable: false
tun:
  enable: false
  auto-route: false
  auto-redirect: false
ntp:
  enable: false
  write-to-system: false
sniffer:
  enable: false
profile:
  store-selected: false
  store-fake-ip: false
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
"""


def receive_exact(connection, size):
    data = bytearray()
    while len(data) < size:
        part = connection.recv(size - len(data))
        if not part:
            raise RuntimeError("sidecar disconnected before its reply")
        data.extend(part)
    return data


def smoke(binary):
    with tempfile.TemporaryDirectory(prefix="dclash-smoke-", dir="/tmp") as temporary:
        home = Path(temporary)
        config = home / "config.yaml"
        config.write_text(CONFIG)
        config.chmod(0o600)
        address = str(home / "ipc.sock")
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.settimeout(15)
        listener.bind(address)
        os.chmod(address, 0o600)
        listener.listen(1)
        process = subprocess.Popen(
            [str(binary), address], stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        connection = None
        try:
            connection, _ = listener.accept()
            connection.settimeout(15)
            sequence = 0

            def invoke(method, arguments=None):
                nonlocal sequence
                sequence += 1
                identity = str(sequence)
                payload = json.dumps({"id": identity, "method": method, "arguments": arguments}).encode()
                connection.sendall(struct.pack("<I", len(payload)) + payload)
                while True:
                    size = struct.unpack("<I", receive_exact(connection, 4))[0]
                    if size > 64 * 1024 * 1024:
                        raise RuntimeError("oversized sidecar reply")
                    reply = json.loads(receive_exact(connection, size))
                    if reply.get("method") == "message":
                        continue
                    if reply.get("id") != identity:
                        raise RuntimeError("sidecar reply identity mismatch")
                    if reply.get("error"):
                        raise RuntimeError(reply["error"])
                    return reply.get("result")

            version = invoke("getVersion")
            assert isinstance(version, str) and version.startswith("v"), version
            assert invoke("initClash", {"home-dir": str(home), "version": 0}) is True
            assert invoke("setupConfig", {"selected-map": {}, "test-url": ""}) == ""
            proxies_before = invoke("getProxies")
            traffic = invoke("getTraffic", False)
            assert traffic == {"up": 0, "down": 0}, traffic
            assert invoke("getConnections")["connections"] in (None, [])
            # Semantic failure must retain the last working native configuration.
            config.write_text(CONFIG.replace("MATCH,DIRECT", "MATCH,missing-proxy"))
            rejected = invoke("setupConfig", {"selected-map": {}, "test-url": ""})
            assert isinstance(rejected, str) and rejected, rejected
            assert invoke("getProxies") == proxies_before
            assert invoke("getIsInit") is True
            if sys.platform == "darwin":
                sockets = subprocess.run(
                    ["/usr/sbin/lsof", "-a", "-p", str(process.pid), "-i", "-Fn"],
                    capture_output=True, timeout=5,
                )
                assert sockets.returncode == 1 and not sockets.stdout, sockets.stdout.decode()
            # No startListener, TUN, system proxy, helper or app launch occurs.
            assert invoke("shutdown") is True
            assert invoke("getIsInit") is False
            connection.close()
            connection = None
            output, error = process.communicate(timeout=8)
            assert process.returncode == 0, error.decode(errors="replace")
            return {"version": version, "pid": process.pid, "exitCode": process.returncode,
                    "traffic": traffic, "invalidConfigRetainedPrevious": True,
                    "listenersStarted": False}
        finally:
            if connection is not None:
                connection.close()
            listener.close()
            if process.poll() is None:
                process.terminate()
                try:
                    process.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.communicate(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    args = parser.parse_args()
    print(json.dumps(smoke(args.binary.resolve()), indent=2))
