// SPDX-License-Identifier: GPL-3.0-only
// Build machub-agent-hook (release) và đặt vào src-tauri/binaries/ theo tên Tauri yêu cầu
// (machub-agent-hook-<target-triple>[.exe]) để đóng gói cạnh MacHub.exe.
import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const triple =
  process.env.MACHUB_TARGET ||
  execFileSync("rustc", ["-vV"], { encoding: "utf8" }).match(/^host: (.+)$/m)[1].trim();
const args = ["build", "--release", "-p", "machub-agent-hook"];
if (process.env.MACHUB_TARGET) args.push("--target", triple);
execFileSync("cargo", args, { cwd: root, stdio: "inherit" });

const ext = triple.includes("windows") ? ".exe" : "";
const built = process.env.MACHUB_TARGET
  ? join(root, "target", triple, "release", `machub-agent-hook${ext}`)
  : join(root, "target", "release", `machub-agent-hook${ext}`);
const out = join(root, "src-tauri", "binaries", `machub-agent-hook-${triple}${ext}`);
mkdirSync(dirname(out), { recursive: true });
copyFileSync(built, out);
console.log(`hook → ${out}`);
