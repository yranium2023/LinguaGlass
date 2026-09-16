const { spawnSync } = require("node:child_process");
const path = require("node:path");
const root = path.resolve(__dirname, "..");
const build = process.argv[2] === "build";
function run(script, args) {
  const result = spawnSync(
    process.execPath,
    [path.join(root, script), ...args],
    { cwd: root, stdio: "inherit" },
  );
  if (result.status !== 0) process.exit(result.status || 1);
}
if (build) run("node_modules/typescript/bin/tsc", ["--noEmit"]);
run(
  "node_modules/vite/bin/vite.js",
  build ? ["build"] : ["--host", "127.0.0.1"],
);
