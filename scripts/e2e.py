#!/usr/bin/env python3
"""End-to-end scenarios for Doll Plus.

    python3 -I scripts/e2e.py build             build Doll Plus, the fixtures and the Dock probe
    python3 -I scripts/e2e.py probe [--prompt]  print the Dock items as JSON
    python3 -I scripts/e2e.py run [NAME ...]    run all or the named scenarios
    python3 -I scripts/e2e.py list              list the scenarios

The process that runs this script needs the Accessibility permission. Doll Plus
runs as a child process, so macOS checks the permission of the terminal.
"""

import argparse
import json
import os
import plistlib
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
E2E = BUILD / "e2e"
DERIVED_DATA = BUILD / "DerivedData"
APP_BINARY = DERIVED_DATA / "Build/Products/Debug/Doll Plus.app/Contents/MacOS/Doll Plus"
PROBE = E2E / "dock-probe"
STATE_FILE = E2E / "state.json"
LOGS = E2E / "logs"
SCREENSHOTS = E2E / "screenshots"
LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

POLL = 0.25
TIMEOUT = 8.0
STABLE_WINDOW = 5.0


@dataclass(frozen=True)
class Fixture:
    key: str
    bundle_id: str
    bundle_name: str
    folder_name: str
    display_name: str | None = None
    localized_display_name: str | None = None

    @property
    def app(self) -> Path:
        return E2E / "fixtures" / f"{self.folder_name}.app"

    @property
    def control_file(self) -> Path:
        return E2E / "control" / f"{self.bundle_id}.badge"

    @property
    def dock_title(self) -> str:
        return self.localized_display_name or self.display_name or self.bundle_name


FIXTURES = {
    "a": Fixture("a", "com.matikka96.DollPlus.fixture.a", "DollFixtureA", "DollFixtureA"),
    # Copies Outlook: the Dock shows the display name, CFBundleName differs.
    "b": Fixture("b", "com.matikka96.DollPlus.fixture.b", "DollFixtureB", "Doll Fixture Display", "Doll Fixture Display"),
    "c": Fixture("c", "com.matikka96.DollPlus.fixture.c", "DollFixtureC", "DollFixtureC",
                 localized_display_name="Doll Fixture Localized"),
}


class CheckFailed(Exception):
    pass


class EnvironmentProblem(Exception):
    pass


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, **kwargs)


def wait_until(condition, timeout=TIMEOUT, describe=lambda: ""):
    deadline = time.monotonic() + timeout
    while True:
        result = condition()
        if result:
            return result
        if time.monotonic() > deadline:
            detail = describe()
            raise CheckFailed(f"timed out after {timeout:.0f} s" + (f". {detail}" if detail else ""))
        time.sleep(POLL)



def build_app():
    run(["xcodebuild", "-project", str(ROOT / "DollPlus.xcodeproj"), "-scheme", "DollPlus",
         "-configuration", "Debug", "-destination", f"platform=macOS,arch={os.uname().machine}", "-derivedDataPath", str(DERIVED_DATA), "-quiet", "build"])


def build_fixture(fixture: Fixture):
    contents = fixture.app / "Contents"
    (contents / "MacOS").mkdir(parents=True, exist_ok=True)
    fixture.control_file.parent.mkdir(parents=True, exist_ok=True)
    info = {
        "CFBundleIdentifier": fixture.bundle_id,
        "CFBundleName": fixture.bundle_name,
        "CFBundleExecutable": fixture.bundle_name,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "13.0",
        "NSPrincipalClass": "NSApplication",
        "DollFixtureControlFile": str(fixture.control_file),
    }
    if fixture.display_name:
        info["CFBundleDisplayName"] = fixture.display_name
    if fixture.localized_display_name:
        # The development region applies when no preferred language has an .lproj.
        info["CFBundleDevelopmentRegion"] = "en"
        info["LSHasLocalizedDisplayName"] = True
        strings = contents / "Resources" / "en.lproj" / "InfoPlist.strings"
        strings.parent.mkdir(parents=True, exist_ok=True)
        strings.write_text(f'CFBundleDisplayName = "{fixture.localized_display_name}";\n')
    with open(contents / "Info.plist", "wb") as f:
        plistlib.dump(info, f)
    run(["swiftc", "-O", "-o", str(contents / "MacOS" / fixture.bundle_name),
         str(ROOT / "scripts/e2e/BadgeFixture.swift")])
    run(["codesign", "--force", "--sign", "-", str(fixture.app)], stderr=subprocess.DEVNULL)
    run([LSREGISTER, "-f", str(fixture.app)])


def build_probe():
    E2E.mkdir(parents=True, exist_ok=True)
    run(["swiftc", "-O", "-o", str(PROBE), str(ROOT / "scripts/e2e/DockProbe.swift")])


def build_all(skip_app=False):
    if not skip_app:
        build_app()
    build_probe()
    for fixture in FIXTURES.values():
        build_fixture(fixture)



def probe(prompt=False):
    args = [str(PROBE)] + (["--prompt"] if prompt else [])
    result = subprocess.run(args, capture_output=True, text=True)
    return json.loads(result.stdout)


def dock_item(fixture: Fixture):
    items = probe().get("items", [])
    return next((item for item in items if item["title"] == fixture.dock_title), None)


def require_trusted():
    if not PROBE.exists():
        raise EnvironmentProblem("the Dock probe does not exist. Run: python3 -I scripts/e2e.py build")
    if not probe().get("trusted"):
        raise EnvironmentProblem("this terminal has no Accessibility permission. Run: python3 -I scripts/e2e.py probe --prompt")


def set_badge(fixture: Fixture, text: str):
    fixture.control_file.write_text(text)


def wait_dock_label(fixture: Fixture, text: str):
    expected = text or None
    try:
        wait_until(lambda: (item := dock_item(fixture)) is not None and item["statusLabel"] == expected,
                   describe=lambda: f"Dock item: {dock_item(fixture)}")
    except CheckFailed as error:
        raise EnvironmentProblem(f"the Dock did not show the badge {text!r} for {fixture.dock_title}: {error}")


def fixture_pids(fixture: Fixture):
    result = subprocess.run(["pgrep", "-x", fixture.bundle_name], capture_output=True, text=True)
    return [int(pid) for pid in result.stdout.split()]


def launch_fixture(fixture: Fixture):
    run(["open", str(fixture.app)])
    try:
        wait_until(lambda: dock_item(fixture))
    except CheckFailed:
        raise EnvironmentProblem(f"{fixture.dock_title} did not appear in the Dock")


def quit_fixture(fixture: Fixture):
    for pid in fixture_pids(fixture):
        os.kill(pid, signal.SIGTERM)
    wait_until(lambda: not fixture_pids(fixture) and dock_item(fixture) is None)


def restart_dock():
    old_pid = probe().get("dockPid")
    run(["killall", "Dock"])
    try:
        wait_until(lambda: (p := probe()).get("dockPid") not in (None, old_pid) and p.get("items"), timeout=15)
    except CheckFailed:
        raise EnvironmentProblem("the Dock did not restart")



class DollPlus:
    def __init__(self, scenario: str, fixtures, red_badge: bool):
        self.scenario = scenario
        self.fixtures = fixtures
        self.red_badge = red_badge
        self.process = None

    def __enter__(self):
        if subprocess.run(["pgrep", "-x", "Doll Plus"], capture_output=True).returncode == 0:
            raise EnvironmentProblem("another Doll Plus process runs. Quit it first")
        if not APP_BINARY.exists():
            raise EnvironmentProblem("Doll Plus is not built. Run: python3 -I scripts/e2e.py build")
        STATE_FILE.unlink(missing_ok=True)
        LOGS.mkdir(parents=True, exist_ok=True)
        log = open(LOGS / f"{self.scenario}.log", "w")
        settings = {
            "SETTING_MONITORED_APP_IDS": ",".join(f.bundle_id for f in self.fixtures),
            "SETTINGS_Show_As_Red_Badge": plist_bool(self.red_badge),
            "SETTINGS_Show_Only_App_Icon": plist_bool(False),
            "SETTINGS_Hide_When_App_Not_Running": plist_bool(False),
            "SETTINGS_Hide_When_Nothing_Coming": plist_bool(False),
            "SETTINGS_Grayout_Icon_When_Nothing_Coming": plist_bool(False),
            "SETTINGS_SHOW_ALERT_IN_FULL_SCREEN_Mode": plist_bool(False),
            "SETTINGS_Giant_Badge_Enabled_Apps": "<dict/>",
            "SETTINGS_APPS_ICON_MASK": "<dict/>",
            "ApplePersistenceIgnoreState": "YES",
            "DollPlusStateFile": str(STATE_FILE),
        }
        args = [str(APP_BINARY)] + [token for key, value in settings.items() for token in (f"-{key}", value)]
        self.process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT)
        wait_until(lambda: len(self.state().get("apps", [])) == len(self.fixtures),
                   describe=lambda: f"state: {self.state()}")
        return self

    def __exit__(self, *exc):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()

    def state(self):
        if self.process and self.process.poll() is not None:
            raise CheckFailed(f"Doll Plus exited with code {self.process.returncode}")
        try:
            return json.loads(STATE_FILE.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

    def app(self, fixture: Fixture):
        apps = self.state().get("apps", [])
        return next((a for a in apps if a["bundleId"] == fixture.bundle_id), None)

    def wait_app(self, fixture: Fixture, condition, what: str, timeout=TIMEOUT):
        try:
            return wait_until(lambda: (a := self.app(fixture)) is not None and condition(a) and a, timeout=timeout)
        except CheckFailed as error:
            raise CheckFailed(f"{what}: {error}. Last state: {self.app(fixture)}")

    def wait_badge(self, fixture: Fixture, text: str, timeout=TIMEOUT):
        return self.wait_app(fixture, lambda a: a["badge"] == text,
                             f"Doll Plus did not show the badge {text!r}", timeout)

    def screenshot(self, fixture: Fixture, label: str):
        state = self.state()
        app = self.app(fixture)
        if not app or not app.get("frame"):
            return
        x, y, w, h = app["frame"]
        top = state["mainScreenHeight"] - (y + h)
        pad = 40
        SCREENSHOTS.mkdir(parents=True, exist_ok=True)
        path = SCREENSHOTS / f"{self.scenario}-{label}.png"
        region = f"{x - pad:.0f},{top:.0f},{w + 2 * pad:.0f},{h:.0f}"
        if subprocess.run(["screencapture", "-x", "-R", region, str(path)], capture_output=True).returncode == 0:
            print(f"    screenshot: {path.relative_to(ROOT)}")
        else:
            print("    screenshot failed. The terminal needs the Screen Recording permission.")


def plist_bool(value: bool) -> str:
    return "<true/>" if value else "<false/>"



@dataclass
class Scenario:
    name: str
    summary: str
    fixtures: tuple
    body: object
    known_issue: int | None = None
    red_badge: bool = False


SCENARIOS: list[Scenario] = []


def scenario(summary, fixtures=("a",), known_issue=None, red_badge=False):
    def register(body):
        SCENARIOS.append(Scenario(body.__name__.replace("_", "-"), summary,
                                  tuple(FIXTURES[k] for k in fixtures), body, known_issue, red_badge))
        return body
    return register


@scenario("A Dock badge shows in the menu bar")
def basic_badge(doll, a, screenshots):
    set_badge(a, "3")
    wait_dock_label(a, "3")
    app = doll.wait_badge(a, "3")
    if app["title"] != "3" or not app["visible"]:
        raise CheckFailed(f"the status item does not show '3': {app}")
    if screenshots:
        doll.screenshot(a, "badge")


@scenario("A cleared Dock badge clears the menu bar")
def clear_badge(doll, a, screenshots):
    set_badge(a, "5")
    wait_dock_label(a, "5")
    doll.wait_badge(a, "5")
    set_badge(a, "")
    wait_dock_label(a, "")
    app = doll.wait_badge(a, "")
    if app["title"] != "":
        raise CheckFailed(f"the status item still has a title: {app}")


@scenario("A two-digit badge fits in the status item")
def two_digit_fit(doll, a, screenshots):
    set_badge(a, "12")
    wait_dock_label(a, "12")
    app = doll.wait_badge(a, "12")
    if screenshots:
        doll.screenshot(a, "two-digits")
    if app["fittingWidth"] > app["length"] + 0.5:
        raise CheckFailed(f"the text needs {app['fittingWidth']} pt, the item has {app['length']} pt")


def assert_dock_title_match(doll, fixture, badge):
    set_badge(fixture, badge)
    wait_dock_label(fixture, badge)
    app = doll.wait_badge(fixture, badge)
    if app["appName"] != fixture.dock_title:
        raise CheckFailed(f"Doll Plus shows the name {app['appName']!r}, the Dock shows {fixture.dock_title!r}")


@scenario("An app whose Dock title differs from CFBundleName", fixtures=("b",))
def display_name(doll, b, screenshots):
    assert_dock_title_match(doll, b, "4")


@scenario("An app whose Dock title is a localized display name", fixtures=("c",))
def localized_name(doll, c, screenshots):
    assert_dock_title_match(doll, c, "6")


@scenario("Badges keep working after the Dock restarts")
def dock_restart(doll, a, screenshots):
    set_badge(a, "1")
    wait_dock_label(a, "1")
    doll.wait_badge(a, "1")
    restart_dock()
    wait_until(lambda: dock_item(a))
    set_badge(a, "2")
    wait_dock_label(a, "2")
    doll.wait_badge(a, "2")


@scenario("Badges keep working after the monitored app relaunches")
def app_relaunch(doll, a, screenshots):
    set_badge(a, "7")
    wait_dock_label(a, "7")
    doll.wait_badge(a, "7")
    quit_fixture(a)
    doll.wait_badge(a, "")
    set_badge(a, "8")
    launch_fixture(a)
    wait_dock_label(a, "8")
    doll.wait_badge(a, "8")


def assert_no_redraw(doll, fixture, badge):
    set_badge(fixture, badge)
    wait_dock_label(fixture, badge)
    doll.wait_badge(fixture, badge)
    time.sleep(2)
    before = doll.app(fixture)["redrawCount"]
    time.sleep(STABLE_WINDOW)
    after = doll.app(fixture)["redrawCount"]
    if after != before:
        raise CheckFailed(f"{after - before} redraws in {STABLE_WINDOW:.0f} s with no badge change")


@scenario("No redraw while the badge stays empty", known_issue=6)
def no_redraw_empty(doll, a, screenshots):
    assert_no_redraw(doll, a, "")


@scenario("No redraw while a red badge stays the same", known_issue=6, red_badge=True)
def no_redraw_red_badge(doll, a, screenshots):
    assert_no_redraw(doll, a, "3")



def reset_fixtures(fixtures):
    for fixture in FIXTURES.values():
        if fixture_pids(fixture):
            quit_fixture(fixture)
        fixture.control_file.parent.mkdir(parents=True, exist_ok=True)
        set_badge(fixture, "")
    for fixture in fixtures:
        launch_fixture(fixture)


def run_scenario(s: Scenario, screenshots: bool) -> str:
    try:
        reset_fixtures(s.fixtures)
        with DollPlus(s.name, s.fixtures, s.red_badge) as doll:
            s.body(doll, *s.fixtures, screenshots)
        detail = ""
        outcome = "XPASS" if s.known_issue else "PASS"
    except CheckFailed as error:
        detail = str(error)
        outcome = "XFAIL" if s.known_issue else "FAIL"
    except EnvironmentProblem as error:
        detail = str(error)
        outcome = "ERROR"
    issue = f" (#{s.known_issue})" if s.known_issue else ""
    print(f"{outcome:5}  {s.name}{issue}")
    if detail:
        print(f"    {detail}")
    if outcome == "XPASS":
        print(f"    This scenario passes now. Remove known_issue={s.known_issue} if #{s.known_issue} is fixed.")
    return outcome


def command_run(names, screenshots):
    selected = [s for s in SCENARIOS if not names or s.name in names]
    unknown = set(names) - {s.name for s in SCENARIOS}
    if unknown:
        sys.exit(f"unknown scenario: {', '.join(sorted(unknown))}")
    try:
        require_trusted()
    except EnvironmentProblem as error:
        sys.exit(f"ERROR  {error}")
    outcomes = [run_scenario(s, screenshots) for s in selected]
    for fixture in FIXTURES.values():
        if fixture_pids(fixture):
            quit_fixture(fixture)
    counts = {o: outcomes.count(o) for o in ("PASS", "FAIL", "XFAIL", "XPASS", "ERROR") if outcomes.count(o)}
    print("\n" + ", ".join(f"{n} {o}" for o, n in counts.items()))
    return 1 if {"FAIL", "XPASS", "ERROR"} & set(outcomes) else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    build = sub.add_parser("build")
    build.add_argument("--skip-app", action="store_true", help="build only the fixtures and the probe")
    p = sub.add_parser("probe")
    p.add_argument("--prompt", action="store_true", help="ask macOS to show the Accessibility prompt")
    r = sub.add_parser("run")
    r.add_argument("names", nargs="*")
    r.add_argument("--screenshots", action="store_true")
    sub.add_parser("list")
    args = parser.parse_args()

    if args.command == "build":
        build_all(args.skip_app)
    elif args.command == "probe":
        if not PROBE.exists():
            build_probe()
        print(json.dumps(probe(args.prompt), indent=2))
    elif args.command == "list":
        for s in SCENARIOS:
            issue = f"  [known issue #{s.known_issue}]" if s.known_issue else ""
            print(f"{s.name:22} {s.summary}{issue}")
    elif args.command == "run":
        sys.exit(command_run(args.names, args.screenshots))


if __name__ == "__main__":
    main()
