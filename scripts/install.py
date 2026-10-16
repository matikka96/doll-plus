#!/usr/bin/env python3
"""Install the personal Doll Plus from main.

    python3 -I scripts/install.py

Config/Local.xcconfig gives the signing identity, so the copy keeps its Accessibility permission.
"""

import os
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCAL_XCCONFIG = ROOT / "Config/Local.xcconfig"
DERIVED_DATA = ROOT / "build/install/DerivedData"
BUILT_APP = DERIVED_DATA / "Build/Products/Release/Doll Plus.app"
BUNDLE_ID = "com.matikka96.DollPlus"
INSTALLED_APP = Path("/Applications") / BUILT_APP.name
INSTALLED_BINARY = INSTALLED_APP / "Contents/MacOS" / BUILT_APP.stem
# No .app extension, so Launch Services does not register these copies.
STAGING = INSTALLED_APP.with_name(f".{BUILT_APP.stem}.installing")
BACKUP = INSTALLED_APP.with_name(f".{BUILT_APP.stem}.previous")
QUIT_TIMEOUT = 10.0
POLL = 0.25
LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"


def git(*args) -> str:
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True, capture_output=True, text=True).stdout.strip()


def require_clean_main():
    if (branch := git("rev-parse", "--abbrev-ref", "HEAD")) != "main":
        sys.exit(f"ERROR  the checkout is on {branch}. Install only from main")
    if git("status", "--porcelain"):
        sys.exit("ERROR  the tree has changes. Install only from a clean tree")


def team_id() -> str:
    if not LOCAL_XCCONFIG.is_file():
        sys.exit(f"ERROR  {LOCAL_XCCONFIG.relative_to(ROOT)} does not exist. "
                 "Without it, the build has an ad-hoc signature and loses the Accessibility permission")
    match = re.search(r'^\s*DEVELOPMENT_TEAM\s*=\s*"?([A-Za-z0-9]+)', LOCAL_XCCONFIG.read_text(), re.MULTILINE)
    if not match:
        sys.exit(f"ERROR  {LOCAL_XCCONFIG.relative_to(ROOT)} has no DEVELOPMENT_TEAM")
    return match.group(1)


def build(team: str):
    result = subprocess.run(["xcodebuild", "-project", str(ROOT / "DollPlus.xcodeproj"), "-scheme", "DollPlus",
                             "-configuration", "Release", "-destination", f"platform=macOS,arch={os.uname().machine}",
                             "-derivedDataPath", str(DERIVED_DATA), "-quiet", "build"],
                            capture_output=True, text=True)
    print((result.stdout + result.stderr).replace(team, "<team ID>"), end="")
    if result.returncode != 0:
        sys.exit("ERROR  the Release build failed")


def require_release_identity(team: str):
    with open(BUILT_APP / "Contents/Info.plist", "rb") as f:
        info = plistlib.load(f)
    identity = info.get("CFBundleIdentifier"), info.get("CFBundleName"), info.get("CFBundleDisplayName")
    if identity != (BUNDLE_ID, BUILT_APP.stem, BUILT_APP.stem):
        sys.exit(f"ERROR  the Release product has the identity {identity}, expected {BUNDLE_ID} and {BUILT_APP.stem!r}")
    signature = subprocess.run(["codesign", "-dv", str(BUILT_APP)], capture_output=True, text=True)
    if signature.returncode != 0 or f"TeamIdentifier={team}" not in signature.stderr.splitlines():
        sys.exit("ERROR  the Release product has no signature of the team in Config/Local.xcconfig")


def installed_pids() -> list[int]:
    processes = subprocess.run(["ps", "-axo", "pid=,comm="], check=True, capture_output=True, text=True).stdout.splitlines()
    rows = [line.split(None, 1) for line in processes]
    return [int(row[0]) for row in rows if len(row) == 2 and row[1] == str(INSTALLED_BINARY)]


def quit_installed():
    for pid in installed_pids():
        os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + QUIT_TIMEOUT
    while installed_pids():
        if time.monotonic() > deadline:
            sys.exit(f"ERROR  {INSTALLED_APP} did not quit in {QUIT_TIMEOUT:.0f} s")
        time.sleep(POLL)


def stage():
    shutil.rmtree(STAGING, ignore_errors=True)
    subprocess.run(["ditto", str(BUILT_APP), str(STAGING)], check=True)
    # Launch Services can register the product after xcodebuild exits.
    shutil.rmtree(BUILT_APP)


def replace_installed():
    shutil.rmtree(BACKUP, ignore_errors=True)
    if INSTALLED_APP.exists():
        INSTALLED_APP.rename(BACKUP)
    try:
        STAGING.rename(INSTALLED_APP)
    except OSError:
        if BACKUP.exists():
            BACKUP.rename(INSTALLED_APP)
        raise
    shutil.rmtree(BACKUP, ignore_errors=True)


def main():
    require_clean_main()
    team = team_id()
    try:
        build(team)
        require_release_identity(team)
        stage()
        quit_installed()
        try:
            replace_installed()
        finally:
            if INSTALLED_APP.exists():
                subprocess.run(["open", str(INSTALLED_APP)], check=True)
    finally:
        # Xcode registers each product that it builds. lsregister -u fails for an app that is not registered.
        subprocess.run([LSREGISTER, "-u", str(BUILT_APP)], capture_output=True)
    print(f"Installed {INSTALLED_APP} from main at {git('rev-parse', '--short', 'HEAD')}")


if __name__ == "__main__":
    main()
