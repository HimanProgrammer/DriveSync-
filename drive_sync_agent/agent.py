"""C: drive -> Google Drive sync agent.

Watches folders on a Windows PC and uploads new/changed files to Google Drive.
Keeps a local state file so each file version is uploaded only once.

Run:  python agent.py            (watch forever)
      python agent.py --once     (scan once, upload, exit)
"""
import argparse
import hashlib
import json
import logging
import os
import time
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

HERE = Path(__file__).parent
CONFIG = json.loads((HERE / "config.json").read_text())
STATE_FILE = HERE / "sync_state.json"
TOKEN_FILE = HERE / "token.json"
SCOPES = ["https://www.googleapis.com/auth/drive.file"]

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[logging.FileHandler(HERE / "agent.log"), logging.StreamHandler()],
)
log = logging.getLogger("drive-agent")


def drive_service():
    creds = None
    if TOKEN_FILE.exists():
        creds = Credentials.from_authorized_user_file(str(TOKEN_FILE), SCOPES)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(str(HERE / "credentials.json"), SCOPES)
            creds = flow.run_local_server(port=0)
        TOKEN_FILE.write_text(creds.to_json())
    return build("drive", "v3", credentials=creds)


class SyncAgent:
    def __init__(self):
        self.svc = drive_service()
        self.state = json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else {"files": {}, "folders": {}}
        self.exclude = set(CONFIG.get("exclude_extensions", []))
        self.max_bytes = CONFIG.get("max_file_mb", 500) * 1024 * 1024

    def save(self):
        STATE_FILE.write_text(json.dumps(self.state, indent=2))

    def folder_id(self, rel_dir: Path) -> str:
        """Mirror local folder structure under the Drive root folder."""
        key = rel_dir.as_posix()
        if key in self.state["folders"]:
            return self.state["folders"][key]
        if key in ("", "."):
            parent, name = None, CONFIG["drive_root_folder"]
        else:
            parent, name = self.folder_id(rel_dir.parent), rel_dir.name
        meta = {"name": name, "mimeType": "application/vnd.google-apps.folder"}
        if parent:
            meta["parents"] = [parent]
        fid = self.svc.files().create(body=meta, fields="id").execute()["id"]
        self.state["folders"][key] = fid
        self.save()
        return fid

    def should_skip(self, p: Path) -> bool:
        return (
            not p.is_file()
            or p.suffix.lower() in self.exclude
            or p.name.startswith(("~$", "."))
            or p.stat().st_size > self.max_bytes
        )

    def upload(self, path: Path, watch_root: Path):
        try:
            if self.should_skip(path):
                return
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            key = str(path)
            entry = self.state["files"].get(key)
            if entry and entry["sha256"] == digest:
                return  # unchanged
            rel = Path(watch_root.name) / path.relative_to(watch_root)
            media = MediaFileUpload(str(path), resumable=True)
            if entry:
                self.svc.files().update(fileId=entry["id"], media_body=media).execute()
                log.info("UPDATED  %s", path)
            else:
                body = {"name": path.name, "parents": [self.folder_id(rel.parent)]}
                entry = {"id": self.svc.files().create(body=body, media_body=media, fields="id").execute()["id"]}
                log.info("UPLOADED %s", path)
            entry.update(sha256=digest, synced_at=time.strftime("%Y-%m-%d %H:%M:%S"))
            self.state["files"][key] = entry
            self.save()
        except PermissionError:
            log.warning("Locked/no access, will retry later: %s", path)
        except Exception as e:  # keep agent alive
            log.error("Failed %s: %s", path, e)

    def full_scan(self):
        for root in map(Path, CONFIG["watch_folders"]):
            for p in root.rglob("*"):
                self.upload(p, root)


class Handler(FileSystemEventHandler):
    def __init__(self, agent, root):
        self.agent, self.root = agent, root

    def on_created(self, e):
        if not e.is_directory:
            time.sleep(CONFIG.get("settle_seconds", 2))  # let the write finish
            self.agent.upload(Path(e.src_path), self.root)

    on_modified = on_created

    def on_moved(self, e):
        if not e.is_directory:
            self.agent.upload(Path(e.dest_path), self.root)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true")
    args = ap.parse_args()
    agent = SyncAgent()
    agent.full_scan()
    if args.once:
        return
    obs = Observer()
    for root in map(Path, CONFIG["watch_folders"]):
        obs.schedule(Handler(agent, root), str(root), recursive=True)
        log.info("Watching %s", root)
    obs.start()
    try:
        while True:
            time.sleep(CONFIG.get("rescan_minutes", 30) * 60)
            agent.full_scan()  # catch anything the watcher missed
    except KeyboardInterrupt:
        obs.stop()
    obs.join()


if __name__ == "__main__":
    main()
