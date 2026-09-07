#!/usr/bin/env node
// Check the shipped Markdown tree, excluding generated release copies in build/.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
function markdownFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    if (entry.name.startsWith(".") || entry.name === "build") return [];
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? markdownFiles(file) : file.endsWith(".md") ? [file] : [];
  });
}

const files = markdownFiles(root);
const failures = [];
for (const file of files) {
  const source = fs.readFileSync(file, "utf8");
  const relative = path.relative(root, file);
  // Ignore fenced examples and external URLs; only local file targets are checked.
  const prose = source.replace(/^```[^\n]*\n[\s\S]*?^```\s*$/gm, "");
  for (const match of prose.matchAll(/\[[^\]]*\]\(([^\s)]+)\)/g)) {
    const target = match[1];
    if (/^(?:[a-z][a-z\d+.-]*:|#)/i.test(target)) continue;
    const local = decodeURIComponent(target.split(/[?#]/)[0]);
    if (!fs.existsSync(path.resolve(path.dirname(file), local))) {
      failures.push(`${relative}: missing link target ${target}`);
    }
  }
}
// A new assembly fragment needs a companion page before it can ship.
function checkAssembly(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) checkAssembly(file);
    else if (file.endsWith(".asm")) {
      const relative = path.relative(root, file);
      if (!fs.existsSync(path.join(root, "docs/assembly", `${relative}.md`))) {
        failures.push(`${relative}: missing assembly handbook page`);
      }
    }
  }
}
checkAssembly(path.join(root, "src"));
if (failures.length) {
  console.error(failures.join("\n"));
  process.exitCode = 1;
} else {
  console.log(`Validated ${files.length} Markdown files: local file links and assembly handbook coverage`);
}
