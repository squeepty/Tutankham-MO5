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
  assert.equal(project.rooms[0].name, "Chamber of Ra, Room 1");
  assert.equal(project.rooms[1].name, "Chamber of Anubis, Room 1");
  assert.equal(project.rooms[7].name, "Chamber of Sobek, Room 1");
  assert.equal(project.rooms[20].name, "Chamber of Tutankhamun, Room 3");
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

test("chamber labels follow assembly source names", () => {
  const renamed = source.replace('"CHAMBER OF RA"', '"CHAMBER OF ATEN"');
  const project = parseGameData(renamed);
  assert.equal(project.chamberNames.length, 9);
  assert.equal(project.chamberNames[0], "Chamber of Aten");
  assert.equal(project.rooms[0].name, "Chamber of Aten, Room 1");
  assert.equal(serializeProject(renamed, project), renamed);
});

test("Each room has ten non-overlapping wall engravings using all six symbols", () => {
  const project = parseGameData(source);
  assert.equal(project.wallSymbols.length, 6);
  assert.ok(project.wallSymbols.every(symbol => symbol.bitmap.length === 16));
  for (const room of project.rooms) {
    assert.equal(room.wallDecorations.length, 10);
    const occupied = new Set();
    for (const { x, y, symbol } of room.wallDecorations) {
      assert.ok(symbol >= 0 && symbol < 6);
      for (const dx of [0, 1]) {
        assert.equal(room.tiles[y][x + dx], "#");
        const key = `${x + dx},${y}`;
        assert.ok(!occupied.has(key));
        occupied.add(key);
      }
    }
    assert.equal(new Set(room.wallDecorations.map(item => item.symbol)).size, 6);
  }
});

test("door artwork provides four cells per color and current exits have room for artwork", () => {
  const project = parseGameData(source);
  assert.deepEqual(project.doorSprites.map(sprite => sprite.name), ["Yellow", "Red"]);
  assert.ok(project.doorSprites.every(sprite => sprite.bitmap.length === 32));
  const widths = new Set();
  for (const room of project.rooms) {
    for (let y = 1; y < project.height - 1; y += 2) {
      for (let x = 0; x < project.width; x += 1) {
        if (room.tiles[y][x] !== "D") continue;
        assert.equal(room.tiles[y + 1][x], "D");
        widths.add(Math.min(2, project.width - x - 1));
      }
    }
  }
  assert.ok(widths.size > 0);
  assert.ok([...widths].every(width => width >= 1 && width <= 2));
});
