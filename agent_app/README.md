# DriveSync Agent (floating app)

A separate, always-on-top desktop app: the DriveSync character floats on
your screen (outside any app window), talks, and shows speech bubbles.

- **Drag** him anywhere. **Tap** to open/close the monitor panel.
  **Double-tap** to repeat the last message.
  **Right-click** (or long-press) for Mute / Quit.
- Starts at the bottom-right of the screen.

## Call him
Press **Ctrl + Alt + Space** anywhere to call the agent (he pops up and
gives a quick status). Press it again, or right-click > Hide, to send him
away. Apps and scripts can also call him with `POST /show` and `POST /hide`.

## Connects to any app
The agent listens on `http://127.0.0.1:47823` (this PC only):

```
POST /say   {"app": "My App", "text": "Hello from my app!"}
GET  /ping  -> ok
POST /status {...}   (DriveSync sends a snapshot every 5 s)
GET  /status         -> {"live": true, "status": {...}}
```

## Monitors DriveSync
While DriveSync is open on the same PC, the monitor panel shows: internet,
Google Drive account and usage, backup running/uploaded/waiting/failed,
daily backup time, last backup, how full each drive is, and your open
to-do tasks. A green dot means DriveSync is connected; red means it isn't
running.

DriveSync sends its announcements here automatically (internet changes,
auto/daily backups, storage alerts). Any other app or script can too, e.g.
PowerShell:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:47823/say `
  -ContentType 'application/json' -Body '{"app":"Script","text":"Done!"}'
```

## Run / build (Windows)
```
cd agent_app
flutter pub get
flutter run -d windows        # or: flutter build windows
```
To start it with Windows, put a shortcut to the built
`drivesync_agent.exe` in `shell:startup`.
