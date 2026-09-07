#!/usr/bin/env node
// Build a reviewable release candidate. Does not commit, tag, or publish.
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const run = (command, args) => execFileSync(command, args, { cwd: root, stdio: "inherit" });
const version = fs.readFileSync(path.join(root, "VERSION"), "utf8").trim();
if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error("VERSION must be major.minor.patch");
const tests = fs.readdirSync(path.join(root, "tools/level-editor/test"))
  .filter(name => name.endsWith(".test.mjs"))
  .sort()
  .map(name => `tools/level-editor/test/${name}`);
run(process.execPath, ["tools/validate-docs.mjs"]);
run(process.execPath, ["--test", ...tests]);
run("sh", ["tools/build.sh"]);
run(process.execPath, ["tools/export-level-images.mjs"]);

const name = `tutankham-mo5-v${version}`;
const staging = path.join(root, "build", name);
fs.rmSync(staging, { recursive: true, force: true });
fs.mkdirSync(path.join(staging, "build"), { recursive: true });
for (const entry of ["README.md", "VERSION", "src", "tools", "docs", "levels_current"]) {
  fs.cpSync(path.join(root, entry), path.join(staging, entry), {
    recursive: true,
    // Finder metadata and editor backup files are not release payload.
    filter: source => ![".DS_Store"].includes(path.basename(source)) && !source.endsWith("~"),
  });
}
for (const entry of ["tutankham-mo5.bin", "tutankham-mo5.loadm", "tutankham-mo5.k7", "DCMOTO_LOAD.txt", "DCMOTO_AUTOTYPE.txt"]) {
  fs.copyFileSync(path.join(root, "build", entry), path.join(staging, "build", entry));
}
// Loading instructions in the archive must not point at the build machine.
const notesPath = path.join(staging, "build/DCMOTO_LOAD.txt");
fs.writeFileSync(notesPath, fs.readFileSync(notesPath, "utf8").replaceAll(root + "/", ""));

function filesIn(directory, prefix = "") {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const relative = prefix + entry.name;
    return entry.isDirectory()
      ? filesIn(path.join(directory, entry.name), `${relative}/`)
      : [relative];
  }).sort();
}
const files = filesIn(staging).map(file => {
  const bytes = fs.readFileSync(path.join(staging, file));
  return { path: file, bytes: bytes.length, sha256: crypto.createHash("sha256").update(bytes).digest("hex") };
});
const binaryBytes = fs.statSync(path.join(staging, "build/tutankham-mo5.bin")).size;
const constants = fs.readFileSync(path.join(root, "src/constants.asm"), "utf8");
const originMatch = /^PROGRAM_ORIGIN\s+equ\s+\$([\da-f]+)/im.exec(constants);
if (!originMatch) throw new Error("Missing hexadecimal PROGRAM_ORIGIN in src/constants.asm");
const origin = Number.parseInt(originMatch[1], 16);
// Hash the payload before writing metadata, avoiding self-referential hashes.
fs.writeFileSync(path.join(staging, "manifest.json"), JSON.stringify({
  version, status: "release-candidate", manualEmulatorVerification: "pending",
  program: { origin, bytes: binaryBytes, endInclusive: origin + binaryBytes - 1,
    stackGuard: 0x9800, bytesBelowGuard: 0x9800 - origin - binaryBytes },
  files,
}, null, 2) + "\n");
fs.writeFileSync(path.join(staging, "SHA256SUMS"), files.map(file => `${file.sha256}  ${file.path}`).join("\n") + "\n");
run("tar", ["-czf", `build/${name}.tar.gz`, "-C", "build", name]);
console.log(`Release candidate: build/${name}.tar.gz (manual emulator verification pending)`);
