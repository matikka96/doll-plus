#!/usr/bin/env python3
"""End-to-end scenarios for Doll Plus.

    python3 -I scripts/e2e.py build             build Doll Plus, the fixtures, the Dock probe, the config driver and
                                                the UI driver
    python3 -I scripts/e2e.py probe [--prompt]  print the Dock items as JSON
    python3 -I scripts/e2e.py run [NAME ...]    run all or the named scenarios
    python3 -I scripts/e2e.py run --quiet       skip the scenarios that take the window focus, and fail a
                                                scenario that activates Doll Plus or a fixture
    python3 -I scripts/e2e.py list              list the scenarios
    python3 -I scripts/e2e.py demo [--app PATH] cycle a fixture badge for a manual check

The process that runs this script needs the Accessibility permission. Doll Plus
runs as a child process, so macOS checks the permission of the terminal.
"""

import argparse
import fcntl
import json
import os
import plistlib
import shutil
import signal
import subprocess
import sys
import time
from contextlib import contextmanager, suppress
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
E2E = BUILD / "e2e"
DERIVED_DATA = BUILD / "DerivedData"
BUILT_APP = DERIVED_DATA / "Build/Products/Debug/Doll Plus.app"
# Its own bundle ID gives the copy its own UserDefaults domain, apart from the stored settings of the user.
APP = E2E / "Doll Plus.app"
APP_BUNDLE_ID = "com.matikka96.DollPlus.e2e"
APP_BINARY = APP / "Contents/MacOS/Doll Plus"
PROBE = E2E / "dock-probe"
CONFIG_DRIVER = E2E / "config-driver"
UI_DRIVER = E2E / "ui-driver"
STATE_FILE = E2E / "state.json"
LOGS = E2E / "logs"
SCREENSHOTS = E2E / "screenshots"
# `open` makes each ad-hoc signed fixture build its own TCC responsible process,
# so a control file in ~/Documents causes a prompt for each build.
CONTROL_DIR = Path.home() / "Library/Caches/com.matikka96.DollPlus.e2e/control"
# Each scenario starts with a centered config window, not the frame that the last scenario moved.
# The name after "NSWindow Frame " is configWindowFrameName in MonitorEngine.swift.
CONFIG_WINDOW_FRAME_KEY = "NSWindow Frame DollPlusConfigWindow"
LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

POLL = 0.25
TIMEOUT = 8.0
STABLE_WINDOW = 5.0
RENDER_SETTLE = 1.0
# Points from the right end of the menu bar. A new status item goes to the left end.
SEEDED_POSITION = 120
CONFIG_WINDOW_OFFSET = (60, 40)
DEMO_BADGES = ("", "1", "12", "123", "new")
DEMO_STEP = 3.0
# NSWindow.Level.popUpMenu, the level of the arrow panel and the alert panel.
PANEL_LAYER = 101
ARROW_SIZE = (1000, 800)
ALERT_DURATION = 3.0
CLICK_CLOSE_TIMEOUT = 1.0
ALERT_CLOSE_SLACK = 1.0
ALERT_CENTER_TOLERANCE = 2
HOVER_DURATION = 3.0
FULL_SCREEN_SETTLE = 1.5
TEXT_WINDOW_SIZE = (480, 160)
ARROW_CLICK_BELOW_ITEM = 150
# About 3 s at the key interval of the UI driver.
KEYS_ACROSS_ALERT = "abcdefghijklmnopqrstuvwxyz" * 4


@dataclass(frozen=True)
class Fixture:
    key: str
    bundle_id: str
    bundle_name: str
    folder_name: str
    display_name: str | None = None
    localized_display_name: str | None = None
    dock_icon: bool = True
    text_window: bool = False

    @property
    def app(self) -> Path:
        return E2E / "fixtures" / f"{self.folder_name}.app"

    @property
    def control_file(self) -> Path:
        return CONTROL_DIR / f"{self.bundle_id}.badge"

    @property
    def report_file(self) -> Path:
        return CONTROL_DIR / f"{self.bundle_id}.report.json"

    @property
    def dock_title(self) -> str:
        return self.localized_display_name or self.display_name or self.bundle_name

    @property
    def autosave_name(self) -> str:
        return f"DollPlus_{self.bundle_id}"

    @property
    def position_key(self) -> str:
        return f"NSStatusItem Preferred Position {self.autosave_name}"

    @property
    def status_item_keys(self) -> list[str]:
        return [self.position_key, f"NSStatusItem VisibleCC {self.autosave_name}", f"DollPlus_SavedPosition_{self.bundle_id}"]


FIXTURES = {
    "a": Fixture("a", "com.matikka96.DollPlus.fixture.a", "DollFixtureA", "DollFixtureA"),
    # Copies Outlook: the Dock shows the display name, CFBundleName differs.
    "b": Fixture("b", "com.matikka96.DollPlus.fixture.b", "DollFixtureB", "Doll Fixture Display", "Doll Fixture Display"),
    "c": Fixture("c", "com.matikka96.DollPlus.fixture.c", "DollFixtureC", "DollFixtureC",
                 localized_display_name="Doll Fixture Localized"),
    "d": Fixture("d", "com.matikka96.DollPlus.fixture.d", "DollFixtureD", "DollFixtureD", dock_icon=False),
    # Takes the place of TextEdit: it keeps no document between runs.
    "text": Fixture("text", "com.matikka96.DollPlus.fixture.text", "DollFixtureText", "DollFixtureText", text_window=True),
}
TEXT = FIXTURES["text"]
SUITE_BUNDLE_IDS = {APP_BUNDLE_ID, *(f.bundle_id for f in FIXTURES.values())}


class CheckFailed(Exception):
    pass


class EnvironmentProblem(Exception):
    pass


class ScenarioSkipped(Exception):
    pass


# Quartz global coordinates: the origin is the top-left corner of the main display, and y grows down.
@dataclass(frozen=True)
class Rect:
    x: float
    y: float
    width: float
    height: float

    @classmethod
    def of(cls, bounds: dict) -> "Rect":
        return cls(bounds["x"], bounds["y"], bounds["width"], bounds["height"])

    @property
    def max_x(self) -> float:
        return self.x + self.width

    @property
    def max_y(self) -> float:
        return self.y + self.height

    @property
    def center(self) -> tuple[float, float]:
        return self.x + self.width / 2, self.y + self.height / 2

    def contains(self, point) -> bool:
        return self.x <= point[0] <= self.max_x and self.y <= point[1] <= self.max_y

    def contains_rect(self, other: "Rect") -> bool:
        return self.x <= other.x and other.max_x <= self.max_x and self.y <= other.y and other.max_y <= self.max_y


@contextmanager
def as_environment_problem(prefix: str = ""):
    try:
        yield
    except CheckFailed as error:
        raise EnvironmentProblem(f"{prefix}{error}")


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, **kwargs)


def wait_until(condition, timeout=TIMEOUT, describe=lambda: "", what=None):
    deadline = time.monotonic() + timeout
    while True:
        result = condition()
        if result:
            return result
        if time.monotonic() > deadline:
            detail = describe()
            message = f"timed out after {timeout:.0f} s" + (f". {detail}" if detail else "")
            raise CheckFailed(f"{what}: {message}" if what else message)
        time.sleep(POLL)



def build_app():
    run(["xcodebuild", "-project", str(ROOT / "DollPlus.xcodeproj"), "-scheme", "DollPlus",
         "-configuration", "Debug", "-destination", f"platform=macOS,arch={os.uname().machine}", "-derivedDataPath", str(DERIVED_DATA), "-quiet", "build"])
    shutil.rmtree(APP, ignore_errors=True)
    shutil.copytree(BUILT_APP, APP, symlinks=True)
    info_plist = APP / "Contents/Info.plist"
    with open(info_plist, "rb") as f:
        info = plistlib.load(f)
    info["CFBundleIdentifier"] = APP_BUNDLE_ID
    with open(info_plist, "wb") as f:
        plistlib.dump(info, f)
    run(["codesign", "--force", "--deep", "--sign", "-", str(APP)], stderr=subprocess.DEVNULL)


def build_fixture(fixture: Fixture):
    contents = fixture.app / "Contents"
    (contents / "MacOS").mkdir(parents=True, exist_ok=True)
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
    if not fixture.dock_icon:
        info["LSUIElement"] = True
    if fixture.text_window:
        info["DollFixtureReportFile"] = str(fixture.report_file)
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


def build_helpers():
    E2E.mkdir(parents=True, exist_ok=True)
    run(["swiftc", "-O", "-o", str(PROBE), str(ROOT / "scripts/e2e/DockProbe.swift")])
    run(["swiftc", "-O", "-o", str(CONFIG_DRIVER), str(ROOT / "scripts/e2e/ConfigDriver.swift")])
    run(["swiftc", "-O", "-o", str(UI_DRIVER), str(ROOT / "scripts/e2e/UIDriver.swift")])


def build_all(skip_app=False):
    if not skip_app:
        build_app()
    build_helpers()
    for fixture in FIXTURES.values():
        build_fixture(fixture)



def probe(*args):
    result = subprocess.run([str(PROBE), *args], capture_output=True, text=True)
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


def app_state(bundle_id: str):
    return probe("--app-state", bundle_id)


def wait_app_state(fixture: Fixture, condition, what: str):
    try:
        wait_until(lambda: condition(app_state(fixture.bundle_id)), describe=lambda: f"Last state: {app_state(fixture.bundle_id)}")
    except CheckFailed as error:
        raise CheckFailed(f"{fixture.dock_title} did not become {what}: {error}")


def deactivate_fixture(fixture: Fixture):
    # A late activation of the other fixture can undo the next click.
    if not app_state(fixture.bundle_id)["active"]:
        return
    # NSRunningApplication.hide() refuses an accessory app, so another fixture takes the activation.
    other = next(f for f in FIXTURES.values() if f != fixture and f.dock_icon)
    run(["open", str(other.app)])
    with as_environment_problem():
        wait_app_state(fixture, lambda s: not s["active"], "inactive")


def fixture_pids(fixture: Fixture):
    result = subprocess.run(["pgrep", "-x", fixture.bundle_name], capture_output=True, text=True)
    return [int(pid) for pid in result.stdout.split()]


def doll_plus_pids():
    result = subprocess.run(["pgrep", "-x", "Doll Plus"], capture_output=True, text=True)
    return [int(pid) for pid in result.stdout.split()]


def launch_fixture(fixture: Fixture):
    run(["open", "-g", str(fixture.app)])
    try:
        wait_until(lambda: dock_item(fixture) if fixture.dock_icon else fixture_pids(fixture))
    except CheckFailed:
        raise EnvironmentProblem(f"{fixture.dock_title} did not appear in the Dock" if fixture.dock_icon
                                 else f"{fixture.dock_title} did not start")


def quit_fixture(fixture: Fixture):
    for pid in fixture_pids(fixture):
        os.kill(pid, signal.SIGTERM)
    wait_until(lambda: not fixture_pids(fixture) and dock_item(fixture) is None)


def frontmost_app():
    return probe("--frontmost")


@contextmanager
def activation_watch():
    watcher = subprocess.Popen([str(PROBE), "--watch-activations"], stdout=subprocess.PIPE, text=True)
    # The first line comes after the watcher subscribes to the activations.
    watcher.stdout.readline()
    activations = []
    try:
        yield activations
    finally:
        watcher.terminate()
        activations.extend(json.loads(line) for line in watcher.communicate()[0].splitlines())


def ui(*args):
    result = subprocess.run([str(UI_DRIVER), *map(str, args)], capture_output=True, text=True)
    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise EnvironmentProblem(f"the UI driver printed no JSON: {result.stdout}{result.stderr}")
    if result.returncode != 0:
        raise EnvironmentProblem(f"UI driver: {output.get('error')}")
    return output


def windows_of(pid: int) -> list[dict]:
    return [{**w, "bounds": Rect.of(w["bounds"])} for w in ui("windows") if w["pid"] == pid and w["alpha"] > 0]


def screens() -> list[Rect]:
    return [Rect.of(bounds) for bounds in ui("screens")]


def screen_of(rect: Rect) -> Rect:
    screen = next((s for s in screens() if s.contains(rect.center)), None)
    if screen is None:
        raise EnvironmentProblem(f"{rect} is on no screen {screens()}")
    return screen


def move_pointer(point):
    ui("move", *point)


def click(point):
    ui("click", *point)


def static_texts_at(point) -> list[str]:
    return ui("texts-at", *point)


def window_state(pid: int) -> dict:
    return ui("window", pid)


def place_text_window(center):
    width, height = TEXT_WINDOW_SIZE
    ui("place", fixture_pids(TEXT)[0], center[0] - width / 2, center[1] - height / 2, width, height)


def text_report():
    try:
        return json.loads(TEXT.report_file.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def activate_text_fixture():
    run(["open", str(TEXT.app)])
    with as_environment_problem():
        wait_app_state(TEXT, lambda s: s["active"], "active")


def start_text_fixture():
    TEXT.report_file.unlink(missing_ok=True)
    launch_fixture(TEXT)
    with as_environment_problem():
        wait_until(text_report, what=f"{TEXT.dock_title} wrote no report")
    activate_text_fixture()


def leave_full_screen(fixture: Fixture, pid: int):
    ui("fullscreen", pid, "off")
    with as_environment_problem(f"{fixture.dock_title} did not leave full screen: "):
        wait_until(lambda: not window_state(pid)["fullScreen"])
    time.sleep(FULL_SCREEN_SETTLE)


@contextmanager
def full_screen(fixture: Fixture):
    pid = fixture_pids(fixture)[0]
    ui("fullscreen", pid, "on")
    try:
        with as_environment_problem(f"{fixture.dock_title} did not go full screen: "):
            window = wait_until(lambda: (w := window_state(pid))["fullScreen"] and Rect.of(w["bounds"]) in screens() and w,
                                describe=lambda: f"window: {window_state(pid)}")
        time.sleep(FULL_SCREEN_SETTLE)
        bounds = Rect.of(window["bounds"])
        # Doll Plus checks the full screen on the screen with the pointer.
        move_pointer(bounds.center)
        yield bounds
    except BaseException:
        # A failure to leave full screen must not hide the failure of the scenario.
        with suppress(CheckFailed, EnvironmentProblem):
            leave_full_screen(fixture, pid)
        raise
    leave_full_screen(fixture, pid)


def restart_dock():
    old_pid = probe().get("dockPid")
    run(["killall", "Dock"])
    try:
        wait_until(lambda: (p := probe()).get("dockPid") not in (None, old_pid) and p.get("items"), timeout=15)
    except CheckFailed:
        raise EnvironmentProblem("the Dock did not restart")



class DollPlus:
    def __init__(self, scenario: str, fixtures, red_badge: bool, hide_when_empty: bool = False, alerts: bool = False,
                 binary: Path = APP_BINARY):
        self.scenario = scenario
        self.fixtures = fixtures
        self.red_badge = red_badge
        self.hide_when_empty = hide_when_empty
        self.alerts = alerts
        self.binary = binary
        self.process = None

    def __enter__(self):
        subprocess.run(["defaults", "delete", APP_BUNDLE_ID, CONFIG_WINDOW_FRAME_KEY], capture_output=True)
        self.start()
        return self

    def __exit__(self, *exc):
        self.stop()

    def start(self):
        if doll_plus_pids():
            raise EnvironmentProblem("another Doll Plus process runs. Quit it first")
        if not self.binary.is_file():
            raise EnvironmentProblem(f"{self.binary} does not exist. Run python3 -I scripts/e2e.py build in its worktree")
        STATE_FILE.unlink(missing_ok=True)
        LOGS.mkdir(parents=True, exist_ok=True)
        log = open(LOGS / f"{self.scenario}.log", "w")
        settings = {
            "SETTING_MONITORED_APP_IDS": ",".join(f.bundle_id for f in self.fixtures),
            "SETTINGS_Show_As_Red_Badge": plist_bool(self.red_badge),
            "SETTINGS_Show_Only_App_Icon": plist_bool(False),
            "SETTINGS_Hide_When_App_Not_Running": plist_bool(False),
            "SETTINGS_Hide_When_Nothing_Coming": plist_bool(self.hide_when_empty),
            "SETTINGS_Grayout_Icon_When_Nothing_Coming": plist_bool(False),
            "SETTINGS_SHOW_ALERT_IN_FULL_SCREEN_Mode": plist_bool(self.alerts),
            "SETTINGS_Giant_Badge_Enabled_Apps": "<dict>" + "".join(
                f"<key>{f.bundle_id}</key><true/>" for f in (self.fixtures if self.alerts else ())) + "</dict>",
            "SETTINGS_APPS_ICON_MASK": "<dict/>",
            "ApplePersistenceIgnoreState": "YES",
            "DollPlusStateFile": str(STATE_FILE),
        }
        args = [str(self.binary)] + [token for key, value in settings.items() for token in (f"-{key}", value)]
        self.process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT)
        try:
            wait_until(lambda: len(self.state().get("apps", [])) == len(set(self.fixtures)),
                       describe=lambda: f"state: {self.state()}")
        except BaseException:
            self.stop()
            raise

    def stop(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()

    def relaunch(self):
        self.stop()
        self.start()

    def state(self):
        if self.process and self.process.poll() is not None:
            raise CheckFailed(f"Doll Plus exited with code {self.process.returncode}")
        try:
            return json.loads(STATE_FILE.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

    def _config(self, *args):
        result = subprocess.run([str(CONFIG_DRIVER), str(self.process.pid), *args], capture_output=True, text=True)
        try:
            output = json.loads(result.stdout)
        except json.JSONDecodeError:
            raise CheckFailed(f"the config driver printed no JSON: {result.stdout}{result.stderr}")
        if result.returncode != 0:
            raise CheckFailed(f"config window: {output.get('error')}")
        return output

    def config_rows(self):
        return self._config("rows")

    def config_buttons(self):
        return self._config("buttons")

    def open_row(self, name: str):
        self._config("open", name)

    def toggle_setting(self, label: str):
        self._config("toggle", label)

    def remove_row(self, name: str):
        self._config("remove", name)

    def config_frame(self):
        return self._config("frame")["frame"]

    def show_config_window(self):
        return self._config("show")["frame"]

    def move_config_window(self):
        return self._config("move", *map(str, CONFIG_WINDOW_OFFSET))["frame"]

    def close_config_window(self):
        self._config("close")

    def activate(self):
        self._config("activate")

    def wait_inactive(self):
        wait_until(lambda: not app_state(APP_BUNDLE_ID)["active"], describe=lambda: f"Last state: {app_state(APP_BUNDLE_ID)}",
                   what="Doll Plus did not become inactive")

    def app(self, fixture: Fixture):
        apps = self.state().get("apps", [])
        return next((a for a in apps if a["bundleId"] == fixture.bundle_id), None)

    def wait_app(self, fixture: Fixture, condition, what: str, timeout=TIMEOUT):
        return wait_until(lambda: (a := self.app(fixture)) is not None and condition(a) and a, timeout=timeout,
                          describe=lambda: f"Last state: {self.app(fixture)}", what=what)

    def wait_badge(self, fixture: Fixture, text: str, timeout=TIMEOUT):
        return self.wait_app(fixture, lambda a: a["badge"] == text,
                             f"Doll Plus did not show the badge {text!r}", timeout)

    def status_item(self, fixture: Fixture) -> Rect:
        x, y, width, height = self.app(fixture)["frame"]
        return Rect(x, self.state()["mainScreenHeight"] - (y + height), width, height)

    def windows(self) -> list[dict]:
        return windows_of(self.process.pid)

    def panels(self, is_arrow: bool) -> list[Rect]:
        return [w["bounds"] for w in self.windows()
                if w["layer"] == PANEL_LAYER and ((w["bounds"].width, w["bounds"].height) == ARROW_SIZE) == is_arrow]

    def arrow(self) -> Rect | None:
        return next(iter(self.panels(is_arrow=True)), None)

    def alert(self) -> Rect | None:
        return next(iter(self.panels(is_arrow=False)), None)

    # A tooltip is a window of its own. The window list of macOS 26 has no status item windows.
    def windows_besides_panels(self) -> list[dict]:
        return [w for w in self.windows() if w["layer"] != PANEL_LAYER]

    def describe_alert(self) -> str:
        panel = self.alert()
        return f"alert: {panel} with the texts {static_texts_at(panel.center)}" if panel else "no alert shows"

    def wait_alert(self, text: str) -> Rect:
        def shown():
            panel = self.alert()
            return panel if panel and static_texts_at(panel.center) == [text] else None
        return wait_until(shown, describe=self.describe_alert, what=f"the alert with {text!r} did not show")

    def wait_no_alert(self, timeout: float, what: str):
        wait_until(lambda: self.alert() is None, timeout=timeout, describe=self.describe_alert, what=what)

    def click_status_item(self):
        if not probe("--press-status-item", str(self.state()["pid"])).get("pressed"):
            raise CheckFailed("the Accessibility press on the status item failed")

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
    hide_when_empty: bool = False
    steals_focus: bool = False
    alerts: bool = False


SCENARIOS: list[Scenario] = []


def scenario(summary, fixtures=("a",), known_issue=None, red_badge=False, hide_when_empty=False, steals_focus=False,
             alerts=False):
    def register(body):
        SCENARIOS.append(Scenario(body.__name__.replace("_", "-"), summary, tuple(FIXTURES[k] for k in fixtures), body,
                                  known_issue, red_badge, hide_when_empty, steals_focus, alerts))
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


@scenario("The status item grows with the badge: 1, 12, 123")
def badge_growth(doll, a, screenshots):
    for badge in ("1", "12", "123"):
        set_badge(a, badge)
        wait_dock_label(a, badge)
        app = doll.wait_badge(a, badge)
        if screenshots:
            doll.screenshot(a, f"badge-{badge}")
        if app["neededWidth"] > app["width"] + 0.5:
            raise CheckFailed(f"the badge {badge!r} needs {app['neededWidth']:.1f} pt, the button has {app['width']:.1f} pt")


@scenario("A red badge shows 99+ above 99 and a dot for a text that does not fit", red_badge=True)
def red_badge_overflow(doll, a, screenshots):
    images = {}
    for badge, label in (("99", "99"), ("123", "99+"), ("new", "new"), ("hello", "•")):
        set_badge(a, badge)
        wait_dock_label(a, badge)
        app = doll.wait_badge(a, badge)
        if screenshots:
            doll.screenshot(a, f"red-badge-{badge}")
        if app.get("redBadgeLabel") != label:
            raise CheckFailed(f"the red badge {badge!r} shows {app.get('redBadgeLabel')!r}, expected {label!r}")
        images[badge] = app.get("imageDigest")
    if len(set(images.values())) != len(images):
        raise CheckFailed(f"two red badges give the same status item image: {images}")


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


@scenario("Badges keep working after the Dock restarts", steals_focus=True)
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


@scenario("A click shows the app, a second click hides it", steals_focus=True)
def click_toggle(doll, a, screenshots):
    deactivate_fixture(a)
    doll.click_status_item()
    wait_app_state(a, lambda s: s["active"] and not s["hidden"], "active")
    doll.click_status_item()
    wait_app_state(a, lambda s: s["hidden"], "hidden")


@scenario("A click shows an app with no Dock icon, a second click hides it", fixtures=("d",), steals_focus=True)
def click_toggle_no_dock_icon(doll, d, screenshots):
    deactivate_fixture(d)
    doll.click_status_item()
    wait_app_state(d, lambda s: s["active"], "active")
    doll.click_status_item()
    # isHidden stays false for an accessory app, so the window shows the hide.
    wait_app_state(d, lambda s: not s["active"] and s["on_screen_windows"] == 0, "inactive and hidden")


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


@scenario("No redraw while the badge stays empty")
def no_redraw_empty(doll, a, screenshots):
    assert_no_redraw(doll, a, "")


@scenario("No redraw while a red badge stays the same", red_badge=True)
def no_redraw_red_badge(doll, a, screenshots):
    assert_no_redraw(doll, a, "3")


def selected_rows(doll):
    return [r["name"] for r in doll.config_rows() if r["selected"]]


def assert_selected_rows(doll, names):
    wait_until(lambda: selected_rows(doll) == names,
               describe=lambda: f"rows: {doll.config_rows()}", what=f"the selected rows are not {names}")


def assert_selection_holds(doll, names):
    deadline = time.monotonic() + RENDER_SETTLE
    while time.monotonic() < deadline:
        if (rows := selected_rows(doll)) != names:
            raise CheckFailed(f"the selected rows changed from {names} to {rows}")
        time.sleep(POLL)


@scenario("A config row stays selected after a setting changes", fixtures=("a", "b"), steals_focus=True)
def row_keeps_selection(doll, a, b, screenshots):
    doll.open_row(a.dock_title)
    assert_selected_rows(doll, [a.dock_title])
    doll.toggle_setting("Hide icon if monitored app isn't running")
    assert_selection_holds(doll, [a.dock_title])


@scenario("The Remove item of a config row stops monitoring the app", fixtures=("a", "b"), steals_focus=True)
def remove_from_list(doll, a, b, screenshots):
    doll.remove_row(b.dock_title)
    wait_until(lambda: [app["bundleId"] for app in doll.state().get("apps", [])] == [a.bundle_id],
               describe=lambda: f"state: {doll.state().get('apps')}", what=f"Doll Plus still monitors {b.dock_title}")
    rows = [r["name"] for r in doll.config_rows()]
    if rows != [a.dock_title]:
        raise CheckFailed(f"the config list shows {rows}, expected {[a.dock_title]}")


def detail_pane_open(doll, fixture):
    return f'Stop monitoring - "{fixture.dock_title}"' in doll.config_buttons()


@scenario("Removing the open config row closes its detail pane", fixtures=("a", "b"), steals_focus=True)
def remove_open_row(doll, a, b, screenshots):
    doll.open_row(b.dock_title)
    wait_until(lambda: detail_pane_open(doll, b), describe=lambda: f"rows: {doll.config_rows()}, buttons: {doll.config_buttons()}",
               what=f"the detail pane of {b.dock_title} did not open")
    doll.remove_row(b.dock_title)
    wait_until(lambda: not detail_pane_open(doll, b), describe=lambda: f"buttons: {doll.config_buttons()}",
               what=f"the detail pane of the removed row {b.dock_title} stays open")


@scenario("A bundle ID saved twice gives one config row", fixtures=("a", "a"), steals_focus=True)
def duplicate_saved_app(doll, a, _, screenshots):
    rows = [r["name"] for r in doll.config_rows()]
    if rows != [a.dock_title]:
        raise CheckFailed(f"the config list shows {rows}, expected {[a.dock_title]}")


def assert_config_frame(doll, expected, after: str):
    if (frame := doll.config_frame()) != expected:
        raise CheckFailed(f"the config window frame changed from {expected} to {frame} after {after}")


@scenario("The config window keeps its frame and selected row when Doll Plus becomes active again",
          fixtures=("a", "b"), steals_focus=True)
def config_keeps_state(doll, a, b, screenshots):
    doll.open_row(a.dock_title)
    assert_selected_rows(doll, [a.dock_title])
    moved = doll.move_config_window()
    run(["open", str(b.app)])
    wait_app_state(b, lambda s: s["active"], "active")
    doll.wait_inactive()
    doll.activate()
    assert_selection_holds(doll, [a.dock_title])
    assert_config_frame(doll, moved, "an activation")


# A launch from Finder or Spotlight activates Doll Plus. An `open` from a script does not.
@scenario("The first activation of Doll Plus shows the config window", steals_focus=True)
def first_activation_shows_config(doll, a, screenshots):
    doll.activate()
    wait_until(doll.config_frame, what="the config window did not show after the first activation")


@scenario("A second open of Doll Plus shows the closed config window at its last frame, also after a relaunch", steals_focus=True)
def reopen_shows_config(doll, a, screenshots):
    moved = doll.move_config_window()
    doll.close_config_window()
    run(["open", str(APP)])
    wait_until(doll.config_frame, what="the config window did not show after a second open")
    if (pids := doll_plus_pids()) != [doll.process.pid]:
        raise CheckFailed(f"the second open started another Doll Plus: {pids}")
    assert_config_frame(doll, moved, "a close and a second open")
    doll.relaunch()
    if (frame := doll.show_config_window()) != moved:
        raise CheckFailed(f"the config window frame changed from {moved} to {frame} after a relaunch")


def stored_default(key: str):
    result = subprocess.run(["defaults", "read", APP_BUNDLE_ID, key], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def delete_status_item_keys(fixture: Fixture):
    for key in fixture.status_item_keys:
        subprocess.run(["defaults", "delete", APP_BUNDLE_ID, key], capture_output=True)


def settled_status_item(doll, fixture: Fixture) -> Rect:
    previous = None

    def settled():
        nonlocal previous
        item = doll.status_item(fixture)
        settled_item = item if item == previous else None
        previous = item
        return settled_item

    # The menu bar moves a status item with an animation after a show.
    time.sleep(RENDER_SETTLE)
    return wait_until(settled, describe=lambda: f"the status item frame changes: {doll.app(fixture)}")


def show_status_item_x(doll, fixture: Fixture) -> float:
    set_badge(fixture, "1")
    wait_dock_label(fixture, "1")
    doll.wait_app(fixture, lambda a: a["visible"] and a["badge"] == "1", "the status item did not show")
    return settled_status_item(doll, fixture).x


def hide_status_item(doll, fixture: Fixture):
    set_badge(fixture, "")
    wait_dock_label(fixture, "")
    doll.wait_app(fixture, lambda a: not a["visible"], "the status item did not hide")


# A launch argument cannot seed the position: the argument domain hides the removal of the stored key.
@scenario("A status item keeps its menu bar position when it hides and shows", hide_when_empty=True)
def hide_keeps_position(doll, a, screenshots):
    try:
        delete_status_item_keys(a)
        run(["defaults", "write", APP_BUNDLE_ID, a.position_key, "-float", str(SEEDED_POSITION)])
        doll.relaunch()
        seeded_x = show_status_item_x(doll, a)
        hide_status_item(doll, a)
        if (x := show_status_item_x(doll, a)) != seeded_x:
            raise CheckFailed(f"the status item moved from x {seeded_x:.0f} to x {x:.0f} after a hide and a show")
        hide_status_item(doll, a)
        doll.relaunch()
        if (x := show_status_item_x(doll, a)) != seeded_x:
            raise CheckFailed(f"the status item moved from x {seeded_x:.0f} to x {x:.0f} after a hide and a relaunch")
        if stored_default(a.position_key) is None:
            raise CheckFailed(f"the stored settings have no {a.position_key!r}")
    finally:
        doll.stop()
        delete_status_item_keys(a)


def assert_no_tooltip(doll, when: str):
    if windows := doll.windows_besides_panels():
        raise CheckFailed(f"a tooltip or another window of Doll Plus shows {when}: {windows}")


@scenario("No tooltip shows on the status item, and none stays after the giant arrow shows", alerts=True,
          steals_focus=True)
def no_tooltip(doll, a, screenshots):
    start_text_fixture()
    item = doll.status_item(a)
    # Doll Plus places the arrow on the screen with the pointer (#49).
    away = screen_of(item).center
    move_pointer(item.center)
    time.sleep(HOVER_DURATION)
    assert_no_tooltip(doll, "while the pointer stays on the status item")
    move_pointer(away)
    set_badge(a, "3")
    doll.wait_badge(a, "3")
    wait_until(doll.arrow, what="the giant arrow did not show")
    move_pointer(doll.status_item(a).center)
    time.sleep(HOVER_DURATION)
    assert_no_tooltip(doll, "while the pointer stays on the status item under the giant arrow")
    move_pointer(away)
    time.sleep(RENDER_SETTLE)
    assert_no_tooltip(doll, "after the pointer leaves the status item")


@scenario("While the arrow shows, the status item takes a click, and the window below the arrow takes a click",
          alerts=True, steals_focus=True)
def arrow_click_through(doll, a, screenshots):
    start_text_fixture()
    # Doll Plus places the arrow on the screen with the pointer (#49).
    move_pointer(screen_of(settled_status_item(doll, a)).center)
    set_badge(a, "3")
    doll.wait_badge(a, "3")
    arrow = wait_until(doll.arrow, what="the giant arrow did not show")
    item = settled_status_item(doll, a)
    covered_top = max(item.y, arrow.y)
    if covered_top >= item.max_y:
        raise EnvironmentProblem(f"the arrow {arrow} does not cover the status item {item}")
    click((item.center[0], (covered_top + item.max_y) / 2))
    wait_app_state(a, lambda s: s["active"], "active after a click on the status item under the arrow")

    activate_text_fixture()
    set_badge(a, "")
    doll.wait_badge(a, "")
    wait_until(lambda: doll.arrow() is None, what="the giant arrow did not hide after the badge cleared")
    item = settled_status_item(doll, a)
    target = (item.center[0], item.max_y + ARROW_CLICK_BELOW_ITEM)
    place_text_window(target)
    set_badge(a, "4")
    doll.wait_badge(a, "4")
    arrow = wait_until(doll.arrow, what="the giant arrow did not show")
    if not arrow.contains(target):
        raise EnvironmentProblem(f"the arrow {arrow} does not cover the click point {target}")
    clicks = text_report()["clicks"]
    click(target)
    wait_until(lambda: text_report()["clicks"] > clicks, describe=lambda: f"report: {text_report()}",
               what=f"the click on the arrow did not reach the {TEXT.dock_title} window below it")


def assert_alert_below_item(doll, fixture: Fixture, panel: Rect):
    item = doll.status_item(fixture)
    screen = next((s for s in screens() if s.contains(panel.center)), None)
    if screen is None:
        raise CheckFailed(f"the alert {panel} is on no screen")
    # Doll Plus keeps the alert on the screen when a full-screen space hides the menu bar.
    top = max(item.max_y, screen.y)
    clamped = panel.x <= screen.x or panel.max_x >= screen.max_x
    centered = abs(panel.center[0] - item.center[0]) <= ALERT_CENTER_TOLERANCE
    if abs(panel.y - top) > 1 or not (centered or (clamped and panel.x <= item.center[0] <= panel.max_x)):
        raise CheckFailed(f"the alert {panel} is not below the status item {item}")


def assert_alert_keeps_focus(doll, a, badge: str) -> Rect:
    with activation_watch() as activations:
        typist = subprocess.Popen([str(UI_DRIVER), "type", KEYS_ACROSS_ALERT], stdout=subprocess.DEVNULL)
        try:
            set_badge(a, badge)
            panel = doll.wait_alert(badge)
            typed_across_alert = typist.poll() is None
        finally:
            typist.wait()
    if not typed_across_alert:
        raise EnvironmentProblem("the typed keys ended before the alert showed, so the focus check is not complete")
    wait_until(lambda: text_report()["text"] == KEYS_ACROSS_ALERT, describe=lambda: f"report: {text_report()}",
               what=f"the {TEXT.dock_title} text field did not get all of the typed keys")
    if activations:
        raise CheckFailed(f"the alert changed the active app: {activations}")
    if (frontmost := frontmost_app())["bundleId"] != TEXT.bundle_id:
        raise CheckFailed(f"the frontmost app is {frontmost['name']}, not {TEXT.dock_title}")
    return panel


@scenario("In full screen, the alert shows the badge below the status item, and the typed keys stay in the active app",
          alerts=True, steals_focus=True)
def alert_keeps_focus(doll, a, screenshots):
    # The status item gets its text width before the alert, so the alert position does not depend on #45.
    set_badge(a, "4")
    doll.wait_badge(a, "4")
    start_text_fixture()
    settled_status_item(doll, a)
    with full_screen(TEXT):
        panel = assert_alert_keeps_focus(doll, a, "5")
        assert_alert_below_item(doll, a, panel)


@scenario("A click on the alert closes it and activates the monitored app", alerts=True, steals_focus=True)
def alert_click(doll, a, screenshots):
    start_text_fixture()
    with full_screen(TEXT):
        set_badge(a, "6")
        panel = doll.wait_alert("6")
        click(panel.center)
        doll.wait_no_alert(CLICK_CLOSE_TIMEOUT, "the alert did not close after a click")
        wait_app_state(a, lambda s: s["active"], "active after a click on the alert")


@scenario("A second badge change updates the alert, and the alert closes 3 s after the last change", alerts=True,
          steals_focus=True)
def alert_update(doll, a, screenshots):
    start_text_fixture()
    with full_screen(TEXT):
        set_badge(a, "7")
        doll.wait_alert("7")
        time.sleep(ALERT_DURATION / 2)
        if doll.alert() is None:
            raise EnvironmentProblem("the alert of the first badge closed before the second badge change")
        set_badge(a, "8")
        doll.wait_alert("8")
        updated = time.monotonic()
        time.sleep(ALERT_DURATION * 2 / 3)
        if doll.alert() is None:
            raise CheckFailed(f"the alert closed less than {ALERT_DURATION:.0f} s after the last badge change")
        doll.wait_no_alert(updated + ALERT_DURATION + ALERT_CLOSE_SLACK - time.monotonic(),
                           f"the alert did not close {ALERT_DURATION:.0f} s after the last badge change")


@scenario("With two screens, the alert shows fully on one screen", alerts=True, steals_focus=True)
def alert_two_screens(doll, a, screenshots):
    all_screens = screens()
    second = next((s for s in all_screens if (s.x, s.y) != (0, 0)), None)
    if second is None:
        raise ScenarioSkipped("the Mac has one screen")
    start_text_fixture()
    place_text_window(second.center)
    with full_screen(TEXT) as window:
        if window != second:
            raise EnvironmentProblem(f"{TEXT.dock_title} went full screen on {window}, not on the second screen {second}")
        panel = assert_alert_keeps_focus(doll, a, "9")
    if not any(s.contains_rect(panel) for s in all_screens):
        raise CheckFailed(f"the alert {panel} is not fully on one of the screens {all_screens}")


@scenario("With hide when nothing is coming, the status item comes back and the alert shows below it",
          hide_when_empty=True, alerts=True, steals_focus=True, known_issue=45)
def alert_hidden_item(doll, a, screenshots):
    doll.wait_app(a, lambda app: not app["visible"], "the status item did not hide")
    start_text_fixture()
    with full_screen(TEXT):
        set_badge(a, "3")
        doll.wait_alert("3")
        doll.wait_app(a, lambda app: app["visible"], "the status item did not come back")
        settled_status_item(doll, a)
        if (panel := doll.alert()) is None:
            raise EnvironmentProblem("the alert closed before the status item stopped its move")
        assert_alert_below_item(doll, a, panel)


def reset_fixtures(fixtures):
    for fixture in FIXTURES.values():
        if fixture_pids(fixture):
            quit_fixture(fixture)
        fixture.control_file.parent.mkdir(parents=True, exist_ok=True)
        set_badge(fixture, "")
    for fixture in fixtures:
        launch_fixture(fixture)


def scenario_outcome(s: Scenario, screenshots: bool) -> tuple[str, str]:
    try:
        reset_fixtures(s.fixtures)
        with DollPlus(s.name, s.fixtures, s.red_badge, s.hide_when_empty, s.alerts) as doll:
            s.body(doll, *s.fixtures, screenshots)
        return ("XPASS" if s.known_issue else "PASS"), ""
    except ScenarioSkipped as reason:
        return "SKIP", str(reason)
    except CheckFailed as error:
        return ("XFAIL" if s.known_issue else "FAIL"), str(error)
    except EnvironmentProblem as error:
        return "ERROR", str(error)


def quiet_scenario_outcome(s: Scenario, screenshots: bool) -> tuple[str, str, str | None]:
    before = frontmost_app()
    with activation_watch() as activations:
        outcome, detail = scenario_outcome(s, screenshots)
    after = frontmost_app()
    if stolen := [a["name"] for a in activations if a["bundleId"] in SUITE_BUNDLE_IDS]:
        return "FAIL", "\n    ".join(filter(None, [f"the scenario activated {', '.join(stolen)}", detail])), None
    # The user works during a quiet run, so an app switch of the user gives only a note.
    if after["bundleId"] != before["bundleId"]:
        return outcome, detail, f"note: the frontmost app changed from {before['name']} to {after['name']}, with no activation of a suite app"
    return outcome, detail, None


def run_scenario(s: Scenario, screenshots: bool, quiet: bool) -> str:
    issue = f" (#{s.known_issue})" if s.known_issue else ""
    if quiet and s.steals_focus:
        print(f"SKIP   {s.name}{issue}\n    it takes the window focus. Run it without --quiet")
        return "SKIP"
    if quiet:
        outcome, detail, note = quiet_scenario_outcome(s, screenshots)
    else:
        (outcome, detail), note = scenario_outcome(s, screenshots), None
    print(f"{outcome:5}  {s.name}{issue}")
    for line in filter(None, [detail, note]):
        print(f"    {line}")
    if outcome == "XPASS":
        print(f"    This scenario passes now. Remove known_issue={s.known_issue} if #{s.known_issue} is fixed.")
    return outcome


def run_lock_path() -> Path:
    common_dir = run(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    return (ROOT / common_dir).resolve() / "doll-plus-e2e.lock"


@contextmanager
def dock_lock():
    # All worktrees share one Dock and one set of fixture bundle IDs.
    with open(run_lock_path(), "a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Another scenario run or demo uses the Dock. Waiting for it to finish.", flush=True)
            fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def command_run(names, screenshots, quiet):
    selected = [s for s in SCENARIOS if not names or s.name in names]
    unknown = set(names) - {s.name for s in SCENARIOS}
    if unknown:
        sys.exit(f"unknown scenario: {', '.join(sorted(unknown))}")
    with dock_lock():
        return run_selected(selected, screenshots, quiet)


def bundle_id_of(binary: Path):
    try:
        with open(binary.parents[1] / "Info.plist", "rb") as f:
            return plistlib.load(f).get("CFBundleIdentifier")
    except FileNotFoundError:
        return None


def command_demo(binary: Path, red_badge: bool, hide_when_empty: bool, cycles: int):
    if bundle_id_of(binary) != APP_BUNDLE_ID:
        sys.exit(f"ERROR  {binary} is not an e2e copy with the bundle ID {APP_BUNDLE_ID}. "
                 "Another copy changes the stored settings of the user")
    a = FIXTURES["a"]
    with dock_lock():
        try:
            require_trusted()
            reset_fixtures((a,))
            with DollPlus("demo", (a,), red_badge, hide_when_empty, binary=binary):
                print(f"Doll Plus shows {a.dock_title}. The badge changes every {DEMO_STEP:.0f} s. Press Ctrl-C to stop.", flush=True)
                for _ in range(cycles):
                    for badge in DEMO_BADGES:
                        print(f"badge {badge!r}", flush=True)
                        set_badge(a, badge)
                        time.sleep(DEMO_STEP)
        except KeyboardInterrupt:
            print("Stopped.")
        except (CheckFailed, EnvironmentProblem) as error:
            sys.exit(f"ERROR  {error}")
        finally:
            for pid in fixture_pids(a):
                os.kill(pid, signal.SIGTERM)


def run_selected(selected, screenshots, quiet):
    try:
        require_trusted()
    except EnvironmentProblem as error:
        sys.exit(f"ERROR  {error}")
    outcomes = [run_scenario(s, screenshots, quiet) for s in selected]
    for fixture in FIXTURES.values():
        if fixture_pids(fixture):
            quit_fixture(fixture)
    counts = {o: outcomes.count(o) for o in ("PASS", "FAIL", "XFAIL", "XPASS", "ERROR", "SKIP") if outcomes.count(o)}
    print("\n" + ", ".join(f"{n} {o}" for o, n in counts.items()))
    return 1 if {"FAIL", "XPASS", "ERROR"} & set(outcomes) else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    build = sub.add_parser("build")
    build.add_argument("--skip-app", action="store_true", help="build only the fixtures and the helpers")
    p = sub.add_parser("probe")
    p.add_argument("--prompt", action="store_true", help="ask macOS to show the Accessibility prompt")
    r = sub.add_parser("run")
    r.add_argument("names", nargs="*")
    r.add_argument("--screenshots", action="store_true")
    r.add_argument("--quiet", action="store_true",
                   help="skip the scenarios that take the window focus, and fail a scenario that activates Doll Plus or a fixture")
    sub.add_parser("list")
    d = sub.add_parser("demo")
    d.add_argument("--app", type=Path, default=APP_BINARY, help="the e2e copy of Doll Plus.app or its binary, for example build/e2e/Doll Plus.app of a PR worktree")
    d.add_argument("--red-badge", action="store_true")
    d.add_argument("--hide-when-empty", action="store_true", help="hide the status item while the badge is empty")
    d.add_argument("--cycles", type=int, default=5)
    args = parser.parse_args()

    if args.command == "build":
        build_all(args.skip_app)
    elif args.command == "probe":
        if not PROBE.exists():
            build_helpers()
        print(json.dumps(probe("--prompt") if args.prompt else probe(), indent=2))
    elif args.command == "list":
        for s in SCENARIOS:
            issue = f"  [known issue #{s.known_issue}]" if s.known_issue else ""
            focus = "  [steals focus]" if s.steals_focus else ""
            print(f"{s.name:26} {s.summary}{issue}{focus}")
    elif args.command == "run":
        sys.exit(command_run(args.names, args.screenshots, args.quiet))
    elif args.command == "demo":
        app = args.app.resolve()
        command_demo(app / "Contents/MacOS/Doll Plus" if app.suffix == ".app" else app, args.red_badge, args.hide_when_empty, args.cycles)


if __name__ == "__main__":
    main()
