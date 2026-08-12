#!/usr/bin/env node

import fs from "node:fs";

/*
 * Static content validator for the 9-stage, 21-room campaign.
 *
 * It parses the human-readable FCC room templates and the parallel FCB/FDB
 * metadata directly from src/game/data.asm. Checks cover four layers:
 *
 *   Shape      30x22 bounds, legal tile alphabet, closed top/bottom edges,
 *              unique rooms, and exact flattened table sizes.
 *   Playability reachability before/after gates, safe key/exit routes that do
 *              not require stepping on a guardian nest, usable warp endpoints,
 *              and actor starts that match S tiles.
 *   Pacing      horizontal spawn exits, the fixed guardian-speed
 *              setting, and object-spacing rules.
 *   Topology    turn and open-square limits for the 12 generated
 *              rooms. The arcade imports and three original reference rooms
 *              retain their source topology while still receiving all
 *              progression checks.
 *
 * The validator models the vertically doubled source as a 28x10 logical
 * interior for topology metrics, but uses all 30x22 physical cells for exact
 * placement and reachability.
 */
const sourcePath = process.argv[2];
if (!sourcePath) {
  throw new Error("usage: validate-content.mjs <game-data.asm>");
}

const source = fs.readFileSync(sourcePath, "utf8");
const minimumKeyTreasureSeparation = 10;
const enemySpawnCount = 3;
const mazeMinimumGateTurns = 7;
const mazeMaximumOpenSquares = 18;

function blockFor(label) {
  // Extract the source owned by a global assembly label. All parsed tables use
  // simple FCB/FCC/FDB lines so the build remains independent of an assembler.
  const marker = `${label}:`;
  const start = source.indexOf(marker);
  if (start < 0) {
    throw new Error(`missing data label ${label}`);
  }
  const rest = source.slice(start + marker.length);
  const next = rest.search(/^[A-Za-z_][A-Za-z0-9_]*:/m);
  return next < 0 ? rest : rest.slice(0, next);
}

function fccRows(label) {
  return [...blockFor(label).matchAll(/^\s*fcc\s+"([^"]*)"/gm)].map(
    (match) => match[1],
  );
}

function fcbValues(label) {
  return [...blockFor(label).matchAll(/^\s*fcb\s+(.+)$/gm)].flatMap((match) =>
    match[1].split(",").map((value) => {
      const token = value.trim();
      if (token === "$FF") return -1;
      const parsed = Number.parseInt(token, 10);
      if (!Number.isInteger(parsed)) {
        throw new Error(`${label} contains non-decimal value ${token}`);
      }
      return parsed;
    }),
  );
}

function tableEntries(label, directive) {
  const expression = new RegExp(`^\\s*${directive}\\s+(.+)$`, "gm");
  return [...blockFor(label).matchAll(expression)].flatMap((match) =>
    match[1].split(",").map((value) => value.trim()),
  );
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const stageRoomOffsets = fcbValues("StageRoomOffsets");
const stageRoomCounts = fcbValues("StageRoomCounts");
const stageCount = stageRoomCounts.length;
const totalRoomCount = stageRoomCounts.reduce((total, count) => total + count, 0);
const mapNames = tableEntries("RoomTemplatePointers", "fdb");

assert(stageCount === 9, `StageRoomCounts must define 9 stages`);
assert(
  JSON.stringify(stageRoomCounts) === JSON.stringify([1, 2, 2, 2, 2, 3, 3, 3, 3]),
  "StageRoomCounts must match the requested 1/2/2/2/2/3/3/3/3 structure",
);
assert(
  stageRoomOffsets.length === stageCount,
  "StageRoomOffsets must contain one entry per stage",
);
let expectedOffset = 0;
for (let stage = 0; stage < stageCount; stage += 1) {
  assert(
    stageRoomOffsets[stage] === expectedOffset,
    `StageRoomOffsets has an invalid Stage ${stage + 1} offset`,
  );
  expectedOffset += stageRoomCounts[stage];
}
assert(totalRoomCount === 21, "Stage room counts must total 21 rooms");

const maps = mapNames.map((name) => {
  const rows = fccRows(name);
  assert(rows.length === 22, `${name} has ${rows.length} rows, expected 22`);
  rows.forEach((row, index) => {
    assert(
      row.length === 30,
      `${name} row ${index} has ${row.length} cells, expected 30`,
    );
    assert(
      /^[#.KTSVARD]+$/.test(row),
      `${name} row ${index} contains an unknown tile`,
    );
  });
  assert(/^#+$/.test(rows[0]), `${name} top edge must be closed`);
  assert(/^#+$/.test(rows[21]), `${name} bottom edge must be closed`);
  return rows;
});

const startX = fcbValues("RoomPlayerStartX");
const startY = fcbValues("RoomPlayerStartY");
const enemyX = fcbValues("EnemyInitialX");
const enemyY = fcbValues("EnemyInitialY");
const enemyDirection = fcbValues("EnemyInitialDirection");
const enemyTimer = fcbValues("EnemyInitialAnimationTimer");
const enemyFrame = fcbValues("EnemyInitialAnimationFrame");
const enemySpeed = fcbValues("EnemySpeedByRoom");

assert(
  startX.length === totalRoomCount,
  `RoomPlayerStartX must contain ${totalRoomCount} entries`,
);
assert(
  startY.length === totalRoomCount,
  `RoomPlayerStartY must contain ${totalRoomCount} entries`,
);
for (const [label, values] of [
  ["EnemyInitialX", enemyX],
  ["EnemyInitialY", enemyY],
  ["EnemyInitialDirection", enemyDirection],
  ["EnemyInitialAnimationTimer", enemyTimer],
  ["EnemyInitialAnimationFrame", enemyFrame],
]) {
  assert(
    values.length === totalRoomCount * enemySpawnCount,
    `${label} must contain ${totalRoomCount * enemySpawnCount} entries`,
  );
}
assert(
  tableEntries("RoomTemplatePointers", "fdb").length === totalRoomCount,
  `RoomTemplatePointers must contain ${totalRoomCount} entries`,
);
assert(
  tableEntries("RoomWallColors", "fcb").length === totalRoomCount,
  `RoomWallColors must contain ${totalRoomCount} entries`,
);
assert(
  enemySpeed.length === totalRoomCount,
  `EnemySpeedByRoom must contain ${totalRoomCount} entries`,
);
assert(
  enemySpeed.every((speed) => speed === 126),
  "EnemySpeedByRoom must remain at 70% while speed progression is disabled",
);
assert(
  new Set(maps.map((rows) => rows.join("\n"))).size === maps.length,
  "room maps must be unique",
);

function positions(rows, tile) {
  const result = [];
  rows.forEach((row, y) => {
    for (let x = 0; x < row.length; x += 1) {
      if (row[x] === tile) result.push([x, y]);
    }
  });
  return result;
}

function reachable(rows, start, blockGates = false, blockedTiles = "") {
  // Breadth-first physical-cell reachability. V/A are directed vertical warp
  // edges to the fixed lower/upper destination rows used by game logic.
  const queue = [start];
  const visited = new Set([start.join(",")]);
  for (let index = 0; index < queue.length; index += 1) {
    const [x, y] = queue[index];
    const tile = rows[y][x];
    const next =
      tile === "V"
        ? [[x, 19]]
        : tile === "A"
          ? [[x, 2]]
          : [
              [x + 1, y],
              [x - 1, y],
              [x, y + 1],
              [x, y - 1],
            ];
    for (const [nextX, nextY] of next) {
      if (nextX < 0 || nextX >= 30 || nextY < 0 || nextY >= 22) continue;
      const nextTile = rows[nextY][nextX];
      if (
        nextTile === "#" ||
        (blockGates && "RD".includes(nextTile)) ||
        blockedTiles.includes(nextTile)
      ) {
        continue;
      }
      const key = `${nextX},${nextY}`;
      if (!visited.has(key)) {
        visited.add(key);
        queue.push([nextX, nextY]);
      }
    }
  }
  return visited;
}

function warpDestinationHasExit(rows, x, y, reverseWarpTile) {
  return [
    [x + 1, y],
    [x - 1, y],
    [x, y + 1],
    [x, y - 1],
  ].some(([nextX, nextY]) => {
    if (nextX < 0 || nextX >= 30 || nextY < 0 || nextY >= 22) return false;
    const tile = rows[nextY][nextX];
    return tile !== "#" && tile !== reverseWarpTile;
  });
}

function mazeQuality(rows, physicalStart) {
  // Find the shortest logical gate route while minimizing turns as a secondary
  // cost, then measure the full graph's open-area shape.
  const width = 28;
  const height = 10;
  const directions = [
    [1, 0],
    [0, 1],
    [-1, 0],
    [0, -1],
  ];
  const logicalTile = (x, y) => rows[1 + y * 2][1 + x];
  const open = (x, y) =>
    x >= 0 &&
    x < width &&
    y >= 0 &&
    y < height &&
    logicalTile(x, y) !== "#";
  const start = [
    physicalStart[0] - 1,
    Math.floor((physicalStart[1] - 1) / 2),
  ];
  let gate;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if ("RD".includes(logicalTile(x, y))) gate = [x, y];
    }
  }

  const cellIndex = (x, y) => y * width + x;
  const distances = Array(width * height * 4).fill(Infinity);
  const turns = Array(width * height * 4).fill(Infinity);
  const queue = [];
  for (let direction = 0; direction < 4; direction += 1) {
    const state = cellIndex(...start) * 4 + direction;
    distances[state] = 0;
    turns[state] = 0;
    queue.push(state);
  }

  while (queue.length) {
    queue.sort(
      (first, second) =>
        distances[first] - distances[second] || turns[first] - turns[second],
    );
    const state = queue.shift();
    const cell = Math.floor(state / 4);
    const direction = state % 4;
    const x = cell % width;
    const y = Math.floor(cell / width);
    for (let nextDirection = 0; nextDirection < 4; nextDirection += 1) {
      const [deltaX, deltaY] = directions[nextDirection];
      const nextX = x + deltaX;
      const nextY = y + deltaY;
      if (!open(nextX, nextY)) continue;
      const nextState =
        cellIndex(nextX, nextY) * 4 + nextDirection;
      const nextDistance = distances[state] + 1;
      const nextTurns = turns[state] + (nextDirection !== direction);
      if (
        nextDistance < distances[nextState] ||
        (nextDistance === distances[nextState] &&
          nextTurns < turns[nextState])
      ) {
        distances[nextState] = nextDistance;
        turns[nextState] = nextTurns;
        queue.push(nextState);
      }
    }
  }

  const gateStates = [0, 1, 2, 3]
    .map((direction) => cellIndex(...gate) * 4 + direction)
    .sort(
      (first, second) =>
        distances[first] - distances[second] || turns[first] - turns[second],
    );
  let openSquares = 0;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (
        open(x, y) &&
        open(x + 1, y) &&
        open(x, y + 1) &&
        open(x + 1, y + 1)
      ) {
        openSquares += 1;
      }
    }
  }
  return {
    turns: turns[gateStates[0]],
    openSquares,
  };
}

function spawnSafety(rows, physicalStart) {
  // Require clear floor and a horizontal escape from the explorer's start.
  const width = 28;
  const height = 10;
  const logicalTile = (x, y) => {
    const upper = rows[1 + y * 2][1 + x];
    const lower = rows[2 + y * 2][1 + x];
    return upper !== "." ? upper : lower;
  };
  const open = (x, y) =>
    x >= 0 &&
    x < width &&
    y >= 0 &&
    y < height &&
    logicalTile(x, y) !== "#";
  const start = [
    physicalStart[0] - 1,
    Math.floor((physicalStart[1] - 1) / 2),
  ];

  return {
    horizontalExit:
      open(start[0] - 1, start[1]) || open(start[0] + 1, start[1]),
    startsOnFloor: logicalTile(...start) === ".",
  };
}

maps.forEach((rows, roomIndex) => {
  // Resolve the flattened room through the variable-size stage boundaries.
  const name = mapNames[roomIndex];
  const isArcadeImport = roomIndex >= 1 && roomIndex <= 6;
  let stageIndex = 0;
  while (
    stageIndex + 1 < stageCount &&
    stageRoomOffsets[stageIndex + 1] <= roomIndex
  ) {
    stageIndex += 1;
  }
  const roomWithinStage = roomIndex - stageRoomOffsets[stageIndex];
  const isFinalRoom = roomWithinStage === stageRoomCounts[stageIndex] - 1;
  const start = [startX[roomIndex], startY[roomIndex]];
  assert(rows[start[1]][start[0]] !== "#", `${name} player start is blocked`);
  const safety = spawnSafety(rows, start);
  assert(safety.startsOnFloor, `${name} player must start on clear floor`);
  assert(safety.horizontalExit, `${name} player starts in a vertical corridor`);
  const keys = positions(rows, "K");
  assert(
    keys.length === (roomWithinStage === 0 ? 1 : 0),
    `${name} has an invalid key count`,
  );
  const beforeGate = reachable(rows, start, true);
  if (keys.length) {
    assert(beforeGate.has(keys[0].join(",")), `${name} key is unreachable`);
  }

  const gateTile = isFinalRoom ? "D" : "R";
  const gates = positions(rows, gateTile);
  assert(gates.length === 2, `${name} must contain a two-cell ${gateTile} gate`);
  for (const position of positions(rows, "K")) {
    assert(
      gates.every(
        ([gateX, gateY]) =>
          Math.max(
            Math.abs(position[0] - gateX),
            Math.abs(position[1] - gateY),
          ) >= 2,
      ),
      `${name} contains K too close to its exit`,
    );
  }
  const fullReach = reachable(rows, start);
  assert(
    gates.some((position) => fullReach.has(position.join(","))),
    `${name} gate is unreachable`,
  );
  const safeFromStart = reachable(rows, start, keys.length > 0, "S");
  if (keys.length) {
    assert(
      safeFromStart.has(keys[0].join(",")),
      `${name} forces the explorer through a spawner to reach its key`,
    );
  }
  const safeToGate = keys.length
    ? reachable(rows, keys[0], false, "S")
    : safeFromStart;
  assert(
    gates.some((position) => safeToGate.has(position.join(","))),
    `${name} forces the explorer through a spawner to reach its exit`,
  );
  // This legacy room intentionally permits disconnected decorative floor.
  if (name !== "StageThreeRoomThreeTemplate") {
    for (let y = 0; y < 22; y += 1) {
      for (let x = 0; x < 30; x += 1) {
        const tile = rows[y][x];
        assert(
          tile === "#" ||
            fullReach.has(`${x},${y}`) ||
            "VA".includes(tile),
          `${name} contains unreachable open floor at ${x},${y}`,
        );
      }
    }
  }
  // Rooms 2-7 are faithful arcade imports, while Rooms 8-9 reuse the two
  // remaining hand-authored Stage 1 reference rooms. Generated-maze style
  // metrics begin with Room 10; progression and reachability still apply to
  // every room.
  if (roomIndex >= 9) {
    const quality = mazeQuality(rows, start);
    assert(
      quality.turns >= mazeMinimumGateTurns,
      `${name} gate route is too straight (${quality.turns} turns)`,
    );
    assert(
      quality.openSquares <= mazeMaximumOpenSquares,
      `${name} contains too much open floor`,
    );
  }

  const treasures = positions(rows, "T");
  assert(
    treasures.length >= 3 && treasures.length <= 4,
    `${name} must contain 3 or 4 treasures`,
  );
  for (const [treasureX, treasureY] of treasures) {
    const separation =
      Math.abs(treasureX - start[0]) +
      Math.abs(treasureY - start[1]);
    assert(
      separation > 1,
      `${name} contains a treasure directly adjacent to the player start`,
    );
  }
  for (const [keyX, keyY] of keys) {
    for (const [treasureX, treasureY] of treasures) {
      const separation =
        Math.abs(keyX - treasureX) + Math.abs(keyY - treasureY);
      assert(
        separation >= (isArcadeImport ? 4 : minimumKeyTreasureSeparation),
        `${name} contains a treasure that is too close to its key`,
      );
    }
  }
  for (const [treasureX, treasureY] of treasures) {
    for (const [spawnerX, spawnerY] of positions(rows, "S")) {
      const separation =
        Math.max(
          Math.abs(treasureX - spawnerX),
          Math.abs(treasureY - spawnerY),
        );
      assert(
        separation > 1,
        `${name} contains a treasure without a clear cell from a spawner`,
      );
    }
  }
  assert(positions(rows, "S").length === 6, `${name} must contain three nests`);
  for (const [tile, tilePositions, reachableCells] of [
    ["T", treasures, beforeGate],
    ["S", positions(rows, "S"), fullReach],
  ]) {
    for (const position of tilePositions) {
      assert(
        reachableCells.has(position.join(",")),
        `${name} contains an unreachable ${tile} tile`,
      );
    }
  }
  for (let spawnIndex = 0; spawnIndex < enemySpawnCount; spawnIndex += 1) {
    const tableIndex = roomIndex * enemySpawnCount + spawnIndex;
    assert(
      rows[enemyY[tableIndex]][enemyX[tableIndex]] === "S",
      `${name} guardian spawn ${spawnIndex} does not start on a nest`,
    );
  }

  const warpDown = positions(rows, "V");
  const warpUp = positions(rows, "A");
  const teleporterTiles = [...warpDown, ...warpUp];
  for (const [spawnerX, spawnerY] of positions(rows, "S")) {
    for (const [teleporterX, teleporterY] of teleporterTiles) {
      const deltaX = Math.abs(spawnerX - teleporterX);
      const deltaY = Math.abs(spawnerY - teleporterY);
      assert(
        Math.max(deltaX, deltaY) > 1 &&
          ((deltaX !== 0 && deltaY !== 0) || deltaX + deltaY > 2),
        `${name} contains a spawner directly adjacent to a teleporter`,
      );
    }
  }
  assert(warpDown.length === warpUp.length, `${name} warp pair is incomplete`);
  assert(
    warpDown.length === 0 || warpDown.length === 2,
    `${name} must use a two-cell warp pair`,
  );
  if (warpDown.length) {
    assert(
      warpDown.some((position) => fullReach.has(position.join(","))),
      `${name} downward warp is unreachable`,
    );
    assert(
      warpUp.some((position) => fullReach.has(position.join(","))),
      `${name} upward warp is unreachable`,
    );
  }
  for (const [x] of warpDown) {
    assert(rows[19][x] !== "#", `${name} lower warp destination is blocked`);
    assert(
      warpDestinationHasExit(rows, x, 19, "A"),
      `${name} lower warp destination has no escape`,
    );
  }
  for (const [x] of warpUp) {
    assert(rows[2][x] !== "#", `${name} upper warp destination is blocked`);
    assert(
      warpDestinationHasExit(rows, x, 2, "V"),
      `${name} upper warp destination has no escape`,
    );
  }
});

console.log(
  `Validated ${stageCount} stages, ${totalRoomCount} rooms, and ${
    totalRoomCount * enemySpawnCount
  } guardian starts; arcade imports and reference rooms preserved, with ` +
    `generated-maze quality checked in the final ${totalRoomCount - 9} rooms`,
);
