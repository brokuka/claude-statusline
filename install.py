#!/usr/bin/env python3
"""
Installer for the Claude Code status line.

What it does (idempotent):
  1. Copies statusline.py into your Claude Code config dir.
  2. Merges a `statusLine` entry into settings.json WITHOUT touching your other
     settings (reads, updates one key, writes back pretty-printed).

Usage:
  python install.py                 # install into the default config dir
  python install.py --dir PATH      # install into a specific config dir
  python install.py --uninstall     # remove the statusLine entry (keeps the script)

Config dir resolution (first match wins):
  --dir argument  ->  $CLAUDE_CONFIG_DIR  ->  ~/.claude
"""
import argparse
import json
import os
import re
import shutil
import sys

REFRESH_INTERVAL = 1  # seconds; keeps the live session timer ticking
REPO = "brokuka/claude-statusline"
BRANCH = "main"
RAW = f"https://raw.githubusercontent.com/{REPO}/{BRANCH}"


def local_version():
    """Read __version__ from the bundled statusline.py."""
    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "statusline.py")
    try:
        with open(src, encoding="utf-8") as f:
            m = re.search(r'^__version__ = "([^"]*)"', f.read(), re.M)
            return m.group(1) if m else ""
    except Exception:
        return ""


def installed_version(dest):
    try:
        with open(dest, encoding="utf-8") as f:
            m = re.search(r'^__version__ = "([^"]*)"', f.read(), re.M)
            return m.group(1) if m else ""
    except Exception:
        return ""


_GIT_RE = re.compile(r'(SHOW_GIT = os\.environ\.get\("CC_STATUSLINE_GIT", ")[01]("\))')


def git_default(path):
    """Return '0'/'1' — the SHOW_GIT default baked into an installed copy, or ''."""
    try:
        with open(path, encoding="utf-8") as f:
            m = re.search(r'SHOW_GIT = os\.environ\.get\("CC_STATUSLINE_GIT", "([01])"\)', f.read())
            return m.group(1) if m else ""
    except Exception:
        return ""


def set_git(path, mode):
    """Flip the SHOW_GIT default in an installed copy. mode: 'on' | 'off'."""
    digit = "0" if mode == "off" else "1"
    with open(path, encoding="utf-8") as f:
        src = f.read()
    new = _GIT_RE.sub(rf"\g<1>{digit}\g<2>", src)
    with open(path, "w", encoding="utf-8") as f:
        f.write(new)


def _kv_re(var, env):
    return re.compile(rf'({re.escape(var)} = os\.environ\.get\("{re.escape(env)}", ")[^"]*(")')


def kv_default(path, var, env):
    """Return the baked-in default of  VAR = os.environ.get("ENV", "..."), or ''."""
    try:
        with open(path, encoding="utf-8") as f:
            m = re.search(rf'{re.escape(var)} = os\.environ\.get\("{re.escape(env)}", "([^"]*)"', f.read())
            return m.group(1) if m else ""
    except Exception:
        return ""


def set_kv(path, var, env, value):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    with open(path, "w", encoding="utf-8") as f:
        f.write(_kv_re(var, env).sub(rf"\g<1>{value}\g<2>", src))


def apply_style(path, view, bars):
    if view:
        set_kv(path, "VIEW", "CC_STATUSLINE_VIEW", view)
    if bars:
        set_kv(path, "BARS", "CC_STATUSLINE_BARS", bars)


def set_ver(path, mode):
    """Flip the SHOW_VERSION default (the vX.Y.Z tag). mode: 'on' | 'off'."""
    set_kv(path, "SHOW_VERSION", "CC_STATUSLINE_VERSION", "0" if mode == "off" else "1")


def fetch(url):
    from urllib.request import urlopen
    with urlopen(url, timeout=10) as r:  # noqa: S310 (fixed https host)
        return r.read().decode("utf-8")


def self_update(dest, gitmode=None, view=None, bars=None, vermode=None):
    """Replace the installed statusline.py with the latest from GitHub."""
    if not os.path.exists(dest):
        sys.exit(f"not installed at {dest} — run `python install.py` first")
    cur = installed_version(dest)
    prev_git = git_default(dest)  # remember preferences before overwriting
    prev_ver = kv_default(dest, "SHOW_VERSION", "CC_STATUSLINE_VERSION")
    prev_view = kv_default(dest, "VIEW", "CC_STATUSLINE_VIEW")
    prev_bars = kv_default(dest, "BARS", "CC_STATUSLINE_BARS")
    try:
        latest = json.loads(fetch(f"{RAW}/package.json")).get("version", "")
    except Exception as e:
        sys.exit(f"could not fetch latest version: {e}")
    print(f"current: {cur or 'unknown'}")
    print(f"latest:  {latest or 'unknown'}")
    if not latest:
        sys.exit("could not read latest version")
    if cur == latest:
        print("already up to date.")
        return
    try:
        script = fetch(f"{RAW}/statusline.py")
    except Exception as e:
        sys.exit(f"download failed: {e}")
    with open(dest, "w", encoding="utf-8") as f:
        f.write(script)
    # Carry preferences across the update: an explicit flag wins, else keep prior.
    if gitmode:
        set_git(dest, gitmode)
    elif prev_git == "0":
        set_git(dest, "off")
    if vermode:
        set_ver(dest, vermode)
    elif prev_ver == "0":
        set_ver(dest, "off")
    apply_style(dest, view or (prev_view if prev_view and prev_view != "default" else None),
                bars or (prev_bars if prev_bars and prev_bars != "line" else None))
    # clear the cached "update available" notice so the status line drops it
    import tempfile
    try:
        os.remove(os.path.join(tempfile.gettempdir(), "cc-statusline-update"))
    except OSError:
        pass
    print(f"✓ updated {dest} -> {latest}")


def resolve_config_dir(explicit):
    if explicit:
        return os.path.abspath(os.path.expanduser(explicit))
    env = os.environ.get("CLAUDE_CONFIG_DIR")
    if env:
        return os.path.abspath(os.path.expanduser(env))
    return os.path.join(os.path.expanduser("~"), ".claude")


def load_settings(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}
    except Exception as e:
        sys.exit(f"error: {path} exists but isn't valid JSON ({e}). Fix it and retry.")


def save_settings(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def build_command(dest):
    # Use the running interpreter (most reliable "which python") and forward
    # slashes: backslashes in a Windows path get eaten as escapes when Claude
    # Code runs the command through Git Bash.
    py = sys.executable.replace("\\", "/")
    dest = dest.replace("\\", "/")
    return f'"{py}" "{dest}"'


def main():
    ap = argparse.ArgumentParser(description="Install the Claude Code status line.")
    ap.add_argument("--dir", help="Claude Code config dir (default: $CLAUDE_CONFIG_DIR or ~/.claude)")
    ap.add_argument("--uninstall", action="store_true", help="remove the statusLine entry")
    ap.add_argument("--update", action="store_true", help="replace the installed script with the latest from GitHub")
    ap.add_argument("--version", action="store_true", help="print the bundled version and exit")
    ap.add_argument("--git", dest="gitmode", action="store_const", const="on", help="show the git segment (default)")
    ap.add_argument("--no-git", dest="gitmode", action="store_const", const="off", help="hide the git branch/dirty segment")
    ap.add_argument("--toggle-git", action="store_true", help="flip the installed copy's git segment in place")
    ap.add_argument("--show-version", dest="vermode", action="store_const", const="on", help="show the vX.Y.Z tag (default)")
    ap.add_argument("--hide-version", dest="vermode", action="store_const", const="off", help="hide the vX.Y.Z tag")
    ap.add_argument("--view", choices=["default", "oneline", "minimal"], help="layout")
    ap.add_argument("--bars", choices=["line", "blocks", "solid", "ascii", "dots"], help="bar style")
    args = ap.parse_args()

    if args.version:
        print(f"claude-statusline {local_version() or 'unknown'}")
        return

    config_dir = resolve_config_dir(args.dir)
    settings_path = os.path.join(config_dir, "settings.json")
    dest = os.path.join(config_dir, "statusline.py")

    if args.update:
        self_update(dest, args.gitmode, args.view, args.bars, args.vermode)
        return

    # --toggle-git: flip the installed copy in place and exit (the plugin's git command).
    if args.toggle_git:
        if not os.path.exists(dest):
            sys.exit(f"not installed at {dest}")
        mode = "on" if git_default(dest) == "0" else "off"
        set_git(dest, mode)
        print(f"git segment: {'hidden' if mode == 'off' else 'shown'} -> {dest}")
        return

    # --git/--view/--bars/--hide-version etc. on an existing install: change those
    # settings in place and exit — no reinstall (the plugin's configure command).
    # If nothing is installed yet, fall through to a normal install that bakes them in.
    if (args.gitmode or args.vermode or args.view or args.bars) and not args.uninstall and os.path.exists(dest):
        if args.gitmode:
            set_git(dest, args.gitmode)
        if args.vermode:
            set_ver(dest, args.vermode)
        apply_style(dest, args.view, args.bars)
        gitstate = "hidden" if git_default(dest) == "0" else "shown"
        verstate = "hidden" if kv_default(dest, "SHOW_VERSION", "CC_STATUSLINE_VERSION") == "0" else "shown"
        print(f"updated -> git:{gitstate} version:{verstate} "
              f"view:{kv_default(dest, 'VIEW', 'CC_STATUSLINE_VIEW')} "
              f"bars:{kv_default(dest, 'BARS', 'CC_STATUSLINE_BARS')} ({dest})")
        return

    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "statusline.py")

    settings = load_settings(settings_path)

    if args.uninstall:
        if settings.pop("statusLine", None) is not None:
            save_settings(settings_path, settings)
            print(f"removed statusLine from {settings_path}")
        else:
            print("nothing to remove (no statusLine entry)")
        return

    os.makedirs(config_dir, exist_ok=True)
    shutil.copyfile(src, dest)
    if args.gitmode:
        set_git(dest, args.gitmode)  # apply --git/--no-git to the fresh copy
    if args.vermode:
        set_ver(dest, args.vermode)  # apply --show/--hide-version
    apply_style(dest, args.view, args.bars)  # apply --view/--bars to the fresh copy

    settings["statusLine"] = {
        "type": "command",
        "command": build_command(dest),
        "refreshInterval": REFRESH_INTERVAL,
    }
    save_settings(settings_path, settings)

    print(f"installed script  -> {dest}")
    print(f"updated settings  -> {settings_path}")
    if args.gitmode:
        print(f"git segment       -> {'hidden' if args.gitmode == 'off' else 'shown'}")
    if args.vermode:
        print(f"version tag       -> {'hidden' if args.vermode == 'off' else 'shown'}")
    if args.view or args.bars:
        print(f"style             -> view:{kv_default(dest, 'VIEW', 'CC_STATUSLINE_VIEW')} "
              f"bars:{kv_default(dest, 'BARS', 'CC_STATUSLINE_BARS')}")
    print("done. Restart Claude Code (or send one message) to see the status line.")


if __name__ == "__main__":
    main()
