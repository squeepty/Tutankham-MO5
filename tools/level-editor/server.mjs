#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

import { parseGameData, serializeProject } from "./lib/data-file.mjs";

const editorRoot = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(editorRoot, "../..");
const publicRoot = path.join(editorRoot, "public");
const dataPath = path.join(projectRoot, "src/game/data.asm");
const validatorPath = path.join(projectRoot, "tools/validate-content.mjs");
const host = "127.0.0.1";

const mimeTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".svg", "image/svg+xml"],
]);

function revisionFor(source) {
  return crypto.createHash("sha256").update(source).digest("hex");
}

function json(response, status, body) {
  const payload = JSON.stringify(body);
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(payload),
    "Cache-Control": "no-store",
  });
  response.end(payload);
}

async function jsonBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 2_000_000) throw new Error("Request body is too large");
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new Error("Request body is not valid JSON");
  }
}

function runCommand(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: projectRoot,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", reject);
    child.on("close", (code) => resolve({ code, stdout, stderr }));
  });
}

function conciseValidationError(stderr) {
  const errorLine = stderr
    .split(/\r?\n/)
    .find((line) => line.startsWith("Error: "));
  return errorLine ? errorLine.slice("Error: ".length) : stderr.trim();
}

async function validateCandidate(candidate) {
  const temporaryDirectory = await fs.mkdtemp(
    path.join(os.tmpdir(), "tutankham-level-editor-"),
  );
  const temporarySource = path.join(temporaryDirectory, "data.asm");
  try {
    await fs.writeFile(temporarySource, candidate, "utf8");
    const result = await runCommand(process.execPath, [
      validatorPath,
      temporarySource,
    ]);
    return {
      ok: result.code === 0,
      message:
        result.code === 0
          ? result.stdout.trim()
          : conciseValidationError(result.stderr) || "Validation failed",
    };
  } finally {
    await fs.rm(temporaryDirectory, { recursive: true, force: true });
  }
}

async function currentSource() {
  const source = await fs.readFile(dataPath, "utf8");
  return { source, revision: revisionFor(source) };
}

async function candidateFromRequest(request) {
  const body = await jsonBody(request);
  if (!body || typeof body.revision !== "string" || !body.project) {
    throw new Error("Expected a revision and editor project");
  }
  const current = await currentSource();
  if (body.revision !== current.revision) {
    const conflict = new Error(
      "src/game/data.asm changed after the editor loaded it. Reload before saving.",
    );
    conflict.status = 409;
    throw conflict;
  }
  return {
    current,
    project: body.project,
    candidate: serializeProject(current.source, body.project),
  };
}

async function writeSourceAtomically(source) {
  const stat = await fs.stat(dataPath);
  const temporaryPath = path.join(
    path.dirname(dataPath),
    `.data.asm.level-editor-${process.pid}-${Date.now()}.tmp`,
  );
  try {
    await fs.writeFile(temporaryPath, source, { mode: stat.mode });
    await fs.rename(temporaryPath, dataPath);
  } catch (error) {
    await fs.rm(temporaryPath, { force: true });
    throw error;
  }
}

async function serveStatic(request, response, pathname) {
  const relativePath = pathname === "/" ? "index.html" : pathname.slice(1);
  const decodedPath = decodeURIComponent(relativePath);
  const filePath = path.resolve(publicRoot, decodedPath);
  if (
    filePath !== publicRoot &&
    !filePath.startsWith(`${publicRoot}${path.sep}`)
  ) {
    json(response, 404, { error: "Not found" });
    return;
  }
  try {
    const contents = await fs.readFile(filePath);
    response.writeHead(200, {
      "Content-Type": mimeTypes.get(path.extname(filePath)) ?? "application/octet-stream",
      "Content-Length": contents.length,
      "Cache-Control": "no-cache",
      "Content-Security-Policy":
        "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
    });
    if (request.method === "HEAD") response.end();
    else response.end(contents);
  } catch (error) {
    if (error.code === "ENOENT" || error.code === "EISDIR") {
      json(response, 404, { error: "Not found" });
      return;
    }
    throw error;
  }
}

export function createLevelEditorServer() {
  return http.createServer(async (request, response) => {
    try {
      const url = new URL(request.url, `http://${host}`);
      if (request.method === "GET" && url.pathname === "/api/project") {
        const current = await currentSource();
        json(response, 200, {
          revision: current.revision,
          sourcePath: path.relative(projectRoot, dataPath),
          project: parseGameData(current.source),
        });
        return;
      }
      if (request.method === "POST" && url.pathname === "/api/validate") {
        const { candidate } = await candidateFromRequest(request);
        const validation = await validateCandidate(candidate);
        json(response, validation.ok ? 200 : 422, validation);
        return;
      }
      if (request.method === "PUT" && url.pathname === "/api/project") {
        const { candidate } = await candidateFromRequest(request);
        const validation = await validateCandidate(candidate);
        if (!validation.ok) {
          json(response, 422, validation);
          return;
        }
        await writeSourceAtomically(candidate);
        json(response, 200, {
          ok: true,
          message: validation.message,
          revision: revisionFor(candidate),
        });
        return;
      }
      if (request.method === "GET" && url.pathname === "/api/health") {
        json(response, 200, { ok: true });
        return;
      }
      if (request.method === "GET" || request.method === "HEAD") {
        await serveStatic(request, response, url.pathname);
        return;
      }
      json(response, 404, { error: "Not found" });
    } catch (error) {
      json(response, error.status ?? 400, {
        error: error.message || "Unexpected editor error",
      });
    }
  });
}

function portFromArguments(arguments_) {
  const portIndex = arguments_.indexOf("--port");
  const rawPort = portIndex >= 0 ? arguments_[portIndex + 1] : "4173";
  const port = Number.parseInt(rawPort, 10);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`Invalid port: ${rawPort}`);
  }
  return port;
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
) {
  if (process.argv.includes("--help")) {
    console.log("Usage: node tools/level-editor/server.mjs [--port 4173]");
  } else {
    const port = portFromArguments(process.argv.slice(2));
    const server = createLevelEditorServer();
    server.listen(port, host, () => {
      console.log(`Tutankham level editor: http://${host}:${port}`);
      console.log(`Editing: ${dataPath}`);
    });
  }
}
