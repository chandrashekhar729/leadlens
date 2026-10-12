#!/usr/bin/env python3
"""LeadLens dashboard server (stdlib only).

Serves this folder on 0.0.0.0 and builds /data.json live from the plugin's own
output: every <project>/.claude/reports/data/*/inventory.json under the project
roots in LEADLENS_PROJECTS (comma-separated; default: every sibling of the
project Claude was started in). serve.sh starts it on SessionStart. No report run yet => {"weeks": [], "users": []} and the page
shows its empty state. Nothing is mocked.
"""
import glob
import http.server
import json
import os
import socket
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENV = HERE / ".env"
MAX_WEEKS = 8


def load_env():
    if ENV.exists():
        for line in ENV.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())


def project_roots():
    raw = os.environ.get("LEADLENS_PROJECTS", "")
    roots = [Path(p).expanduser() for p in raw.split(",") if p.strip()]
    # default: every sibling of the project Claude was started in (hooks set CLAUDE_PROJECT_DIR)
    base = Path(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()).resolve().parent
    return roots or [p for p in base.iterdir() if p.is_dir()]


def inventories():
    for root in project_roots():
        for f in sorted(glob.glob(str(root / ".claude" / "reports" / "data" / "*" / "inventory.json"))):
            try:
                yield Path(root).name, json.loads(Path(f).read_text())
            except (OSError, ValueError) as e:
                print(f"skip {f}: {e}", file=sys.stderr)


def monday(d):
    return (d - timedelta(days=d.weekday())).date()


def build_data():
    """One row per author per ISO week, aggregated from commits; dedup by sha."""
    seen = set()
    people = {}          # key -> {name, repos:set, weeks:{monday:{...}}, heat:[7][24]}
    for repo, inv in inventories():
        for c in inv.get("commits", []):
            sha = c.get("sha")
            if not sha or sha in seen or c.get("is_merge"):
                continue
            seen.add(sha)
            try:
                when = datetime.fromisoformat(c["date"])
            except (KeyError, ValueError):
                continue
            key = (c.get("author_email") or c.get("author_name") or "?").lower()
            p = people.setdefault(key, {"name": c.get("author_name") or key, "repos": set(),
                                        "weeks": defaultdict(lambda: {"commits": 0, "merged": 0, "lines": 0, "hits": 0}),
                                        "heat": [[0] * 24 for _ in range(7)]})
            p["repos"].add(repo)
            w = p["weeks"][monday(when)]
            w["commits"] += 1
            on_main = any(b.split("/")[-1] in ("master", "main") for b in (c.get("branches") or []))
            w["merged"] += 1 if (c.get("merged_into_default") or on_main or str(c.get("status", "")).startswith("In ")) else 0
            w["lines"] += (c.get("insertions") or 0) + (c.get("deletions") or 0)
            w["hits"] += len(c.get("pattern_hits") or [])
            p["heat"][when.weekday()][when.hour] += 1
    if not people:
        return {"weeks": [], "users": [], "generatedAt": datetime.now().isoformat(timespec="seconds")}
    last = max(wk for p in people.values() for wk in p["weeks"])
    weeks = [last - timedelta(weeks=i) for i in range(MAX_WEEKS - 1, -1, -1)]
    users = []
    for i, (key, p) in enumerate(sorted(people.items(), key=lambda kv: kv[1]["name"].lower())):
        first = min(p["weeks"])
        history = []
        for wk in weeks:
            if wk < first:
                continue
            w = p["weeks"].get(wk)
            n = w["commits"] if w else 0
            history.append({"week": wk.isoformat(), "commits": n,
                            "mergedPct": round(100 * w["merged"] / n, 1) if n else 0,
                            # ponytail: a week with no commits gets the worst size bound so it scores low, not 100
                            "avgLines": round(w["lines"] / n) if n else 800,
                            "patternHits": w["hits"] if w else 0})
        name = p["name"]
        initials = "".join(s[0] for s in name.split()[:2]).upper() or "?"
        users.append({"id": f"u{i:02d}", "name": name, "role": ", ".join(sorted(p["repos"])),
                      "initials": initials, "history": history, "heatmap": p["heat"]})
    return {"range": f"last-{MAX_WEEKS}-weeks", "weeks": [w.isoformat() for w in weeks],
            "generatedAt": datetime.now().isoformat(timespec="seconds"), "users": users}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(HERE), **kw)

    def do_GET(self):
        if self.path.split("?")[0] == "/data.json":
            body = json.dumps(build_data()).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def log_message(self, fmt, *args):
        pass


def lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def main():
    load_env()
    if "--print-data" in sys.argv:
        print(json.dumps(build_data(), indent=1))
        return
    port = int(os.environ.get("LEADLENS_PORT", "8850"))
    try:
        server = http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler)
    except OSError:
        sys.exit(f"Port {port} is already in use. Change LEADLENS_PORT in {ENV}")
    roots = ", ".join(str(r) for r in project_roots())
    print("LeadLens dashboard")
    print(f"  this PC:   http://localhost:{port}/")
    print(f"  share:     http://{lan_ip()}:{port}/")
    print(f"  by name:   http://{socket.gethostname()}.local:{port}/")
    print(f"  data from: {roots}")
    print("Ctrl+C to stop", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
