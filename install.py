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
import shutil
import sys

REFRESH_INTERVAL = 1  # seconds; keeps the live session timer ticking


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
    args = ap.parse_args()

    config_dir = resolve_config_dir(args.dir)
    settings_path = os.path.join(config_dir, "settings.json")
    settings = load_settings(settings_path)

    if args.uninstall:
        if settings.pop("statusLine", None) is not None:
            save_settings(settings_path, settings)
            print(f"removed statusLine from {settings_path}")
        else:
            print("nothing to remove (no statusLine entry)")
        return

    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "statusline.py")
    dest = os.path.join(config_dir, "statusline.py")
    os.makedirs(config_dir, exist_ok=True)
    shutil.copyfile(src, dest)

    settings["statusLine"] = {
        "type": "command",
        "command": build_command(dest),
        "refreshInterval": REFRESH_INTERVAL,
    }
    save_settings(settings_path, settings)

    print(f"installed script  -> {dest}")
    print(f"updated settings  -> {settings_path}")
    print("done. Restart Claude Code (or send one message) to see the status line.")


if __name__ == "__main__":
    main()
