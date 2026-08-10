#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { parseGameData, serializeProject } from "./level-editor/lib/data-file.mjs";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, "..");
const dataPath = path.join(projectRoot, "src/game/data.asm");
const arcadeMapsPath = path.join(projectRoot, "src/arcade_maps");
const WIDTH = 30;
const ARCADE_HEIGHT = 12;

function arcadeRowsFor(source, level) {
  const marker = `  Level ${level}\n`;
  const start = source.indexOf(marker);
  if (start < 0) throw new Error(`Missing arcade Level ${level}`);
  const rows = source
    .slice(start + marker.length)
    .split(/\n\s{4}(?:This|It's|If you|Use the)/, 1)[0]
    .split(/\r?\n/)
    .filter((line) => line.startsWith("X"));
  const expectedWidth = level === 1 ? 30 : 62;
  if (
    rows.length !== ARCADE_HEIGHT ||
    rows.some((row) => row.length !== expectedWidth)
  ) {
    throw new Error(
      `Arcade Level ${level} must be ${expectedWidth}×${ARCADE_HEIGHT}`,
    );
  }
  return rows;
}

function pointKey(x, arcadeRow) {
  return `${x},${arcadeRow}`;
}

function importedRoom(rows, specification) {
  const {
    firstColumn,
    exit,
    key,
    extraTreasures = [],
    spawnPoints,
    warpColumns = [],
    start,
  } = specification;
  const sourceOverrides = new Map();
  if (key) sourceOverrides.set(pointKey(...key), "K");
  for (const point of extraTreasures) {
    sourceOverrides.set(pointKey(...point), "T");
  }
  if (exit.source) sourceOverrides.set(pointKey(...exit.source), exit.tile);
  const spawnSet = new Set(spawnPoints.map((point) => pointKey(...point)));
  const warpSet = new Set(warpColumns);

  const logicalRows = [];
  for (let arcadeRow = 1; arcadeRow <= 10; arcadeRow += 1) {
    const logical = [];
    for (let offset = 0; offset < 28; offset += 1) {
      const sourceX = firstColumn + offset;
      const sourceCharacter = rows[arcadeRow][sourceX];
      const override = sourceOverrides.get(pointKey(sourceX, arcadeRow));
      if (override) {
        logical.push(override);
        continue;
      }
      if (spawnSet.has(pointKey(sourceX, arcadeRow))) {
        logical.push("S");
        continue;
      }
      if (sourceCharacter === "X" || sourceCharacter === "x") {
        logical.push("#");
      } else if (sourceCharacter === ".") {
        logical.push(".");
      } else if (sourceCharacter === "^") {
        logical.push(warpSet.has(sourceX) ? "A" : ".");
      } else if (sourceCharacter === "v") {
        logical.push(warpSet.has(sourceX) ? "V" : ".");
      } else if (sourceCharacter === "+") {
        logical.push("T");
      } else {
        // Spaces, key/door markers not selected for MO5 progression, empty
        // niches, and later-loop markers are all traversable arcade floor.
        logical.push(".");
      }
    }
    logicalRows.push(logical);
  }

  const tiles = ["#".repeat(WIDTH)];
  for (const [logicalIndex, logical] of logicalRows.entries()) {
    const upper = ["#", ...logical, "#"];
    const lower = ["#", ...logical.map((tile) => {
      if ("SVARD".includes(tile)) return tile;
      return tile === "#" ? "#" : ".";
    }), "#"];
    if (exit.output && exit.output[1] === logicalIndex + 1) {
      upper[exit.output[0]] = exit.tile;
      lower[exit.output[0]] = exit.tile;
    }
    tiles.push(upper.join(""), lower.join(""));
  }
  tiles.push("#".repeat(WIDTH));

  const enemyStarts = [];
  for (let y = 0; y < logicalRows.length; y += 1) {
    for (let x = 0; x < logicalRows[y].length; x += 1) {
      if (logicalRows[y][x] === "S") {
        enemyStarts.push({ x: x + 1, y: y * 2 + 1 });
      }
    }
  }
  if (enemyStarts.length !== 3) {
    throw new Error(`Imported room has ${enemyStarts.length} nests, expected 3`);
  }

  return {
    tiles,
    start: {
      x: start.sourceX - firstColumn + 1,
      y: (start.arcadeRow - 1) * 2 + 1,
    },
    enemyStarts,
  };
}

function levelOneFromArcade(rows) {
  return importedRoom(rows, {
    firstColumn: 1,
    exit: { source: [25, 9], tile: "D" },
    key: [13, 1],
    spawnPoints: [[16, 2], [10, 4], [26, 5]],
    warpColumns: [11],
    start: { sourceX: 1, arcadeRow: 1 },
  });
}

function mazeTopology(room) {
  return room.tiles.map((row) => row.replace(/[KRD]/g, "."));
}

function placeUniqueKey(room, x, y) {
  room.tiles = room.tiles.map((row) => row.replaceAll("K", "."));
  const row = room.tiles[y];
  if (row[x] !== ".") {
    throw new Error(`Cannot place stage key on ${row[x]} at ${x},${y}`);
  }
  room.tiles[y] = `${row.slice(0, x)}K${row.slice(x + 1)}`;
}

const arcadeSource = fs.readFileSync(arcadeMapsPath, "utf8");
const arcadeRows = new Map(
  [1, 2, 3, 4].map((level) => [level, arcadeRowsFor(arcadeSource, level)]),
);
const gameSource = fs.readFileSync(dataPath, "utf8");
const project = parseGameData(gameSource);
const originalRooms = structuredClone(project.rooms);

const convertedLevelOne = levelOneFromArcade(arcadeRows.get(1));
if (
  JSON.stringify(mazeTopology(convertedLevelOne)) !==
  JSON.stringify(mazeTopology(originalRooms[0]))
) {
  throw new Error("MO5 Room 1 topology no longer matches arcade Level 1");
}

const importedRooms = [
  // Arcade Level 2, left and right halves.
  importedRoom(arcadeRows.get(2), {
    firstColumn: 3,
    exit: { output: [28, 2], tile: "R" },
    key: [18, 1],
    spawnPoints: [[10, 4], [22, 6], [28, 6]],
    warpColumns: [23],
    start: { sourceX: 3, arcadeRow: 9 },
  }),
  importedRoom(arcadeRows.get(2), {
    firstColumn: 31,
    exit: { source: [57, 9], tile: "D" },
    spawnPoints: [[45, 4], [53, 6], [35, 9]],
    warpColumns: [31],
    start: { sourceX: 31, arcadeRow: 2 },
  }),

  // Arcade Level 3, left and right halves.
  importedRoom(arcadeRows.get(3), {
    firstColumn: 3,
    exit: { output: [28, 1], tile: "R" },
    key: [12, 3],
    extraTreasures: [[18, 8]],
    spawnPoints: [[21, 2], [12, 5], [26, 6]],
    warpColumns: [9],
    start: { sourceX: 3, arcadeRow: 9 },
  }),
  importedRoom(arcadeRows.get(3), {
    firstColumn: 31,
    exit: { source: [56, 9], tile: "D" },
    extraTreasures: [[41, 1]],
    spawnPoints: [[53, 2], [36, 6], [44, 6]],
    start: { sourceX: 31, arcadeRow: 1 },
  }),

  // Arcade Level 4, left and right halves. The arcade map has three warp
  // columns; MO5 supports one pair per room, so the central progression pair
  // at the split edge is retained.
  importedRoom(arcadeRows.get(4), {
    firstColumn: 5,
    exit: { output: [28, 1], tile: "R" },
    key: [19, 1],
    spawnPoints: [[30, 4], [12, 6], [21, 7]],
    warpColumns: [30],
    start: { sourceX: 5, arcadeRow: 9 },
  }),
  importedRoom(arcadeRows.get(4), {
    firstColumn: 33,
    exit: { source: [56, 9], tile: "D" },
    spawnPoints: [[46, 1], [40, 2], [46, 5]],
    start: { sourceX: 34, arcadeRow: 9 },
  }),
];

const alreadyImported =
  JSON.stringify(mazeTopology(originalRooms[1])) ===
  JSON.stringify(mazeTopology(importedRooms[0]));
const reusableOriginalRooms = alreadyImported
  ? originalRooms.slice(7, 21)
  : originalRooms.slice(1, 15);

// Original MO5 Rooms 2-3 now form their own stage. Add that stage's key to a
// distant reachable floor cell in its first room without changing maze walls.
placeUniqueKey(reusableOriginalRooms[0], 21, 17);

const campaignRooms = [
  convertedLevelOne,
  ...importedRooms,
  ...reusableOriginalRooms,
];
if (campaignRooms.length !== project.rooms.length) {
  throw new Error(`Campaign has ${campaignRooms.length} rooms, expected 21`);
}

for (let index = 0; index < project.rooms.length; index += 1) {
  const destination = project.rooms[index];
  const source = campaignRooms[index];
  destination.tiles = structuredClone(source.tiles);
  destination.start = structuredClone(source.start);
  destination.enemyStarts = structuredClone(source.enemyStarts);
}

const candidate = serializeProject(gameSource, project);
if (process.argv.includes("--write")) {
  fs.writeFileSync(dataPath, candidate);
  console.log("Imported arcade Levels 2–4 as MO5 Stages 2–4");
} else {
  process.stdout.write(candidate);
}
