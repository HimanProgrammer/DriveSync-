"""Claude-powered assistant for the Drive sync agent.

Chat in plain language, e.g.:
  "What changed since the last backup?"
  "Back up my Documents, but skip videos and installers."
  "Which PDFs did you upload this week?"

Claude decides which files to back up using the tools below; uploads go
through the same SyncAgent (and sync_state.json) as agent.py.

Run:  python ai_agent.py
Needs ANTHROPIC_API_KEY set (or an `ant auth login` profile).
"""
import json
import time
from pathlib import Path

import anthropic
from anthropic import beta_tool

from agent import CONFIG, SyncAgent, log

MODEL = "claude-opus-5-5"
SYSTEM = (
    "You are DriveSync, an assistant that backs up the user's Windows files to "
    "Google Drive. Use the tools to inspect watched folders and sync state. "
    "Only upload files inside the watched folders. Skip obvious junk (temp files, "
    "caches, installers, very large media) unless the user asks for it. Before "
    "uploading more than 25 files at once, tell the user what you plan and ask "
    "for confirmation. Keep answers short and plain."
)

client = anthropic.Anthropic()
sync = SyncAgent()
roots = [Path(p).resolve() for p in CONFIG["watch_folders"]]


def _root_for(path: Path):
    for r in roots:
        if path == r or r in path.parents:
            return r
    return None


@beta_tool
def list_watched_folders() -> str:
    """List the local folders being backed up and the Drive folder they go to."""
    return json.dumps({"watch_folders": [str(r) for r in roots],
                       "drive_root_folder": CONFIG["drive_root_folder"]})


@beta_tool
def find_pending_files(limit: int = 200) -> str:
    """List files in watched folders that are new or changed since their last upload.

    Args:
        limit: Maximum number of files to return.
    """
    out = []
    for root in roots:
        for p in root.rglob("*"):
            try:
                if sync.should_skip(p):
                    continue
                entry = sync.state["files"].get(str(p))
                mtime = time.strftime("%Y-%m-%d %H:%M", time.localtime(p.stat().st_mtime))
                if not entry or entry.get("synced_at", "") < mtime:
                    out.append({"path": str(p), "size_kb": p.stat().st_size // 1024,
                                "modified": mtime, "status": "changed" if entry else "new"})
            except OSError:
                continue
            if len(out) >= limit:
                return json.dumps({"files": out, "truncated": True})
    return json.dumps({"files": out, "truncated": False})


@beta_tool
def upload_files(paths: list[str]) -> str:
    """Upload (or update) the given files to Google Drive.

    Args:
        paths: Absolute file paths; each must be inside a watched folder.
    """
    results = []
    for raw in paths:
        p = Path(raw).resolve()
        root = _root_for(p)
        if root is None:
            results.append({"path": raw, "result": "refused: outside watched folders"})
            continue
        before = sync.state["files"].get(str(p), {}).get("sha256")
        sync.upload(p, root)
        after = sync.state["files"].get(str(p), {}).get("sha256")
        results.append({"path": raw, "result": "uploaded" if after and after != before
                        else "unchanged or skipped"})
    return json.dumps(results)


@beta_tool
def search_synced_files(query: str = "", limit: int = 50) -> str:
    """Search the record of files already backed up.

    Args:
        query: Case-insensitive text to match in the file path (empty = all).
        limit: Maximum number of results.
    """
    q = query.lower()
    hits = [{"path": k, "synced_at": v.get("synced_at"), "drive_id": v["id"]}
            for k, v in sync.state["files"].items() if q in k.lower()]
    hits.sort(key=lambda h: h["synced_at"] or "", reverse=True)
    return json.dumps({"total": len(hits), "files": hits[:limit]})


TOOLS = [list_watched_folders, find_pending_files, upload_files, search_synced_files]


def ask(messages: list) -> str:
    runner = client.beta.messages.tool_runner(
        model=MODEL,
        max_tokens=16000,
        system=SYSTEM,
        tools=TOOLS,
        messages=messages,
        output_config={"effort": "medium"},
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
    )
    final = None
    for message in runner:
        final = message
        messages.append({"role": "assistant", "content": message.content})
        tool_response = runner.generate_tool_call_response()
        if tool_response is not None:
            messages.append(tool_response)
    if final is None:
        return ""
    if final.stop_reason == "refusal":
        return "(Claude declined this request.)"
    return "".join(b.text for b in final.content if b.type == "text")


def main():
    print("DriveSync AI agent. Type a request, or 'quit' to exit.")
    messages = []
    while True:
        try:
            text = input("\nyou> ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if text.lower() in ("quit", "exit"):
            break
        if not text:
            continue
        messages.append({"role": "user", "content": text})
        try:
            print("\ndrivesync>", ask(messages))
        except anthropic.APIError as e:
            log.error("Claude API error: %s", e)
            print("Error talking to Claude:", e)
            messages.pop()


if __name__ == "__main__":
    main()
