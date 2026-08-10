const WIDTH = 30;
const HEIGHT = 22;
const ENEMY_SPAWN_COUNT = 3;
const TILE_PATTERN = /^[#.KTSVARD]+$/;

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function blockBounds(source, label) {
  const marker = new RegExp(`^${escapeRegExp(label)}:`, "m");
  const match = marker.exec(source);
  if (!match) throw new Error(`Missing data label ${label}`);

  const contentStart = match.index + match[0].length;
  const rest = source.slice(contentStart);
  const nextLabel = /^[A-Za-z_][A-Za-z0-9_]*:/m.exec(rest);
  return {
    start: contentStart,
    end: nextLabel ? contentStart + nextLabel.index : source.length,
  };
}

function blockFor(source, label) {
  const { start, end } = blockBounds(source, label);
  return source.slice(start, end);
}

function directiveEntries(source, label, directive) {
  const expression = new RegExp(`^\\s*${directive}\\s+(.+)$`, "gm");
  return [...blockFor(source, label).matchAll(expression)].flatMap((match) =>
    match[1].split(",").map((value) => value.trim()),
  );
}

function numericFcbValues(source, label) {
  return directiveEntries(source, label, "fcb").map((token) => {
    if (/^\$[0-9a-f]+$/i.test(token)) {
      const value = Number.parseInt(token.slice(1), 16);
      return value === 0xff ? -1 : value;
    }
    const value = Number.parseInt(token, 10);
    if (!Number.isInteger(value)) {
      throw new Error(`${label} contains a non-numeric value: ${token}`);
    }
    return value;
  });
}

function templateRows(source, label) {
  return [
    ...blockFor(source, label).matchAll(/^\s*fcc\s+"([^"]*)"/gm),
  ].map((match) => match[1]);
}

function roomName(index, stageRoomOffsets, stageRoomCounts) {
  let stageIndex = 0;
  while (
    stageIndex + 1 < stageRoomCounts.length &&
    stageRoomOffsets[stageIndex + 1] <= index
  ) {
    stageIndex += 1;
  }
  const stage = stageIndex + 1;
  const room = index - stageRoomOffsets[stageIndex] + 1;
  return { stage, room, name: `Stage ${stage}, Room ${room}` };
}

export function parseGameData(source) {
  const labels = directiveEntries(source, "RoomTemplatePointers", "fdb");
  const startX = numericFcbValues(source, "RoomPlayerStartX");
  const startY = numericFcbValues(source, "RoomPlayerStartY");
  const enemyX = numericFcbValues(source, "EnemyInitialX");
  const enemyY = numericFcbValues(source, "EnemyInitialY");
  const wallColors = directiveEntries(source, "RoomWallColors", "fcb");
  const stageRoomOffsets = numericFcbValues(source, "StageRoomOffsets");
  const stageRoomCounts = numericFcbValues(source, "StageRoomCounts");

  if (stageRoomOffsets.length !== stageRoomCounts.length) {
    throw new Error("Stage room offset/count tables do not match");
  }
  let expectedOffset = 0;
  stageRoomCounts.forEach((count, stageIndex) => {
    if (count < 1 || count > 3 || stageRoomOffsets[stageIndex] !== expectedOffset) {
      throw new Error(`Stage ${stageIndex + 1} has invalid room boundaries`);
    }
    expectedOffset += count;
  });
  if (expectedOffset !== labels.length) {
    throw new Error("Stage room counts do not match the room count");
  }

  if (startX.length !== labels.length || startY.length !== labels.length) {
    throw new Error("Player start tables do not match the room count");
  }
  if (
    enemyX.length !== labels.length * ENEMY_SPAWN_COUNT ||
    enemyY.length !== labels.length * ENEMY_SPAWN_COUNT
  ) {
    throw new Error("Guardian start tables do not match the room count");
  }

  const rooms = labels.map((label, index) => {
    const identity = roomName(index, stageRoomOffsets, stageRoomCounts);
    const enemyOffset = index * ENEMY_SPAWN_COUNT;
    return {
      id: label,
      ...identity,
      tiles: templateRows(source, label),
      start: { x: startX[index], y: startY[index] },
      enemyStarts: Array.from({ length: ENEMY_SPAWN_COUNT }, (_, enemyIndex) => ({
        x: enemyX[enemyOffset + enemyIndex],
        y: enemyY[enemyOffset + enemyIndex],
      })),
      wallColor: wallColors[index] ?? "COLOR_WALL_ROOM_ONE",
    };
  });

  const project = {
    formatVersion: 1,
    width: WIDTH,
    height: HEIGHT,
    stageRoomCounts,
    rooms,
  };
  validateProjectShape(project, labels);
  return project;
}

export function validateProjectShape(project, expectedLabels = undefined) {
  if (!project || project.formatVersion !== 1) {
    throw new Error("Unsupported or missing editor project version");
  }
  if (project.width !== WIDTH || project.height !== HEIGHT) {
    throw new Error(`Rooms must be ${WIDTH}×${HEIGHT} cells`);
  }
  if (!Array.isArray(project.rooms) || project.rooms.length === 0) {
    throw new Error("The project has no rooms");
  }
  if (
    !Array.isArray(project.stageRoomCounts) ||
    project.stageRoomCounts.length === 0 ||
    project.stageRoomCounts.some(
      (count) => !Number.isInteger(count) || count < 1 || count > 3,
    ) ||
    project.stageRoomCounts.reduce((total, count) => total + count, 0) !==
      project.rooms.length
  ) {
    throw new Error("The project has invalid stage room counts");
  }
  if (
    expectedLabels &&
    (project.rooms.length !== expectedLabels.length ||
      project.rooms.some((room, index) => room.id !== expectedLabels[index]))
  ) {
    throw new Error("Room labels or ordering do not match the assembly source");
  }

  const seen = new Set();
  for (const room of project.rooms) {
    if (typeof room.id !== "string" || !room.id || seen.has(room.id)) {
      throw new Error("Every room must have a unique source label");
    }
    seen.add(room.id);
    if (!Array.isArray(room.tiles) || room.tiles.length !== HEIGHT) {
      throw new Error(`${room.id} must have ${HEIGHT} rows`);
    }
    room.tiles.forEach((row, rowIndex) => {
      if (typeof row !== "string" || row.length !== WIDTH) {
        throw new Error(`${room.id} row ${rowIndex} must be ${WIDTH} cells wide`);
      }
      if (!TILE_PATTERN.test(row)) {
        throw new Error(`${room.id} row ${rowIndex} contains an unknown tile`);
      }
    });
    for (const [label, point] of [
      ["player start", room.start],
      ...((room.enemyStarts ?? []).map((point, index) => [
        `guardian ${index + 1} start`,
        point,
      ])),
    ]) {
      if (
        !point ||
        !Number.isInteger(point.x) ||
        !Number.isInteger(point.y) ||
        point.x < 0 ||
        point.x >= WIDTH ||
        point.y < 0 ||
        point.y >= HEIGHT
      ) {
        throw new Error(`${room.id} has an invalid ${label}`);
      }
    }
    if (
      !Array.isArray(room.enemyStarts) ||
      room.enemyStarts.length !== ENEMY_SPAWN_COUNT
    ) {
      throw new Error(
        `${room.id} must have exactly ${ENEMY_SPAWN_COUNT} guardian starts`,
      );
    }
  }
  return project;
}

function replaceTemplateRows(source, label, rows) {
  const bounds = blockBounds(source, label);
  const block = source.slice(bounds.start, bounds.end);
  const rowPattern = /^[ \t]*fcc[ \t]+"[^"]*"[^\r\n]*(?:\r?\n|$)/gm;
  const matches = [...block.matchAll(rowPattern)];
  if (matches.length !== HEIGHT) {
    throw new Error(`${label} does not contain ${HEIGHT} editable rows`);
  }
  const first = matches[0].index;
  const last = matches.at(-1);
  const afterLast = last.index + last[0].length;
  const replacement = rows
    .map((row) => `        fcc     "${row}"`)
    .join("\n") + "\n";
  const updatedBlock =
    block.slice(0, first) + replacement + block.slice(afterLast);
  return (
    source.slice(0, bounds.start) +
    updatedBlock +
    source.slice(bounds.end)
  );
}

function replaceFcbValues(source, label, values, valuesPerLine) {
  const bounds = blockBounds(source, label);
  const block = source.slice(bounds.start, bounds.end);
  const linePattern = /^[ \t]*fcb[ \t]+.+(?:\r?\n|$)/gm;
  const matches = [...block.matchAll(linePattern)];
  if (!matches.length) throw new Error(`${label} has no FCB values`);

  const lines = [];
  for (let index = 0; index < values.length; index += valuesPerLine) {
    lines.push(
      `        fcb     ${values.slice(index, index + valuesPerLine).join(",")}`,
    );
  }
  const first = matches[0].index;
  const last = matches.at(-1);
  const afterLast = last.index + last[0].length;
  const replacement = `${lines.join("\n")}\n`;
  const updatedBlock =
    block.slice(0, first) + replacement + block.slice(afterLast);
  return (
    source.slice(0, bounds.start) +
    updatedBlock +
    source.slice(bounds.end)
  );
}

export function serializeProject(source, project) {
  const expectedLabels = directiveEntries(
    source,
    "RoomTemplatePointers",
    "fdb",
  );
  validateProjectShape(project, expectedLabels);
  const expectedStageRoomCounts = numericFcbValues(source, "StageRoomCounts");
  if (
    JSON.stringify(project.stageRoomCounts) !==
    JSON.stringify(expectedStageRoomCounts)
  ) {
    throw new Error("Stage structure does not match the assembly source");
  }

  let updated = source;
  for (const room of project.rooms) {
    updated = replaceTemplateRows(updated, room.id, room.tiles);
  }

  updated = replaceFcbValues(
    updated,
    "RoomPlayerStartX",
    project.rooms.map((room) => room.start.x),
    3,
  );
  updated = replaceFcbValues(
    updated,
    "RoomPlayerStartY",
    project.rooms.map((room) => room.start.y),
    3,
  );
  updated = replaceFcbValues(
    updated,
    "EnemyInitialX",
    project.rooms.flatMap((room) => room.enemyStarts.map((point) => point.x)),
    3,
  );
  updated = replaceFcbValues(
    updated,
    "EnemyInitialY",
    project.rooms.flatMap((room) => room.enemyStarts.map((point) => point.y)),
    3,
  );
  return updated;
}

export const LEVEL_DIMENSIONS = Object.freeze({
  width: WIDTH,
  height: HEIGHT,
  enemyCount: ENEMY_SPAWN_COUNT,
});
