"""Seed the throwaway Audiobookshelf test server (tool/test-server).

Standard library only. Idempotent: run it as often as you like.

  1. waits for the server on 127.0.0.1:13378 (and refuses any other host);
  2. initializes the root user when the server is new, with generated test
     credentials saved to tool/test-server/.env (git-ignored);
  3. generates short test media with the container's own ffmpeg:
     a three-file MP3 book, a single M4B with two chapters, a one-file MP3
     book with non-ASCII metadata, and a two-episode podcast;
  4. creates the "Absorb Test Books" library over /audiobooks and the
     "Absorb Test Podcasts" library over /podcasts, and scans them;
  5. creates a second, non-admin account for multi-account tests;
  6. waits until every book and the podcast are in their libraries.

/podcasts lives in the container only (the compose file mounts no volume
for it), so after `server down`/`up` the next `server seed` recreates it.

Never point this at a real server: it only talks to the loopback port the
compose file publishes.
"""

from __future__ import annotations

import json
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENV_FILE = HERE / ".env"
BASE_URL = "http://127.0.0.1:13378"
CONTAINER = "absorb-test-abs"
LIBRARY_NAME = "Absorb Test Books"
LIBRARY_FOLDER = "/audiobooks"
AUTHOR = "Absorb Test Author"
BOOKS = ("Multi File Book", "Chaptered Book")
# Odd metadata on purpose: accents, CJK, Greek, an astral-plane emoji, a
# narrator and a genre whose standard base64 contains "+".
UNICODE_AUTHOR = "Ünïcødé Àuthör"
UNICODE_TITLE = ("Ünïcødé Bøøk 日本語 "
                 "Ελληνικά \U0001f3a7")
UNICODE_NARRATOR = "Slavoj Žižek"
UNICODE_GENRE = "Fiction > Fantasy"
ALL_BOOKS = BOOKS + (UNICODE_TITLE,)
PODCAST_LIBRARY_NAME = "Absorb Test Podcasts"
PODCAST_FOLDER = "/podcasts"
PODCAST_TITLE = "Absorb Test Podcast"
ROOT_USER = "absorb-root"
LISTENER_USER = "absorb-listener"

# Runs inside the container (sh -s). Only creates files that are missing.
MEDIA_SCRIPT = f"""
set -e
author="{LIBRARY_FOLDER}/{AUTHOR}"
mp3dir="$author/{BOOKS[0]}"
m4bdir="$author/{BOOKS[1]}"
mkdir -p "$mp3dir" "$m4bdir"
for i in 1 2 3; do
  out="$mp3dir/Part 0$i.mp3"
  [ -s "$out" ] && continue
  ffmpeg -nostdin -loglevel error -y \\
    -f lavfi -i "sine=frequency=$((300 + i * 100)):duration=10" \\
    -c:a libmp3lame -b:a 32k \\
    -metadata title="Part $i" -metadata album="{BOOKS[0]}" \\
    -metadata artist="{AUTHOR}" -metadata track="$i/3" \\
    -f mp3 "$out.tmp"
  mv "$out.tmp" "$out"
done
out="$m4bdir/{BOOKS[1]}.m4b"
if [ ! -s "$out" ]; then
  cat > /tmp/absorb-chapters.txt <<'EOF'
;FFMETADATA1
title={BOOKS[1]}
album={BOOKS[1]}
artist={AUTHOR}
[CHAPTER]
TIMEBASE=1/1000
START=0
END=15000
title=Chapter One
[CHAPTER]
TIMEBASE=1/1000
START=15000
END=30000
title=Chapter Two
EOF
  ffmpeg -nostdin -loglevel error -y \\
    -f lavfi -i "sine=frequency=330:duration=30" \\
    -i /tmp/absorb-chapters.txt -map 0:a -map_metadata 1 -map_chapters 1 \\
    -c:a aac -b:a 32k -f ipod "$out.tmp"
  mv "$out.tmp" "$out"
fi
udir="{LIBRARY_FOLDER}/{UNICODE_AUTHOR}/{UNICODE_TITLE}"
mkdir -p "$udir"
out="$udir/Track.mp3"
if [ ! -s "$out" ]; then
  ffmpeg -nostdin -loglevel error -y \\
    -f lavfi -i "sine=frequency=440:duration=12" \\
    -c:a libmp3lame -b:a 32k \\
    -metadata title="{UNICODE_TITLE}" -metadata album="{UNICODE_TITLE}" \\
    -metadata artist="{UNICODE_AUTHOR}" -metadata composer="{UNICODE_NARRATOR}" \\
    -metadata genre="{UNICODE_GENRE}" \\
    -f mp3 "$out.tmp"
  mv "$out.tmp" "$out"
fi
pdir="{PODCAST_FOLDER}/{PODCAST_TITLE}"
mkdir -p "$pdir"
for i in 1 2; do
  out="$pdir/Episode $i.mp3"
  [ -s "$out" ] && continue
  ffmpeg -nostdin -loglevel error -y \\
    -f lavfi -i "sine=frequency=$((500 + i * 50)):duration=$((8 + i * 2))" \\
    -c:a libmp3lame -b:a 32k \\
    -metadata title="Episode $i" -metadata album="{PODCAST_TITLE}" \\
    -metadata artist="{AUTHOR}" -metadata track="$i" \\
    -f mp3 "$out.tmp"
  mv "$out.tmp" "$out"
done
echo media-ok
"""


def log(msg: str) -> None:
    print(f"seed: {msg}", flush=True)


def fail(msg: str) -> None:
    print(f"seed: ERROR: {msg}", file=sys.stderr, flush=True)
    sys.exit(1)


def request(method: str, path: str, body: dict | None = None,
            token: str | None = None, headers: dict | None = None,
            timeout: float = 20) -> tuple[int, object]:
    url = BASE_URL + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            status = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read()
        status = e.code
    try:
        payload: object = json.loads(raw) if raw else None
    except ValueError:
        payload = raw.decode(errors="replace")
    return status, payload


def read_env() -> dict[str, str]:
    env: dict[str, str] = {}
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                env[key.strip()] = value.strip()
    return env


def write_env(env: dict[str, str]) -> None:
    lines = ["# Generated by tool/test-server/seed.py for the throwaway test server.",
             "# Test-only credentials; git-ignored. Delete with: dev.ps1 server reset"]
    lines += [f"{k}={v}" for k, v in env.items()]
    ENV_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")


def wait_for_server(timeout_s: float = 180) -> dict:
    deadline = time.time() + timeout_s
    last = ""
    while time.time() < deadline:
        try:
            status, payload = request("GET", "/status", timeout=5)
            if status == 200 and isinstance(payload, dict):
                return payload
            last = f"HTTP {status}"
        except (urllib.error.URLError, ConnectionError, TimeoutError, OSError) as e:
            last = str(e)
        time.sleep(2)
    fail(f"server at {BASE_URL} not ready after {timeout_s:.0f}s ({last}). "
         "Start it with: .\\tool\\dev.ps1 server up")
    raise AssertionError  # unreachable


def login(username: str, password: str) -> str:
    status, payload = request("POST", "/login",
                              {"username": username, "password": password},
                              headers={"x-return-tokens": "true"})
    if status != 200 or not isinstance(payload, dict):
        fail(f"login as {username} failed (HTTP {status})")
    user = payload["user"]
    token = user.get("accessToken") or user.get("token")
    if not token:
        fail("login response had no token")
    return token


def ensure_root(server_status: dict, env: dict[str, str]) -> None:
    if server_status.get("isInit"):
        if not env.get("ABS_TEST_PASSWORD"):
            fail("server is already initialized but tool/test-server/.env has no "
                 "credentials. Run: .\\tool\\dev.ps1 server reset")
        log("root user already initialized")
        return
    status, payload = request("POST", "/init", {
        "newRoot": {"username": env["ABS_TEST_USER"],
                    "password": env["ABS_TEST_PASSWORD"]}})
    if status != 200:
        fail(f"POST /init failed (HTTP {status}): {payload}")
    log(f"initialized root user {env['ABS_TEST_USER']}")


def generate_media() -> None:
    # Bytes, not text: text mode on Windows would send CRLF line endings to sh.
    result = subprocess.run(["docker", "exec", "-i", CONTAINER, "sh", "-s"],
                            input=MEDIA_SCRIPT.encode(), capture_output=True)
    out = result.stdout.decode(errors="replace")
    if result.returncode != 0 or "media-ok" not in out:
        err = result.stderr.decode(errors="replace").strip()
        fail(f"generating test media failed: {err or out.strip()}")
    log("test media ready (3-file MP3 book, 2-chapter M4B, unicode MP3 book, 2-episode podcast)")


def ensure_library(token: str, name: str = LIBRARY_NAME,
                   folder: str = LIBRARY_FOLDER, media_type: str = "book") -> str:
    status, payload = request("GET", "/api/libraries", token=token)
    if status != 200 or not isinstance(payload, dict):
        fail(f"GET /api/libraries failed (HTTP {status})")
    for lib in payload.get("libraries", []):
        if lib.get("name") == name:
            log(f"library exists ({lib['id']})")
            return lib["id"]
    status, payload = request("POST", "/api/libraries", {
        "name": name,
        "folders": [{"fullPath": folder}],
        "icon": "audiobookshelf" if media_type == "book" else "podcast",
        "mediaType": media_type,
        "provider": "google" if media_type == "book" else "itunes",
    }, token=token)
    if status != 200 or not isinstance(payload, dict):
        fail(f"creating the library failed (HTTP {status}): {payload}")
    log(f"created library {payload['id']}")
    return payload["id"]


def ensure_listener(token: str, env: dict[str, str]) -> None:
    status, payload = request("GET", "/api/users", token=token)
    if status != 200 or not isinstance(payload, dict):
        fail(f"GET /api/users failed (HTTP {status})")
    if any(u.get("username") == env["ABS_TEST_USER2"] for u in payload.get("users", [])):
        log("second account exists")
        return
    status, payload = request("POST", "/api/users", {
        "username": env["ABS_TEST_USER2"],
        "password": env["ABS_TEST_PASSWORD2"],
        "type": "user",
        "isActive": True,
    }, token=token)
    if status != 200:
        fail(f"creating the second account failed (HTTP {status}): {payload}")
    log(f"created second account {env['ABS_TEST_USER2']}")


def scan_and_wait(token: str, library_id: str, titles: tuple[str, ...] = ALL_BOOKS,
                  timeout_s: float = 120) -> None:
    request("POST", f"/api/libraries/{library_id}/scan", token=token)
    deadline = time.time() + timeout_s
    found: set[str] = set()
    while time.time() < deadline:
        status, payload = request(
            "GET", f"/api/libraries/{library_id}/items?limit=50", token=token)
        if status == 200 and isinstance(payload, dict):
            found = {r.get("media", {}).get("metadata", {}).get("title")
                     for r in payload.get("results", [])}
            if all(b in found for b in titles):
                log(f"library has all {len(titles)} expected titles ({payload.get('total')} items)")
                return
        time.sleep(2)
    # ascii(): a redirected Windows stdout may not take the non-ASCII titles.
    fail(f"scan did not find {ascii(titles)} within {timeout_s:.0f}s "
         f"(found {ascii(sorted(t for t in found if t))})")


def main() -> None:
    env = read_env()
    env.setdefault("ABS_TEST_URL", BASE_URL)
    if env["ABS_TEST_URL"] != BASE_URL:
        fail(f".env points at {env['ABS_TEST_URL']}; only {BASE_URL} is allowed")
    env.setdefault("ABS_TEST_USER", ROOT_USER)
    env.setdefault("ABS_TEST_PASSWORD", secrets.token_urlsafe(18))
    env.setdefault("ABS_TEST_USER2", LISTENER_USER)
    env.setdefault("ABS_TEST_PASSWORD2", secrets.token_urlsafe(18))

    server_status = wait_for_server()
    log(f"server up (v{server_status.get('serverVersion', '?')})")
    if not server_status.get("isInit"):
        write_env(env)  # before /init, so the credentials can never be lost
    ensure_root(server_status, env)
    token = login(env["ABS_TEST_USER"], env["ABS_TEST_PASSWORD"])
    generate_media()
    library_id = ensure_library(token)
    env["ABS_TEST_LIBRARY_ID"] = library_id
    ensure_listener(token, env)
    write_env(env)
    scan_and_wait(token, library_id)
    podcast_library_id = ensure_library(token, PODCAST_LIBRARY_NAME, PODCAST_FOLDER, "podcast")
    scan_and_wait(token, podcast_library_id, (PODCAST_TITLE,))
    log(f"done; credentials in {ENV_FILE.relative_to(HERE.parent.parent)}")


if __name__ == "__main__":
    main()
