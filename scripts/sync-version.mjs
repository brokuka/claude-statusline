#!/usr/bin/env node
// package.json is the single source of truth for the version. The installed
// status-line script is copied into ~/.claude ALONE (no package.json alongside),
// so it can't read the version at runtime — we bake it into the script instead.
// This propagates package.json's version into every such place:
//   - statusline.sh   STATUSLINE_VERSION="x.y.z"
//   - statusline.py   __version__ = "x.y.z"
//   - .claude-plugin/plugin.json      "version"
//   - .claude-plugin/marketplace.json "version" (both plugin + top-level)
// Run automatically by `npm run release`; safe to run by hand any time.
// The remote update check reads package.json directly off GitHub — no extra file.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const version = JSON.parse(readFileSync(join(root, "package.json"), "utf8")).version;
if (!version) {
  console.error("sync-version: no version field in package.json");
  process.exit(1);
}

function patch(rel, re, repl) {
  const p = join(root, rel);
  const before = readFileSync(p, "utf8");
  // Reset lastIndex so a /g regex's stateful .test() starts clean each call.
  re.lastIndex = 0;
  if (!re.test(before)) {
    console.warn(`sync-version: WARN no version marker matched in ${rel}`);
    return;
  }
  const after = before.replace(re, repl);
  if (after === before) {
    console.log(`sync-version: ${rel} already at ${version}`);
  } else {
    writeFileSync(p, after);
    console.log(`sync-version: ${rel} -> ${version}`);
  }
}

patch("statusline.sh", /^STATUSLINE_VERSION="[^"]*"/m, `STATUSLINE_VERSION="${version}"`);
patch("statusline.py", /^__version__ = "[^"]*"/m, `__version__ = "${version}"`);
patch(".claude-plugin/plugin.json", /("version":\s*)"[^"]*"/, `$1"${version}"`);
patch(".claude-plugin/marketplace.json", /("version":\s*)"[^"]*"/g, `$1"${version}"`);
