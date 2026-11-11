#!/usr/bin/env python3
"""Create a synthetic workspace or verify the migrated workspace through the API."""
import argparse
import hashlib
import json
import os
import urllib.request
from uuid import uuid4

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("mode", choices=("seed", "verify"))
parser.add_argument("--url", default="http://localhost:8065")
args = parser.parse_args()
base = args.url.rstrip("/") + "/api/v4"
password = os.environ.get("MM_ADMIN_PASSWORD")
if not password:
    raise SystemExit("Set MM_ADMIN_PASSWORD in the environment.")
email = "student@example.test"
token = ""
messages = [
    "ПР4 · 01 · Сообщение до миграции",
    "ПР4 · 02 · Проверка приватного канала",
    "ПР4 · 03 · MySQL → PostgreSQL",
    "ПР4 · 04 · Контрольное вложение",
]
payload = "Практика 4. Файл загружен в исходный Mattermost.\n".encode()


def request(path, data=None, content_type="application/json", raw=False):
    headers = {"Content-Type": content_type}
    if token:
        headers["Authorization"] = "Bearer " + token
    if data is not None and content_type == "application/json":
        data = json.dumps(data).encode()
    req = urllib.request.Request(base + path, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as res:
        value = res.read()
        return (value if raw else json.loads(value)), res.headers


if args.mode == "seed":
    request("/users", {"email": email, "username": "student", "password": password})

user, headers = request("/users/login", {"login_id": email, "password": password})
token = headers["Token"]
assert "system_admin" in user["roles"].split()
if args.mode == "seed":
    team, _ = request("/teams", {"name": "practice4", "display_name": "Практика 4", "type": "I"})
    channel, _ = request("/channels", {
        "team_id": team["id"], "name": "migration-check",
        "display_name": "Проверка миграции", "type": "P",
    })
    boundary = uuid4().hex
    upload = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"channel_id\"\r\n\r\n{channel['id']}\r\n"
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"files\"; filename=\"migration-proof.txt\"\r\n"
        "Content-Type: text/plain\r\n\r\n"
    ).encode() + payload + f"\r\n--{boundary}--\r\n".encode()
    files, _ = request("/files", upload, "multipart/form-data; boundary=" + boundary)
    for index, message in enumerate(messages):
        request("/posts", {"channel_id": channel["id"], "message": message,
                           "file_ids": [files["file_infos"][0]["id"]] if index == 3 else []})

channel, _ = request("/teams/name/practice4/channels/name/migration-check")
assert channel["type"] == "P"
result, _ = request(f"/channels/{channel['id']}/posts")
posts = [result["posts"][key] for key in reversed(result["order"])]
demo_posts = [post for post in posts if post["message"].startswith("ПР4 ·")]
assert [post["message"] for post in demo_posts] == messages
file_id, = demo_posts[-1]["file_ids"]
attachment, _ = request(f"/files/{file_id}", raw=True)
assert attachment == payload
print("Проверены 4 сообщения, приватный канал и вложение migration-proof.txt.")
print("SHA-256 вложения:", hashlib.sha256(attachment).hexdigest())
print("Канал:", args.url.rstrip("/") + "/practice4/channels/migration-check")
