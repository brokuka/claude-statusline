#!/usr/bin/env node
// Cut a release:
//   1. changelogen --release  -> bump package.json, update CHANGELOG.md, commit, tag
//   2. sync-version           -> propagate the new version into VERSION + scripts + manifests
//   3. commit that sync (if anything changed) and push commits + tags
//
// Version bump is driven by Conventional Commits since the last tag (feat -> minor,
// fix -> patch, `!`/BREAKING -> major). Run: `npm run release`.
import { execSync } from "node:child_process";

const run = (cmd) => execSync(cmd, { stdio: "inherit" });

run("npx changelogen@latest --release");
run("node scripts/sync-version.mjs");

let dirty = false;
try {
  execSync("git diff --quiet", { stdio: "ignore" });
} catch {
  dirty = true;
}
if (dirty) {
  run('git commit -am "chore(release): sync version to VERSION, scripts, and manifests"');
} else {
  console.log("release: VERSION/scripts already in sync, nothing extra to commit");
}

run("git push --follow-tags");
console.log("release: done");
