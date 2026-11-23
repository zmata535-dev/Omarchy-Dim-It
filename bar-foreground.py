#!/usr/bin/env python3
"""Temporarily override Omarchy's shared bar foreground through user config."""

import fcntl
import json
import os
import re
import sys
import tempfile
from pathlib import Path
import tomllib


HOME = Path.home()
CONFIG = HOME / ".config/omarchy/shell.toml"
SHELL_JSON = HOME / ".config/omarchy/shell.json"
STATE = HOME / ".local/state/omarchy/plugins/dim-it/bar-foreground.json"
THEME = HOME / ".local/state/omarchy/current/theme/shell.toml"
KEYS = ("text", "active")


def theme_colors() -> dict[str, str]:
    """Read the real foreground palette, not the temporary user override."""
    try:
        with THEME.open("rb") as stream:
            bar = tomllib.load(stream).get("bar", {})
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise ValueError(f"cannot read active Omarchy bar theme: {THEME}") from error
    colors = {key: canonical_color(bar.get(key)) for key in KEYS}
    if any(value is None for value in colors.values()):
        raise ValueError(f"active Omarchy theme has invalid bar foreground colors: {THEME}")
    return colors


def read_lines(path: Path) -> list[str]:
    try:
        return path.read_text().splitlines(keepends=True)
    except FileNotFoundError:
        return []


def section_bounds(lines: list[str], name: str) -> tuple[int | None, int | None]:
    start = None
    for index, line in enumerate(lines):
        match = re.match(r"^\s*\[([^]]+)\]\s*(?:#.*)?(?:\r?\n)?$", line)
        if not match:
            continue
        if start is not None:
            return start, index
        if match.group(1) == name:
            start = index
    if start is not None:
        return start, len(lines)
    return None, None


def key_index(lines: list[str], start: int | None, end: int | None, key: str) -> int | None:
    if start is None or end is None:
        return None
    for index in range(start + 1, end):
        if re.match(rf"^\s*{re.escape(key)}\s*=", lines[index]):
            return index
    return None


def replace_keys(values: dict[str, str | None]) -> None:
    lines = read_lines(CONFIG)
    start, end = section_bounds(lines, "bar")
    if start is None and any(value is not None for value in values.values()):
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        if lines and lines[-1].strip():
            lines.append("\n")
        lines.append("[bar]\n")
        start, end = len(lines) - 1, len(lines)

    if start is not None:
        # Work backwards so removing a line never shifts a later match.
        for key in reversed(KEYS):
            index = key_index(lines, start, end, key)
            value = values.get(key)
            if value is None:
                if index is not None:
                    lines.pop(index)
            else:
                replacement = f'{key} = "{value}"\n'
                if index is None:
                    lines.insert(end, replacement)
                    end += 1
                else:
                    lines[index] = replacement

        if start < len(lines) and lines[start].strip() == "[bar]":
            section_end = next(
                (i for i in range(start + 1, len(lines)) if re.match(r"^\s*\[[^]]+\]", lines[i])),
                len(lines),
            )
            content = [line for line in lines[start + 1:section_end] if line.strip() and not line.lstrip().startswith("#")]
            if not content:
                del lines[start:section_end]

    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    if not lines:
        try:
            CONFIG.unlink()
        except FileNotFoundError:
            pass
        return
    CONFIG.write_text("".join(lines))


def darken(color: str, factor: float) -> str:
    value = color.strip().lower()
    if not re.fullmatch(r"#[0-9a-f]{6}(?:[0-9a-f]{2})?", value):
        raise ValueError(f"unsupported color from active theme: {color!r}")
    alpha = value[1:3] if len(value) == 9 else "ff"
    rgb = value[3:9] if len(value) == 9 else value[1:7]
    channels = [max(0, min(255, round(int(rgb[i:i + 2], 16) / factor))) for i in (0, 2, 4)]
    return "#" + alpha + "".join(f"{channel:02x}" for channel in channels)


def canonical_color(color: str | None) -> str | None:
    if not isinstance(color, str):
        return None
    value = color.strip().lower()
    if not re.fullmatch(r"#[0-9a-f]{6}(?:[0-9a-f]{2})?", value):
        return None
    return value if len(value) == 9 else "#ff" + value[1:]


def line_color(line: str, key: str) -> str | None:
    match = re.match(rf'^\s*{re.escape(key)}\s*=\s*"(#[0-9a-fA-F]+)"', line)
    return canonical_color(match.group(1)) if match else None


def load_state() -> dict | None:
    try:
        return json.loads(STATE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=STATE.parent, prefix=".bar-foreground.")
    with os.fdopen(fd, "w") as stream:
        json.dump(state, stream)
        stream.write("\n")
    os.replace(temporary, STATE)


def read_bar_background() -> tuple[bool, object]:
    try:
        parsed = json.loads(SHELL_JSON.read_text())
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid Omarchy shell config: {SHELL_JSON}") from error
    bar = parsed.get("bar") if isinstance(parsed, dict) else None
    if not isinstance(parsed, dict):
        raise ValueError(f"Omarchy shell config must contain an object: {SHELL_JSON}")
    if not isinstance(bar, dict):
        return False, None
    return "background" in bar, bar.get("background")


def write_bar_background(value: object | None, present: bool = True) -> None:
    parsed = json.loads(SHELL_JSON.read_text())
    if not isinstance(parsed, dict):
        raise ValueError("shell.json must contain an object")
    bar = parsed.get("bar")
    if not isinstance(bar, dict):
        bar = {}
        parsed["bar"] = bar
    if present:
        bar["background"] = value
    else:
        bar.pop("background", None)

    mode = SHELL_JSON.stat().st_mode & 0o777
    fd, temporary = tempfile.mkstemp(dir=SHELL_JSON.parent, prefix=".dim-it-shell.")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(parsed, stream, indent=2)
            stream.write("\n")
        os.chmod(temporary, mode)
        os.replace(temporary, SHELL_JSON)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def apply(mode: str, text_color: str, active_color: str) -> None:
    if mode not in ("dark", "very-dark", "black"):
        raise ValueError(f"unknown foreground mode: {mode}")
    # The user shell.toml may contain this plugin's last temporary values.
    # Always use the active theme as the base so repeated dim cycles cannot
    # progressively darken the bar or preserve a stale black foreground.
    palette = theme_colors()
    state = load_state()
    new_state = state is None
    if state is None:
        lines = read_lines(CONFIG)
        start, end = section_bounds(lines, "bar")
        original = {}
        for key in KEYS:
            index = key_index(lines, start, end, key)
            original[key] = f'{key} = "{palette[key]}"\n'
        state = {
            "hadFile": CONFIG.exists(),
            "hadBarSection": start is not None,
            "original": original,
            "base": palette,
        }
        had_background, original_background = read_bar_background()
        state["hadBarBackground"] = had_background
        state["originalBarBackground"] = original_background
        save_state(state)
    elif "originalBarBackground" not in state:
        had_background, original_background = read_bar_background()
        state["hadBarBackground"] = had_background
        state["originalBarBackground"] = original_background

    if not new_state and "appliedBarBackground" in state:
        had_background, current_background = read_bar_background()
        if not had_background or current_background != state["appliedBarBackground"]:
            state["hadBarBackground"] = had_background
            state["originalBarBackground"] = current_background

    incoming_base = palette
    if not new_state and isinstance(state.get("applied"), dict):
        lines = read_lines(CONFIG)
        start, end = section_bounds(lines, "bar")
        theme_changed = False
        for key in KEYS:
            incoming = incoming_base[key]
            previous = canonical_color(state["applied"].get(key))
            if incoming and incoming != previous:
                state["base"][key] = incoming
                theme_changed = True
                state["original"][key] = f'{key} = "{incoming}"\n'
        if theme_changed:
            state["hadFile"] = CONFIG.exists()
            state["hadBarSection"] = start is not None

    if mode == "black":
        changed = {key: "#ff000000" for key in KEYS}
    else:
        factor = 1.5 if mode == "dark" else 2.1
        changed = {key: darken(state["base"][key], factor) for key in KEYS}

    state["applied"] = changed
    state["appliedBarBackground"] = "none"
    save_state(state)
    replace_keys(changed)
    write_bar_background("none")


def restore() -> None:
    state = load_state()
    palette = theme_colors()
    # Always restore the current Omarchy theme. The saved foreground snapshot
    # may be stale, or another writer may have changed the temporary colors.
    replace_keys(palette)
    if state is None:
        return
    if "originalBarBackground" in state:
        if "appliedBarBackground" not in state:
            write_bar_background(state.get("originalBarBackground"), state.get("hadBarBackground", False))
        else:
            had_background, current_background = read_bar_background()
            if had_background and current_background == state["appliedBarBackground"]:
                write_bar_background(state.get("originalBarBackground"), state.get("hadBarBackground", False))
    try:
        STATE.unlink()
    except FileNotFoundError:
        pass


def main() -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    lock_path = STATE.with_suffix(".lock")
    with lock_path.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if len(sys.argv) >= 2 and sys.argv[1] == "apply":
            if len(sys.argv) != 5 or sys.argv[2] not in ("dark", "very-dark", "black"):
                raise SystemExit("usage: bar-foreground.py apply dark|very-dark|black TEXT_COLOR ACTIVE_COLOR")
            apply(sys.argv[2], sys.argv[3], sys.argv[4])
        elif len(sys.argv) == 2 and sys.argv[1] == "restore":
            restore()
        else:
            raise SystemExit("usage: bar-foreground.py apply|restore ...")


if __name__ == "__main__":
    main()
