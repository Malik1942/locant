#!/usr/bin/env python3
"""Record Locant's public GitHub numbers over time and report them.

Touches only GitHub's API, as you, through `gh`. The app is not involved and reports
nothing, so this counts downloads, never people or active users.

    scripts/stats.py                     take a snapshot, then print the report
    scripts/stats.py --report            print the report from saved snapshots
    scripts/stats.py --window 2026-11-17T00:01 --hours 48
                                         what changed in that window (no time zone = local)
    scripts/stats.py --install-daily     snapshot every day at 00:05 (launchd)
    scripts/stats.py --uninstall-daily   stop that; the saved data stays

The numbers stay on this Mac, in ~/Library/Application Support/locant-stats (not the repo,
which is public). GitHub keeps traffic for only 14 days, so traffic.csv is the only long
record of it. launchd runs a copy kept beside the data, because agents can't read
~/Documents; run --install-daily again after changing this file.
"""

import argparse
import csv
import json
import os
import plistlib
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO = "Malik1942/locant"
LABEL = "com.malikzhang.locant-stats"
DATA = Path(
    os.environ.get(
        "LOCANT_STATS_DIR",
        Path.home() / "Library/Application Support/locant-stats",
    )
)
AGENT = Path.home() / "Library/LaunchAgents" / f"{LABEL}.plist"
AGENT_PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

DOWNLOADS = ("downloads.csv", ["at", "tag", "published", "asset", "downloads"])
REPO_STATS = ("repo.csv", ["at", "stars", "forks", "watchers"])
TRAFFIC = ("traffic.csv", ["date", "kind", "count", "uniques"])


def gh(path):
    binary = shutil.which("gh") or "/opt/homebrew/bin/gh"
    result = subprocess.run([binary, "api", path], capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"gh api {path} failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def releases():
    found, page = [], 1
    while True:
        batch = gh(f"repos/{REPO}/releases?per_page=100&page={page}")
        if not batch:
            return found
        found += batch
        page += 1


def read(table):
    name, _ = table
    path = DATA / name
    if not path.exists():
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def write(table, rows):
    name, fields = table
    path = DATA / name
    temporary = path.with_suffix(".tmp")
    with temporary.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


def snapshot(now):
    """Fetch everything first, so a failed request leaves the saved data untouched."""
    at = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    new_downloads = [
        {
            "at": at,
            "tag": release["tag_name"],
            "published": (release["published_at"] or "")[:10],
            "asset": asset["name"],
            "downloads": asset["download_count"],
        }
        for release in releases()
        for asset in release["assets"]
        if asset["name"].endswith(".dmg")
    ]
    repo = gh(f"repos/{REPO}")
    new_repo = {
        "at": at,
        "stars": repo["stargazers_count"],
        "forks": repo["forks_count"],
        "watchers": repo["subscribers_count"],
    }
    # A day's numbers keep changing until it ends, so the newest reading replaces the older.
    traffic = {(row["date"], row["kind"]): row for row in read(TRAFFIC)}
    for kind in ("views", "clones"):
        for day in gh(f"repos/{REPO}/traffic/{kind}")[kind]:
            date = day["timestamp"][:10]
            traffic[(date, kind)] = {
                "date": date,
                "kind": kind,
                "count": day["count"],
                "uniques": day["uniques"],
            }

    DATA.mkdir(parents=True, exist_ok=True)
    write(DOWNLOADS, read(DOWNLOADS) + new_downloads)
    write(REPO_STATS, read(REPO_STATS) + [new_repo])
    write(TRAFFIC, [traffic[key] for key in sorted(traffic)])


def parse_time(text):
    moment = datetime.fromisoformat(text.replace("Z", "+00:00"))
    return moment.astimezone(timezone.utc)


def local(moment):
    return moment.astimezone().strftime("%Y-%m-%d %H:%M %Z")


def version(tag):
    parts = []
    for piece in tag.lstrip("v").split("."):
        parts.append(int(piece) if piece.isdigit() else 0)
    return tuple(parts + [0] * (3 - len(parts)))


def download_totals():
    """Total dmg downloads at each snapshot, oldest first."""
    totals = {}
    for row in read(DOWNLOADS):
        totals[row["at"]] = totals.get(row["at"], 0) + int(row["downloads"])
    return sorted((parse_time(at), total) for at, total in totals.items())


def star_history():
    return sorted((parse_time(row["at"]), int(row["stars"])) for row in read(REPO_STATS))


def at_or_before(history, moment):
    earlier = [entry for entry in history if entry[0] <= moment]
    return earlier[-1] if earlier else None


def nearest(history, moment):
    return min(history, key=lambda entry: abs(entry[0] - moment))


def need_snapshots():
    if not download_totals():
        sys.exit("No snapshots yet. Run scripts/stats.py first.")


def report():
    need_snapshots()
    totals = download_totals()
    latest_at, total = totals[-1]
    stamp = latest_at.strftime("%Y-%m-%dT%H:%M:%SZ")
    per_tag = {}
    published = {}
    for row in read(DOWNLOADS):
        if row["at"] == stamp:
            per_tag[row["tag"]] = per_tag.get(row["tag"], 0) + int(row["downloads"])
            published[row["tag"]] = row["published"]
    newest = max(per_tag, key=version)

    print(f"Locant, as of {local(latest_at)} (snapshots: {len(totals)})")
    print()
    print("dmg downloads (downloads, not people; your own are included)")
    print(f"  All releases      {total}")
    print(f"  Since v1.0.0      {sum(n for tag, n in per_tag.items() if version(tag) >= (1, 0, 0))}")
    print(f"  {newest:<17} {per_tag[newest]}  (published {published[newest]})")
    for label, days in (("Last 24 hours", 1), ("Last 7 days", 7), ("Last 30 days", 30)):
        past = at_or_before(totals, latest_at - timedelta(days=days))
        change = (
            f"+{total - past[1]}  (since {local(past[0])})"
            if past
            else "not enough history yet"
        )
        print(f"  {label:<17} {change}")

    repo = max(read(REPO_STATS), key=lambda row: row["at"])
    print()
    print(f"Repo: {repo['stars']} stars, {repo['forks']} forks, {repo['watchers']} watchers")

    traffic = read(TRAFFIC)
    cutoff = (latest_at - timedelta(days=14)).strftime("%Y-%m-%d")
    print()
    print("Traffic (clones include CI runs and other machines)")
    for kind in ("views", "clones"):
        rows = [row for row in traffic if row["kind"] == kind]
        recent = sum(int(row["count"]) for row in rows if row["date"] >= cutoff)
        recorded = sum(int(row["count"]) for row in rows)
        print(f"  {kind:<7} last 14 days {recent:<5} recorded since {rows[0]['date'] if rows else '-'}: {recorded}")


def window(start_text, hours):
    need_snapshots()
    start = parse_time(start_text)
    end = start + timedelta(hours=hours)
    totals, stars = download_totals(), star_history()
    print(f"Window: {local(start)} to {local(end)}")

    def change(name, history):
        # Nearest, not "before": a launch at 00:01 belongs with the 00:05 snapshot, not yesterday's.
        first = nearest(history, start)
        if abs(first[0] - start) > timedelta(days=1):
            print(f"  {name}: no snapshot within a day of the start, nearest is {local(first[0])}")
            return
        over = end <= history[-1][0]
        last = nearest(history, end) if over else history[-1]
        note = "" if over else "  (window not over; latest snapshot used)"
        print(f"  {name}: +{last[1] - first[1]}  ({local(first[0])} to {local(last[0])}){note}")

    change("Downloads", totals)
    change("Stars", stars)


def install():
    DATA.mkdir(parents=True, exist_ok=True)
    copy = DATA / "stats.py"
    shutil.copy2(__file__, copy)
    AGENT.parent.mkdir(parents=True, exist_ok=True)
    with AGENT.open("wb") as f:
        plistlib.dump(
            {
                "Label": LABEL,
                "ProgramArguments": ["/usr/bin/python3", str(copy), "--quiet"],
                "StartCalendarInterval": {"Hour": 0, "Minute": 5},
                "EnvironmentVariables": {"PATH": AGENT_PATH},
                "StandardOutPath": str(DATA / "launchd.log"),
                "StandardErrorPath": str(DATA / "launchd.log"),
            },
            f,
        )
    domain = f"gui/{os.getuid()}"
    subprocess.run(["launchctl", "bootout", f"{domain}/{LABEL}"], capture_output=True)
    subprocess.run(["launchctl", "bootstrap", domain, str(AGENT)], check=True)
    print(f"Daily snapshot at 00:05 installed. Data: {DATA}")


def uninstall():
    subprocess.run(
        ["launchctl", "bootout", f"gui/{os.getuid()}/{LABEL}"], capture_output=True
    )
    AGENT.unlink(missing_ok=True)
    print(f"Daily snapshot removed. The data stays in {DATA}")


def main():
    parser = argparse.ArgumentParser(description="Locant's public GitHub numbers.")
    parser.add_argument("--report", action="store_true", help="report without a new snapshot")
    parser.add_argument("--quiet", action="store_true", help="snapshot without the report")
    parser.add_argument("--window", metavar="START", help="what changed from START (ISO time)")
    parser.add_argument("--hours", type=float, default=48, help="length of --window (default 48)")
    parser.add_argument("--install-daily", action="store_true")
    parser.add_argument("--uninstall-daily", action="store_true")
    args = parser.parse_args()

    if args.install_daily:
        install()
    elif args.uninstall_daily:
        uninstall()
    elif args.window:
        window(args.window, args.hours)
    elif args.report:
        report()
    else:
        snapshot(datetime.now(timezone.utc))
        if not args.quiet:
            report()


if __name__ == "__main__":
    main()
