import fs from "node:fs";
import test from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

import {
  parseGameData,
  serializeProject,
  validateProjectShape,
} from "../lib/data-file.mjs";

const sourcePath = fileURLToPath(
  new URL("../../../src/game/data.asm", import.meta.url),
);
const source = fs.readFileSync(sourcePath, "utf8");

test("parses all campaign rooms and actor metadata", () => {
  const project = parseGameData(source);

  assert.equal(project.width, 30);
  assert.equal(project.height, 22);
  assert.deepEqual(project.stageRoomCounts, [1, 2, 2, 2, 2, 3, 3, 3, 3]);
  assert.equal(project.rooms.length, 21);
  assert.equal(project.rooms[0].name, "Stage 1, Room 1");
  assert.equal(project.rooms[1].name, "Stage 2, Room 1");
  assert.equal(project.rooms[7].name, "Stage 5, Room 1");
  assert.equal(project.rooms[20].name, "Stage 9, Room 3");
  assert.deepEqual(project.rooms[0].start, { x: 1, y: 1 });
  assert.deepEqual(project.rooms[0].enemyStarts[0], { x: 16, y: 3 });
});

test("an untouched project serializes byte-for-byte", () => {
  const project = parseGameData(source);
  assert.equal(serializeProject(source, project), source);
});

test("serializes grid and coordinate edits back into their source tables", () => {
  const project = parseGameData(source);
  const firstRow = project.rooms[0].tiles[1];
  project.rooms[0].tiles[1] = `${firstRow.slice(0, 2)}#${firstRow.slice(3)}`;
  project.rooms[0].start = { x: 2, y: 2 };
  project.rooms[0].enemyStarts[0] = { x: 3, y: 4 };

  const reparsed = parseGameData(serializeProject(source, project));
  assert.equal(reparsed.rooms[0].tiles[1][2], "#");
  assert.deepEqual(reparsed.rooms[0].start, { x: 2, y: 2 });
  assert.deepEqual(reparsed.rooms[0].enemyStarts[0], { x: 3, y: 4 });
});

test("rejects malformed editor projects", () => {
  const project = parseGameData(source);
  project.rooms[0].tiles[0] = "too short";
  assert.throws(
    () => validateProjectShape(project),
    /row 0 must be 30 cells wide/,
  );
});
