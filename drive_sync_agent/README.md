# C: Drive → Google Drive Sync Agent

Watches folders on your Windows PC and automatically uploads new or changed files to Google Drive, mirroring the folder structure. It keeps track of what has been uploaded (`sync_state.json`) and logs every action to `agent.log`.

## Setup (Windows)
1. Install Python 3.10+ from python.org.
2. `pip install -r requirements.txt`
3. Google Cloud Console → create a project → enable **Google Drive API** → OAuth consent screen (External, add yourself as test user) → Credentials → **OAuth client ID → Desktop app** → download JSON, save as `credentials.json` in this folder.
4. Edit `config.json`: set `watch_folders` (don't watch all of `C:\` — pick folders like Documents/Desktop).
5. `python agent.py` — a browser opens once to sign in; afterwards it runs on its own.

## Run automatically at startup
Task Scheduler → Create Task → Trigger: *At log on* → Action: `pythonw.exe` with argument `C:\path\to\agent.py`.

## Notes
- Only the `drive.file` scope is used: the agent can only see files it created.
- Locked files (open in Office etc.) are retried on the next rescan.
- Delete `sync_state.json` to force a full re-upload.
