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
 *   Pacing      safe horizontal entrance bays, nest reaction distance, smooth
 *              guardian-speed progression, and object-spacing rules.
 *   Topology    rewarded side branches plus turn, junction, cycle, corridor,
 *              and open-square limits for the 12 generated rooms. The arcade
 *              imports and three original reference rooms retain their source
 *              topology while still receiving all progression checks.
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
const minimumTreasureSeparation = 10;
const minimumKeyTreasureSeparation = 10;
const enemyCount = 3;
const mazeMinimumGateTurns = 7;
const mazeMinimumGateBranchCells = 5;
const mazeMinimumCycles = 12;
const mazeMaximumHorizontalRun = 15;
const mazeMaximumOpenSquares = 18;
const spawnMinimumHorizontalLane = 5;
const spawnMinimumNestDistance = 12;
const minimumSpawnerExitDistance = 4;

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
    values.length === totalRoomCount * enemyCount,
    `${label} must contain ${totalRoomCount * enemyCount} entries`,
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
  enemySpeed[0] === 126 && enemySpeed.at(-1) === 162,
  "EnemySpeedByRoom must span 70% to 90% of explorer speed",
);
assert(
  enemySpeed.every(
    (speed, index) => index === 0 || speed > enemySpeed[index - 1],
  ),
  "EnemySpeedByRoom must increase in every room",
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
  // cost, then measure its junctions and the full graph's cycle/open-area shape.
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
  const previous = Array(width * height * 4).fill(-1);
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
        previous[nextState] = state;
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
  const path = [];
  let cursor = gateStates[0];
  while (cursor >= 0) {
    const cell = Math.floor(cursor / 4);
    path.push([cell % width, Math.floor(cell / width)]);
    cursor = previous[cursor];
  }

  let passable = 0;
  let edges = 0;
  let horizontalRun = 0;
  let openSquares = 0;
  for (let y = 0; y < height; y += 1) {
    let run = 0;
    for (let x = 0; x < width; x += 1) {
      if (!open(x, y)) {
        run = 0;
        continue;
      }
      passable += 1;
      run += 1;
      horizontalRun = Math.max(horizontalRun, run);
      edges += directions.filter(([deltaX, deltaY]) =>
        open(x + deltaX, y + deltaY),
      ).length;
      if (
        open(x + 1, y) &&
        open(x, y + 1) &&
        open(x + 1, y + 1)
      ) {
        openSquares += 1;
      }
    }
  }
  const branchCells = path.filter(
    ([x, y]) =>
      directions.filter(([deltaX, deltaY]) =>
        open(x + deltaX, y + deltaY),
      ).length >= 3,
  ).length;

  return {
    turns: turns[gateStates[0]],
    branchCells,
    cycles: edges / 2 - passable + 1,
    horizontalRun,
    openSquares,
  };
}

function unrewardedBranches(rows, physicalStart) {
  // Walk inward from every logical degree-one endpoint until a junction.
  // Optional paths must contain a collectible, gate, warp, or player start.
  const width = 28;
  const height = 10;
  const directions = [
    [1, 0],
    [0, 1],
    [-1, 0],
    [0, -1],
  ];
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
  const neighbors = (x, y) =>
    directions
      .map(([deltaX, deltaY]) => [x + deltaX, y + deltaY])
      .filter(([nextX, nextY]) => open(nextX, nextY));
  const start = [
    physicalStart[0] - 1,
    Math.floor((physicalStart[1] - 1) / 2),
  ];
  const branches = [];
  const seen = new Set();

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (!open(x, y) || neighbors(x, y).length > 1) continue;
      if (seen.has(`${x},${y}`)) continue;

      const path = [];
      let previous;
      let current = [x, y];
      while (current) {
        path.push(current);
        seen.add(current.join(","));
        const next = neighbors(...current).filter(
          ([nextX, nextY]) =>
            !previous ||
            nextX !== previous[0] ||
            nextY !== previous[1],
        );
        if (next.length !== 1) break;
        if (neighbors(...next[0]).length >= 3) break;
        previous = current;
        current = next[0];
      }

      const meaningful = path.some(([pathX, pathY]) => {
        if (pathX === start[0] && pathY === start[1]) return true;
        return "KTVARD".includes(logicalTile(pathX, pathY));
      });
      if (!meaningful) branches.push(path);
    }
  }
  return branches;
}

function unrewardedIsolatedRegions(rows, physicalStart) {
  // Remove each logical cell in turn. Any newly disconnected component without
  // a meaningful objective is an empty side region behind an articulation.
  const width = 28;
  const height = 10;
  const directions = [
    [1, 0],
    [0, 1],
    [-1, 0],
    [0, -1],
  ];
  const logicalTile = (x, y) => {
    const upper = rows[1 + y * 2][1 + x];
    const lower = rows[2 + y * 2][1 + x];
    return upper !== "." ? upper : lower;
  };
  const cellIndex = (x, y) => y * width + x;
  const openCells = [];
  const adjacency = new Map();
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (logicalTile(x, y) === "#") continue;
      const cell = cellIndex(x, y);
      openCells.push(cell);
      adjacency.set(cell, new Set());
    }
  }
  for (const cell of openCells) {
    const x = cell % width;
    const y = Math.floor(cell / width);
    for (const [deltaX, deltaY] of directions) {
      const nextX = x + deltaX;
      const nextY = y + deltaY;
      const next = cellIndex(nextX, nextY);
      if (
        nextX >= 0 &&
        nextX < width &&
        nextY >= 0 &&
        nextY < height &&
        adjacency.has(next)
      ) {
        adjacency.get(cell).add(next);
      }
    }
    const tile = logicalTile(x, y);
    const destinationY = tile === "V" ? 9 : tile === "A" ? 0 : undefined;
    if (destinationY !== undefined) {
      const destination = cellIndex(x, destinationY);
      if (adjacency.has(destination)) {
        adjacency.get(cell).add(destination);
        adjacency.get(destination).add(cell);
      }
    }
  }

  const start = cellIndex(
    physicalStart[0] - 1,
    Math.floor((physicalStart[1] - 1) / 2),
  );
  const meaningful = new Set(
    openCells.filter((cell) => {
      const x = cell % width;
      const y = Math.floor(cell / width);
      return cell === start || "KTVARD".includes(logicalTile(x, y));
    }),
  );
  const componentsWithout = (removed) => {
    const unseen = new Set(
      openCells.filter((cell) => cell !== removed),
    );
    const components = [];
    while (unseen.size) {
      const first = unseen.values().next().value;
      const queue = [first];
      const component = [];
      unseen.delete(first);
      for (let index = 0; index < queue.length; index += 1) {
        const cell = queue[index];
        component.push(cell);
        for (const next of adjacency.get(cell)) {
          if (next !== removed && unseen.delete(next)) queue.push(next);
        }
      }
      components.push(component);
    }
    return components;
  };

  const baselineComponents = componentsWithout(undefined).length;
  const emptyRegions = [];
  for (const removed of openCells) {
    const components = componentsWithout(removed);
    if (components.length <= baselineComponents) continue;
    for (const component of components) {
      if (!component.some((cell) => meaningful.has(cell))) {
        emptyRegions.push({ removed, size: component.length });
      }
    }
  }
  return emptyRegions;
}

function spawnSafety(rows, physicalStart) {
  // Measure the contiguous horizontal firing bay and cardinal graph distance
  // from the explorer's physical start to the nearest logical nest.
  const width = 28;
  const height = 10;
  const directions = [
    [1, 0],
    [0, 1],
    [-1, 0],
    [0, -1],
  ];
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

  let left = start[0];
  let right = start[0];
  while (open(left - 1, start[1])) left -= 1;
  while (open(right + 1, start[1])) right += 1;

  const queue = [start];
  const distances = new Map([[start.join(","), 0]]);
  for (let index = 0; index < queue.length; index += 1) {
    const [x, y] = queue[index];
    const distance = distances.get(`${x},${y}`);
    for (const [deltaX, deltaY] of directions) {
      const nextX = x + deltaX;
      const nextY = y + deltaY;
      const key = `${nextX},${nextY}`;
      if (open(nextX, nextY) && !distances.has(key)) {
        distances.set(key, distance + 1);
        queue.push([nextX, nextY]);
      }
    }
  }

  const nestDistances = [];
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (logicalTile(x, y) !== "S") continue;
      const distance = distances.get(`${x},${y}`);
      if (distance !== undefined) nestDistances.push(distance);
    }
  }
  return {
    horizontalLane: right - left + 1,
    horizontalExit:
      open(start[0] - 1, start[1]) || open(start[0] + 1, start[1]),
    nearestNest: Math.min(...nestDistances),
    startsOnFloor: logicalTile(...start) === ".",
  };
}

maps.forEach((rows, roomIndex) => {
  // Resolve the flattened room through the variable-size stage boundaries.
  const name = mapNames[roomIndex];
  const isReferenceRoom = roomIndex === 0;
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
  if (!isReferenceRoom && !isArcadeImport) {
    assert(
      safety.horizontalLane >= spawnMinimumHorizontalLane,
      `${name} spawn firing lane is only ${safety.horizontalLane} cells long`,
    );
  }
  assert(
    safety.nearestNest >= (isArcadeImport ? 8 : spawnMinimumNestDistance),
    `${name} nearest nest is only ${safety.nearestNest} cells from spawn`,
  );

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
  for (const tile of ["K", "S"]) {
    for (const position of positions(rows, tile)) {
      const minimumDistance =
        tile === "S" ? minimumSpawnerExitDistance : 2;
      assert(
        gates.every(
          ([gateX, gateY]) =>
            Math.max(
              Math.abs(position[0] - gateX),
              Math.abs(position[1] - gateY),
            ) >= minimumDistance,
        ),
        `${name} contains ${tile} too close to its exit`,
      );
    }
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
  const emptyBranches = unrewardedBranches(rows, start);
  const emptyRegions = unrewardedIsolatedRegions(rows, start);
  if (!isReferenceRoom && !isArcadeImport) {
    assert(
      emptyBranches.length === 0,
      `${name} contains ${emptyBranches.length} unrewarded cul-de-sac branches`,
    );
    assert(
      emptyRegions.length === 0,
      `${name} contains ${emptyRegions.length} unrewarded isolated regions`,
    );
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
      quality.branchCells >= mazeMinimumGateBranchCells,
      `${name} gate route has too few junctions`,
    );
    assert(
      quality.cycles >= mazeMinimumCycles,
      `${name} has too few alternate-path loops`,
    );
    assert(
      quality.horizontalRun <= mazeMaximumHorizontalRun,
      `${name} has an overlong open corridor`,
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
  for (let first = 0; first < treasures.length; first += 1) {
    for (let second = first + 1; second < treasures.length; second += 1) {
      const [firstX, firstY] = treasures[first];
      const [secondX, secondY] = treasures[second];
      const separation =
        Math.abs(firstX - secondX) + Math.abs(firstY - secondY);
      assert(
        separation >= (isArcadeImport ? 2 : minimumTreasureSeparation),
        `${name} contains treasures that are too close together`,
      );
    }
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
  for (let actor = 0; actor < enemyCount; actor += 1) {
    const tableIndex = roomIndex * enemyCount + actor;
    assert(
      rows[enemyY[tableIndex]][enemyX[tableIndex]] === "S",
      `${name} enemy ${actor} does not start on a nest`,
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
    totalRoomCount * enemyCount
  } guardian starts; arcade imports and reference rooms preserved, with ` +
    `generated-maze quality checked in the final ${totalRoomCount - 9} rooms`,
);
