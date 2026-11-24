#!/usr/bin/env python3
"""Configure a newly started Nexus container for the syspulse exercise."""
import base64
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import urllib.request

BASE = "http://127.0.0.1:8081/service/rest/v1"
ROOT = Path(__file__).resolve().parents[1]
state = Path(os.environ.get("NEXUS_STATE_DIR", ROOT / "nexus/private")).resolve()
state.mkdir(mode=0o700, parents=True, exist_ok=True)
os.umask(0o077)


def call(path, password, data=None, method="POST"):
    token = base64.b64encode(f"admin:{password}".encode()).decode()
    request = urllib.request.Request(
        BASE + path, method=method,
        headers={"Authorization": f"Basic {token}", "Content-Type": "application/json"},
        data=json.dumps(data).encode() if data is not None else None,
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.status


def password_file(name):
    file = state / name
    if not file.exists():
        file.write_text(secrets.token_hex(24))
    return file.read_text()


admin = password_file("admin.password")
deployer = password_file("deployer.password")
passphrase = password_file("signing.password")
secret_key = state / "syspulse-private.asc"
public_key_file = state / "syspulse-public.asc"
if not secret_key.exists() or not public_key_file.exists():
    with tempfile.TemporaryDirectory(prefix="syspulse-gpg-", dir="/tmp") as key_home:
        gpg = ["gpg", "--homedir", key_home, "--batch", "--pinentry-mode", "loopback"]
        key_name = "SysPulse APT <syspulse@example.test>"
        pass_opt = ["--passphrase-file", str(state / "signing.password")]
        try:
            subprocess.run(gpg + pass_opt + [
                "--quick-generate-key", key_name, "rsa3072", "sign", "0"
            ], check=True)
            secret_key.write_bytes(subprocess.check_output(
                gpg + pass_opt + ["--armor", "--export-secret-keys", key_name]
            ))
            public_key_file.write_bytes(subprocess.check_output(
                gpg + ["--armor", "--export", key_name]
            ))
        finally:
            subprocess.run(["gpgconf", "--homedir", key_home, "--kill", "gpg-agent"], check=False)
private_key = secret_key.read_text()
public_key = public_key_file.read_bytes()
initial = subprocess.run(
    ["docker", "compose", "-f", str(ROOT / "nexus/docker-compose.yml"), "exec", "-T",
     "nexus", "cat", "/nexus-data/admin.password"], text=True, capture_output=True
)
if initial.returncode == 0:
    start = initial.stdout.strip()
    request = urllib.request.Request(
        BASE + "/security/users/admin/change-password", method="PUT",
        headers={"Authorization": "Basic " + base64.b64encode(f"admin:{start}".encode()).decode(),
                 "Content-Type": "text/plain"},
        data=admin.encode(),
    )
    with urllib.request.urlopen(request, timeout=30):
        pass
    print("Nexus initial admin password changed.")

print("Hosted APT", call("/repositories/apt/hosted", admin, {
    "name": "syspulse", "online": True,
    "storage": {"blobStoreName": "default", "strictContentTypeValidation": True,
                "writePolicy": "ALLOW"},
    "apt": {"distribution": "stable"},
    "aptSigning": {"keypair": private_key, "passphrase": passphrase},
}))
role = "syspulse-publisher"
print("Publisher role", call("/security/roles", admin, {
    "id": role, "name": "SysPulse publisher", "description": "Publish syspulse Debian packages",
    "privileges": ["nx-component-upload"] + [
        f"nx-repository-view-apt-syspulse-{action}" for action in ("add", "edit", "read", "browse")
    ], "roles": [],
}))
print("Publisher user", call("/security/users", admin, {
    "userId": "syspulse-deployer", "firstName": "SysPulse", "lastName": "Deployer",
    "emailAddress": "syspulse@example.test", "password": deployer,
    "status": "active", "roles": [role],
}))
print("Anonymous APT read", call("/security/anonymous", admin, {
    "enabled": True, "userId": "anonymous", "realmName": "NexusAuthorizingRealm",
}, method="PUT"))
public_path = ROOT / "nexus/syspulse.asc"
public_path.write_bytes(public_key)
public_path.chmod(0o644)
