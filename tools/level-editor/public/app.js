import { doorCells, exitTileFor } from "./room-art.mjs";

const WIDTH = 30;
const HEIGHT = 22;
const CELL = 32;
const PAIRED_TILES = new Set(["S", "V", "A", "R", "D"]);

const toolDefinitions = {
  move: { shortcut: "M", hint: "Choose an object, then click its new cell." },
  wall: { shortcut: "1", hint: "Drag to paint walls. Right-click to erase." },
  floor: { shortcut: "2", hint: "Drag to clear cells back to walkable floor." },
  treasure: { shortcut: "T", hint: "Click to place a treasure. Each room needs 3." },
  key: { shortcut: "K", hint: "Click to move the unique chamber key into this room." },
  spawner: { shortcut: "S", hint: "Click to place a two-cell nest. Each room needs 3." },
  warpDown: { shortcut: "V", hint: "Place the upper, downward warp endpoint." },
  warpUp: { shortcut: "A", hint: "Place the lower, upward warp endpoint." },
  exit: { shortcut: "E", hint: "Place the two-cell room gate or final chamber door." },
  start: { shortcut: "P", hint: "Click a clear floor cell for the player start." },
};

const state = {
  project: null,
  baseline: null,
  revision: "",
  currentStage: 0,
  currentRoom: 0,
  activeTool: "wall",
  selectedObject: null,
  hover: null,
  pointerDown: false,
  pointerTool: null,
  pendingEdit: null,
  lastPaintKey: "",
  history: [],
  future: [],
  busy: false,
};

const elements = {
  canvas: document.querySelector("#mazeCanvas"),
  canvasEmpty: document.querySelector("#canvasEmpty"),
  checkList: document.querySelector("#checkList"),
  connectionDot: document.querySelector("#connectionDot"),
  coordinateReadout: document.querySelector("#coordinateReadout"),
  documentStatus: document.querySelector("#documentStatus"),
  editorLayout: document.querySelector("#editorLayout"),
  exportButton: document.querySelector("#exportButton"),
  healthBadge: document.querySelector("#healthBadge"),
  importInput: document.querySelector("#importInput"),
  objectList: document.querySelector("#objectList"),
  pairRows: document.querySelector("#pairRows"),
  redoButton: document.querySelector("#redoButton"),
  resetRoomButton: document.querySelector("#resetRoomButton"),
  roomBreadcrumb: document.querySelector("#roomBreadcrumb"),
  roomTabs: document.querySelector("#roomTabs"),
  roomTitle: document.querySelector("#roomTitle"),
  saveButton: document.querySelector("#saveButton"),
  sourcePath: document.querySelector("#sourcePath"),
  stageList: document.querySelector("#stageList"),
  toastRegion: document.querySelector("#toastRegion"),
  toolHint: document.querySelector("#toolHint"),
  activeShortcut: document.querySelector("#activeShortcut"),
  undoButton: document.querySelector("#undoButton"),
  validateButton: document.querySelector("#validateButton"),
  validationIcon: document.querySelector("#validationIcon"),
  validationMessage: document.querySelector("#validationMessage"),
  validationPanel: document.querySelector("#validationPanel"),
  validationTitle: document.querySelector("#validationTitle"),
};

const context = elements.canvas.getContext("2d");

function clone(value) {
  return structuredClone(value);
}

function currentIndex() {
  return (
    state.project.stageRoomCounts
      .slice(0, state.currentStage)
      .reduce((total, count) => total + count, 0) + state.currentRoom
  );
}

function stageOffset(stage) {
  return state.project.stageRoomCounts
    .slice(0, stage)
    .reduce((total, count) => total + count, 0);
}

function currentRoom() {
  return state.project.rooms[currentIndex()];
}

function roomAt(index) {
  return state.project.rooms[index];
}

function editableRoom(room) {
  return {
    tiles: room.tiles,
    start: room.start,
    enemyStarts: room.enemyStarts,
  };
}

function roomsEqual(first, second) {
  return JSON.stringify(editableRoom(first)) === JSON.stringify(editableRoom(second));
}

function dirtyRoomIndexes() {
  if (!state.project || !state.baseline) return [];
  return state.project.rooms
    .map((room, index) => (roomsEqual(room, state.baseline.rooms[index]) ? -1 : index))
    .filter((index) => index >= 0);
}

function isDirty() {
  return dirtyRoomIndexes().length > 0;
}

function cellAt(room, x, y) {
  return room.tiles[y][x];
}

function setCell(room, x, y, tile) {
  if (cellAt(room, x, y) === tile) return false;
  const row = room.tiles[y];
  room.tiles[y] = `${row.slice(0, x)}${tile}${row.slice(x + 1)}`;
  return true;
}

function pairedTop(y) {
  if (y <= 0 || y >= HEIGHT - 1) return y;
  return y % 2 === 1 ? y : y - 1;
}

function positionsOf(room, tile) {
  const positions = [];
  for (let y = 0; y < HEIGHT; y += 1) {
    for (let x = 0; x < WIDTH; x += 1) {
      if (cellAt(room, x, y) === tile) positions.push({ x, y });
    }
  }
  return positions;
}

function pairedPositions(room, tile) {
  const positions = [];
  for (let y = 1; y < HEIGHT - 1; y += 2) {
    for (let x = 0; x < WIDTH; x += 1) {
      if (cellAt(room, x, y) === tile && cellAt(room, x, y + 1) === tile) {
        positions.push({ x, y });
      }
    }
  }
  return positions;
}

function samePoint(first, second) {
  return first.x === second.x && first.y === second.y;
}

function syncEnemyStarts(room) {
  const nests = pairedPositions(room, "S");
  const preserved = room.enemyStarts.filter((start) =>
    nests.some((nest) => samePoint(start, nest)),
  );
  room.enemyStarts = [
    ...preserved,
    ...nests.filter((nest) => !preserved.some((start) => samePoint(start, nest))),
  ];
}

function clearObjectAt(room, x, y) {
  const tile = cellAt(room, x, y);
  if (PAIRED_TILES.has(tile)) {
    const top = pairedTop(y);
    if (
      top > 0 &&
      top < HEIGHT - 1 &&
      cellAt(room, x, top) === tile &&
      cellAt(room, x, top + 1) === tile
    ) {
      setCell(room, x, top, ".");
      setCell(room, x, top + 1, ".");
      return;
    }
  }
  if (tile !== "#" && tile !== ".") setCell(room, x, y, ".");
}

function clearTile(room, tile) {
  for (const position of positionsOf(room, tile)) {
    setCell(room, position.x, position.y, ".");
  }
}

function beginEdit() {
  if (state.pendingEdit) return;
  state.pendingEdit = {
    roomIndex: currentIndex(),
    before: clone(currentRoom()),
  };
}

function finishEdit() {
  if (!state.pendingEdit) return;
  const pending = state.pendingEdit;
  state.pendingEdit = null;
  const after = clone(roomAt(pending.roomIndex));
  if (!roomsEqual(pending.before, after)) {
    state.history.push({ ...pending, after });
    if (state.history.length > 100) state.history.shift();
    state.future = [];
    markValidationStale();
  }
  renderAll();
}

function withEdit(callback) {
  beginEdit();
  callback();
  finishEdit();
}

function placePair(room, tile, x, y) {
  if (tile === "R") x = WIDTH - 2;
  const top = pairedTop(y);
  if (top <= 0 || top >= HEIGHT - 1) {
    toast("Two-cell objects must sit inside the room border.", "error");
    return false;
  }
  clearObjectAt(room, x, top);
  clearObjectAt(room, x, top + 1);
  setCell(room, x, top, tile);
  setCell(room, x, top + 1, tile);
  if (tile === "R") {
    setCell(room, WIDTH - 1, top, ".");
    setCell(room, WIDTH - 1, top + 1, ".");
  }
  return true;
}

function applyToolAt(x, y, tool = state.activeTool) {
  const room = currentRoom();
  let changed = false;

  if (tool === "wall" || tool === "floor") {
    const tile = tool === "wall" ? "#" : ".";
    const rows =
      elements.pairRows.checked && y > 0 && y < HEIGHT - 1
        ? [pairedTop(y), pairedTop(y) + 1]
        : [y];
    for (const row of rows) {
      clearObjectAt(room, x, row);
      changed = setCell(room, x, row, tile) || changed;
    }
  } else if (tool === "start") {
    changed = room.start.x !== x || room.start.y !== y;
    room.start = { x, y };
  } else if (tool === "treasure" || tool === "key") {
    const tile = tool === "treasure" ? "T" : "K";
    if (tile === "K") clearTile(room, "K");
    clearObjectAt(room, x, y);
    changed = setCell(room, x, y, tile) || changed;
  } else {
    const tile = {
      spawner: "S",
      warpDown: "V",
      warpUp: "A",
      exit: exitTileFor(room, state.project.stageRoomCounts),
    }[tool];
    if (!tile) return false;
    const top = pairedTop(y);
    if (top <= 0 || top >= HEIGHT - 1) {
      toast("Two-cell objects must sit inside the room border.", "error");
      return false;
    }
    if (
      tile === "S" &&
      pairedPositions(room, "S").length >= 3 &&
      !(cellAt(room, x, top) === "S" && cellAt(room, x, top + 1) === "S")
    ) {
      toast("This room already has three spawners. Move one from the inspector or erase it first.", "error");
      return false;
    }
    if (tile === "V" || tile === "A") clearTile(room, tile);
    if (tile === "R" || tile === "D") {
      clearTile(room, "R");
      clearTile(room, "D");
    }
    changed = placePair(room, tile, x, y);
  }

  syncEnemyStarts(room);
  if (changed) {
    state.selectedObject = null;
    renderRoomDetails();
  }
  return changed;
}

function objectsForRoom(room) {
  const objects = [
    {
      id: "start",
      kind: "start",
      symbol: "♟",
      label: "Player start",
      x: room.start.x,
      y: room.start.y,
      paired: false,
    },
  ];
  const definitions = [
    ["K", "Key", "⚿", false],
    ["T", "Treasure", "◆", false],
    ["S", "Spawner", "✹", true],
    ["V", "Warp down", "↓", true],
    ["A", "Warp up", "↑", true],
    ["R", "Room exit", "⇥", true],
    ["D", "Chamber exit", "⇥", true],
  ];
  for (const [tile, label, symbol, paired] of definitions) {
    const positions = paired ? pairedPositions(room, tile) : positionsOf(room, tile);
    positions.forEach((position, index) => {
      objects.push({
        id: `${tile}:${position.x}:${position.y}`,
        kind: tile,
        tile,
        symbol,
        label: positions.length > 1 ? `${label} ${index + 1}` : label,
        x: position.x,
        y: position.y,
        paired,
      });
    });
  }
  return objects;
}

function objectAt(room, x, y) {
  if (room.start.x === x && room.start.y === y) {
    return objectsForRoom(room)[0];
  }
  const tile = cellAt(room, x, y);
  if (tile === "." || tile === "#") return null;
  const objectY = PAIRED_TILES.has(tile) ? pairedTop(y) : y;
  return objectsForRoom(room).find(
    (object) => object.kind === tile && object.x === x && object.y === objectY,
  );
}

function moveSelectedObject(x, y) {
  if (!state.selectedObject || state.selectedObject.roomIndex !== currentIndex()) return false;
  const room = currentRoom();
  const object = objectsForRoom(room).find(
    (candidate) => candidate.id === state.selectedObject.id,
  );
  if (!object) {
    state.selectedObject = null;
    return false;
  }

  if (object.kind === "start") {
    room.start = { x, y };
    state.selectedObject.id = "start";
  } else if (object.paired) {
    const top = pairedTop(y);
    if (top <= 0 || top >= HEIGHT - 1) {
      toast("Two-cell objects must sit inside the room border.", "error");
      return false;
    }
    clearObjectAt(room, object.x, object.y);
    if (!placePair(room, object.tile, x, y)) return false;
    state.selectedObject.id = `${object.tile}:${object.tile === "R" ? WIDTH - 2 : x}:${top}`;
  } else {
    clearObjectAt(room, object.x, object.y);
    clearObjectAt(room, x, y);
    setCell(room, x, y, object.tile);
    state.selectedObject.id = `${object.tile}:${x}:${y}`;
  }
  syncEnemyStarts(room);
  renderRoomDetails();
  return true;
}

function selectObject(object) {
  state.selectedObject = object
    ? { roomIndex: currentIndex(), id: object.id }
    : null;
  selectTool("move", false);
  renderRoomDetails();
}

function roomChecks(room, roomWithinStage, roomCount) {
  const treasureCount = positionsOf(room, "T").length;
  const keyCount = positionsOf(room, "K").length;
  const spawnerTiles = positionsOf(room, "S").length;
  const spawners = pairedPositions(room, "S");
  const isFinalRoom = roomWithinStage === roomCount - 1;
  const expectedExit = isFinalRoom ? "D" : "R";
  const exits = pairedPositions(room, expectedExit);
  const wrongExit = positionsOf(room, expectedExit === "D" ? "R" : "D").length;
  const downTiles = positionsOf(room, "V").length;
  const upTiles = positionsOf(room, "A").length;
  const downPairs = pairedPositions(room, "V").length;
  const upPairs = pairedPositions(room, "A").length;
  const startsMatch =
    room.enemyStarts.length === 3 &&
    room.enemyStarts.every((start) => spawners.some((nest) => samePoint(start, nest)));
  const startTile = cellAt(room, room.start.x, room.start.y);
  const borderClosed = /^#+$/.test(room.tiles[0]) && /^#+$/.test(room.tiles.at(-1));

  return [
    {
      label: "Player start",
      detail: startTile === "." ? "clear" : `on ${startTile}`,
      ok: startTile === ".",
    },
    {
      label: "Treasures",
      detail: `${treasureCount} / 3`,
      ok: treasureCount === 3,
    },
    {
      label: "Chamber key",
      detail: `${keyCount} / ${roomWithinStage === 0 ? 1 : 0}`,
      ok: keyCount === (roomWithinStage === 0 ? 1 : 0),
    },
    {
      label: "Spawners",
      detail: `${spawners.length} / 3`,
      ok: spawnerTiles === 6 && spawners.length === 3 && startsMatch,
    },
    {
      label: isFinalRoom ? "Chamber exit" : "Room exit",
      detail: `${exits.length} / 1`,
      ok: exits.length === 1 && positionsOf(room, expectedExit).length === 2 && wrongExit === 0
        && (isFinalRoom || exits.every(({ x, y }) => x === WIDTH - 2
          && cellAt(room, WIDTH - 1, y) === "." && cellAt(room, WIDTH - 1, y + 1) === ".")),
    },
    {
      label: "Warp pair",
      detail: downTiles === 0 && upTiles === 0 ? "unused" : `${downPairs} ↓ · ${upPairs} ↑`,
      ok:
        (downTiles === 0 && upTiles === 0) ||
        (downTiles === 2 && upTiles === 2 && downPairs === 1 && upPairs === 1),
    },
    {
      label: "Top & bottom border",
      detail: borderClosed ? "closed" : "open",
      ok: borderClosed,
    },
  ];
}

function wallPalette(room) {
  const color = room.wallColor ?? "";
  if (color.includes("GREEN")) return ["#527f4d", "#395c37", "#77a16d"];
  if (color.includes("PURPLE")) return ["#72547f", "#4f3a5b", "#9772a3"];
  if (color.includes("TWO")) return ["#a85246", "#743a32", "#cc7567"];
  if (color.includes("THREE")) return ["#39758b", "#285362", "#5a9bb1"];
  return ["#a67a34", "#705223", "#c89a4d"];
}

function drawWall(x, y, colors) {
  const left = x * CELL;
  const top = y * CELL;
  context.fillStyle = colors[(x + y) % 2 === 0 ? 0 : 1];
  context.fillRect(left, top, CELL, CELL);
  context.strokeStyle = "rgba(18, 16, 10, 0.48)";
  context.lineWidth = 2;
  const offset = y % 2 === 0 ? 0 : CELL / 2;
  context.beginPath();
  context.moveTo(left, top + CELL / 2);
  context.lineTo(left + CELL, top + CELL / 2);
  context.moveTo(left + CELL / 2 + offset, top);
  context.lineTo(left + CELL / 2 + offset, top + CELL / 2);
  context.moveTo(left + CELL / 2 - offset, top + CELL / 2);
  context.lineTo(left + CELL / 2 - offset, top + CELL);
  context.stroke();
  context.fillStyle = "rgba(255, 238, 178, 0.08)";
  context.fillRect(left + 2, top + 2, CELL - 4, 2);
}

function drawItem(tile, x, y, paired = false) {
  const centerX = x * CELL + CELL / 2;
  const centerY = y * CELL + (paired ? CELL : CELL / 2);
  const height = paired ? CELL * 2 : CELL;
  context.save();

  if (paired) {
    context.fillStyle = "rgba(8, 8, 6, 0.48)";
    context.fillRect(x * CELL + 3, y * CELL + 3, CELL - 6, height - 6);
  }

  if (tile === "T") {
    context.translate(centerX, centerY);
    context.rotate(Math.PI / 4);
    context.fillStyle = "#edb940";
    context.fillRect(-8, -8, 16, 16);
    context.strokeStyle = "#fff0a8";
    context.lineWidth = 2;
    context.strokeRect(-5, -5, 10, 10);
  } else if (tile === "K") {
    context.strokeStyle = "#ffd96e";
    context.lineWidth = 4;
    context.beginPath();
    context.arc(centerX - 5, centerY - 4, 6, 0, Math.PI * 2);
    context.moveTo(centerX, centerY);
    context.lineTo(centerX + 9, centerY + 9);
    context.moveTo(centerX + 5, centerY + 5);
    context.lineTo(centerX + 9, centerY + 1);
    context.stroke();
  } else if (tile === "S") {
    context.fillStyle = "rgba(207, 77, 61, 0.2)";
    context.strokeStyle = "#e76f60";
    context.lineWidth = 2;
    context.beginPath();
    context.arc(centerX, centerY, 12, 0, Math.PI * 2);
    context.fill();
    context.stroke();
    for (let index = 0; index < 8; index += 1) {
      const angle = (Math.PI * 2 * index) / 8;
      context.beginPath();
      context.moveTo(centerX + Math.cos(angle) * 8, centerY + Math.sin(angle) * 8);
      context.lineTo(centerX + Math.cos(angle) * 17, centerY + Math.sin(angle) * 17);
      context.stroke();
    }
    context.fillStyle = "#ffb0a5";
    context.beginPath();
    context.arc(centerX, centerY, 4, 0, Math.PI * 2);
    context.fill();
  } else if (tile === "V" || tile === "A") {
    context.strokeStyle = "#48cbbb";
    context.fillStyle = "rgba(52, 178, 164, 0.13)";
    context.lineWidth = 2;
    context.beginPath();
    context.ellipse(centerX, centerY, 11, 20, 0, 0, Math.PI * 2);
    context.fill();
    context.stroke();
    context.fillStyle = "#8ff4e6";
    context.font = "700 22px ui-monospace, monospace";
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.fillText(tile === "V" ? "↓" : "↑", centerX, centerY);
  } else if (tile === "R" || tile === "D") {
    context.fillStyle = tile === "D" ? "#745531" : "#4e675d";
    context.strokeStyle = tile === "D" ? "#e6b05d" : "#80c1aa";
    context.lineWidth = 2;
    context.fillRect(centerX - 10, centerY - 23, 20, 46);
    context.strokeRect(centerX - 10, centerY - 23, 20, 46);
    context.beginPath();
    context.moveTo(centerX, centerY - 22);
    context.lineTo(centerX, centerY + 22);
    context.stroke();
    context.fillStyle = "#f4d889";
    context.beginPath();
    context.arc(centerX + 5, centerY, 2, 0, Math.PI * 2);
    context.fill();
  }
  context.restore();
}

function drawPlayerStart(room) {
  const { x, y } = room.start;
  const centerX = x * CELL + CELL / 2;
  const centerY = y * CELL + CELL / 2;
  context.save();
  context.shadowColor = "rgba(255, 238, 185, 0.65)";
  context.shadowBlur = 8;
  context.fillStyle = "#fff0c2";
  context.beginPath();
  context.arc(centerX, centerY - 7, 5, 0, Math.PI * 2);
  context.fill();
  context.fillRect(centerX - 4, centerY - 1, 8, 11);
  context.beginPath();
  context.moveTo(centerX - 4, centerY + 7);
  context.lineTo(centerX - 9, centerY + 14);
  context.moveTo(centerX + 4, centerY + 7);
  context.lineTo(centerX + 9, centerY + 14);
  context.strokeStyle = "#fff0c2";
  context.lineWidth = 3;
  context.stroke();
  context.restore();
}

function drawCanvas() {
  if (!state.project) return;
  const room = currentRoom();
  const deviceScale = Math.min(window.devicePixelRatio || 1, 2);
  const expectedWidth = WIDTH * CELL * deviceScale;
  const expectedHeight = HEIGHT * CELL * deviceScale;
  if (elements.canvas.width !== expectedWidth || elements.canvas.height !== expectedHeight) {
    elements.canvas.width = expectedWidth;
    elements.canvas.height = expectedHeight;
  }
  context.setTransform(deviceScale, 0, 0, deviceScale, 0, 0);
  context.clearRect(0, 0, WIDTH * CELL, HEIGHT * CELL);

  for (let y = 0; y < HEIGHT; y += 1) {
    for (let x = 0; x < WIDTH; x += 1) {
      context.fillStyle =
        y === 0 || y === HEIGHT - 1
          ? "#11110d"
          : y % 2 === 0
            ? "#1e1e17"
            : "#191a14";
      context.fillRect(x * CELL, y * CELL, CELL, CELL);
      if ((x * 7 + y * 11) % 13 === 0) {
        context.fillStyle = "rgba(207, 199, 159, 0.06)";
        context.fillRect(x * CELL + 8, y * CELL + 10, 2, 2);
      }
    }
  }

  const colors = wallPalette(room);
  for (let y = 0; y < HEIGHT; y += 1) {
    for (let x = 0; x < WIDTH; x += 1) {
      if (cellAt(room, x, y) === "#") drawWall(x, y, colors);
    }
  }

  if (room.wallDecorations) {
    for (const { x, y, symbol } of room.wallDecorations) {
      if (cellAt(room, x, y) !== "#" || cellAt(room, x + 1, y) !== "#") continue;
      const bitmap = state.project.wallSymbols[symbol].bitmap;
      const pixel = CELL / 8;
      context.fillStyle = "#080a09";
      context.fillRect(x * CELL, y * CELL, CELL * 2, CELL);
      context.fillStyle = colors[2];
      bitmap.forEach((byte, index) => {
        const row = index % 8;
        const half = Math.floor(index / 8);
        for (let col = 0; col < 8; col += 1) {
          if (byte & (128 >> col)) context.fillRect((x + half) * CELL + col * pixel, y * CELL + row * pixel, pixel, pixel);
        }
      });
    }
  }

  for (let y = 0; y < HEIGHT; y += 1) {
    for (let x = 0; x < WIDTH; x += 1) {
      const tile = cellAt(room, x, y);
      if (tile === "." || tile === "#") continue;
      if (PAIRED_TILES.has(tile)) {
        if (y % 2 === 1 && y + 1 < HEIGHT && cellAt(room, x, y + 1) === tile) {
          drawItem(tile, x, y, true);
        } else if (!(y % 2 === 0 && y > 0 && cellAt(room, x, y - 1) === tile)) {
          drawItem(tile, x, y, false);
        }
      } else {
        drawItem(tile, x, y, false);
      }
    }
  }

  for (const cell of doorCells(room, state.project.doorSprites)) {
    const pixel = CELL / 8;
    context.fillStyle = "#080a09";
    context.fillRect(cell.x * CELL, cell.y * CELL, CELL, CELL);
    context.fillStyle = cell.color;
    cell.bitmap.forEach((byte, row) => {
      for (let col = 0; col < 8; col += 1) {
        if (byte & (128 >> col)) {
          context.fillRect(cell.x * CELL + col * pixel, cell.y * CELL + row * pixel, pixel, pixel);
        }
      }
    });
  }

  context.lineWidth = 1;
  for (let x = 0; x <= WIDTH; x += 1) {
    context.strokeStyle = x === 1 || x === WIDTH - 1 ? "rgba(233,185,73,0.22)" : "rgba(137,132,108,0.12)";
    context.beginPath();
    context.moveTo(x * CELL + 0.5, 0);
    context.lineTo(x * CELL + 0.5, HEIGHT * CELL);
    context.stroke();
  }
  for (let y = 0; y <= HEIGHT; y += 1) {
    context.strokeStyle = y % 2 === 1 ? "rgba(233,185,73,0.2)" : "rgba(137,132,108,0.1)";
    context.beginPath();
    context.moveTo(0, y * CELL + 0.5);
    context.lineTo(WIDTH * CELL, y * CELL + 0.5);
    context.stroke();
  }

  drawPlayerStart(room);

  if (state.selectedObject?.roomIndex === currentIndex()) {
    const selected = objectsForRoom(room).find((object) => object.id === state.selectedObject.id);
    if (selected) {
      context.strokeStyle = "#ffd86f";
      context.lineWidth = 3;
      context.setLineDash([6, 4]);
      context.strokeRect(
        selected.x * CELL + 2,
        selected.y * CELL + 2,
        CELL - 4,
        (selected.paired ? CELL * 2 : CELL) - 4,
      );
      context.setLineDash([]);
    }
  }

  if (state.hover) {
    const pairPreview =
      (state.activeTool === "wall" || state.activeTool === "floor") && elements.pairRows.checked ||
      ["spawner", "warpDown", "warpUp", "exit"].includes(state.activeTool);
    const hoverY = pairPreview ? pairedTop(state.hover.y) : state.hover.y;
    const hoverHeight = pairPreview && hoverY > 0 && hoverY < HEIGHT - 1 ? CELL * 2 : CELL;
    context.fillStyle = "rgba(255, 220, 120, 0.08)";
    context.fillRect(state.hover.x * CELL, hoverY * CELL, CELL, hoverHeight);
    context.strokeStyle = "rgba(255, 220, 120, 0.8)";
    context.lineWidth = 2;
    context.strokeRect(state.hover.x * CELL + 1, hoverY * CELL + 1, CELL - 2, hoverHeight - 2);
  }
}

function renderNavigation() {
  const dirty = new Set(dirtyRoomIndexes());
  elements.stageList.replaceChildren();
  for (let stage = 0; stage < state.project.stageRoomCounts.length; stage += 1) {
    const offset = stageOffset(stage);
    const roomCount = state.project.stageRoomCounts[stage];
    const button = document.createElement("button");
    button.type = "button";
    button.className = "stage-button";
    if (stage === state.currentStage) button.classList.add("active");
    if (Array.from({ length: roomCount }, (_, room) => dirty.has(offset + room)).some(Boolean)) {
      button.classList.add("dirty");
    }
    button.textContent = state.project.chamberNames[stage];
    button.dataset.stage = stage;
    button.setAttribute("aria-label", state.project.chamberNames[stage]);
    elements.stageList.append(button);
  }

  elements.roomTabs.replaceChildren();
  const offset = stageOffset(state.currentStage);
  const roomCount = state.project.stageRoomCounts[state.currentStage];
  for (let room = 0; room < roomCount; room += 1) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "room-button";
    if (room === state.currentRoom) button.classList.add("active");
    if (dirty.has(offset + room)) button.classList.add("dirty");
    button.textContent = `Room ${room + 1}`;
    button.dataset.room = room;
    elements.roomTabs.append(button);
  }
}

function renderChecks() {
  const checks = roomChecks(
    currentRoom(),
    state.currentRoom,
    state.project.stageRoomCounts[state.currentStage],
  );
  const healthy = checks.every((check) => check.ok);
  elements.healthBadge.textContent = healthy ? "READY" : `${checks.filter((check) => !check.ok).length} ISSUE${checks.filter((check) => !check.ok).length === 1 ? "" : "S"}`;
  elements.healthBadge.className = `health-badge ${healthy ? "good" : "bad"}`;
  elements.checkList.replaceChildren();
  for (const check of checks) {
    const row = document.createElement("div");
    row.className = `check-row ${check.ok ? "" : "bad"}`;
    const icon = document.createElement("span");
    icon.className = "check-icon";
    icon.textContent = check.ok ? "✓" : "!";
    const label = document.createElement("strong");
    label.textContent = check.label;
    const output = document.createElement("output");
    output.textContent = check.detail;
    row.append(icon, label, output);
    elements.checkList.append(row);
  }
}

function renderObjects() {
  const objects = objectsForRoom(currentRoom());
  elements.objectList.replaceChildren();
  for (const object of objects) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "object-row";
    button.dataset.objectId = object.id;
    if (
      state.selectedObject?.roomIndex === currentIndex() &&
      state.selectedObject.id === object.id
    ) {
      button.classList.add("selected");
    }
    const symbol = document.createElement("span");
    symbol.className = "object-symbol";
    symbol.textContent = object.symbol;
    const name = document.createElement("span");
    name.className = "object-name";
    name.textContent = object.label;
    const coordinates = document.createElement("span");
    coordinates.className = "object-coordinates";
    coordinates.textContent = `${object.x},${object.y}`;
    button.append(symbol, name, coordinates);
    elements.objectList.append(button);
  }
}

function renderDocumentState() {
  const dirty = dirtyRoomIndexes();
  elements.connectionDot.className = `status-dot ${dirty.length ? "dirty" : "online"}`;
  elements.documentStatus.textContent = dirty.length
    ? `${dirty.length} unsaved room${dirty.length === 1 ? "" : "s"}`
    : "Source is in sync";
  elements.saveButton.disabled = state.busy || dirty.length === 0;
  elements.validateButton.disabled = state.busy;
  elements.undoButton.disabled = state.history.length === 0 || state.busy;
  elements.redoButton.disabled = state.future.length === 0 || state.busy;
  elements.exportButton.disabled = state.busy || !state.project;
}

function renderToolState() {
  document.querySelectorAll("[data-tool]").forEach((button) => {
    const active = button.dataset.tool === state.activeTool;
    button.classList.toggle("active", active);
    button.setAttribute("aria-pressed", active ? "true" : "false");
  });
  elements.activeShortcut.textContent = toolDefinitions[state.activeTool].shortcut;
  elements.toolHint.textContent = toolDefinitions[state.activeTool].hint;
  elements.canvas.classList.toggle("move-cursor", state.activeTool === "move");
}

function renderRoomDetails() {
  if (!state.project) return;
  const room = currentRoom();
  elements.roomBreadcrumb.textContent = `${state.project.chamberNames[room.stage - 1]} · Room ${room.room}`;
  elements.roomTitle.textContent = `${room.name} layout`;
  renderChecks();
  renderObjects();
  drawCanvas();
  renderDocumentState();
}

function renderAll() {
  if (!state.project) return;
  renderNavigation();
  renderToolState();
  renderRoomDetails();
}

function selectTool(tool, clearSelection = true) {
  if (!toolDefinitions[tool]) return;
  state.activeTool = tool;
  if (clearSelection && tool !== "move") state.selectedObject = null;
  renderToolState();
  drawCanvas();
}

function navigate(stage, room) {
  if (state.pointerDown) return;
  state.currentStage = Math.max(
    0,
    Math.min(state.project.stageRoomCounts.length - 1, stage),
  );
  state.currentRoom = Math.max(
    0,
    Math.min(state.project.stageRoomCounts[state.currentStage] - 1, room),
  );
  state.selectedObject = null;
  state.hover = null;
  elements.coordinateReadout.textContent = "x — · y —";
  renderAll();
}

function undo() {
  const entry = state.history.pop();
  if (!entry) return;
  state.future.push(entry);
  state.project.rooms[entry.roomIndex] = clone(entry.before);
  navigate(entry.before.stage - 1, entry.before.room - 1);
  markValidationStale();
}

function redo() {
  const entry = state.future.pop();
  if (!entry) return;
  state.history.push(entry);
  state.project.rooms[entry.roomIndex] = clone(entry.after);
  navigate(entry.after.stage - 1, entry.after.room - 1);
  markValidationStale();
}

function canvasPosition(event) {
  const rect = elements.canvas.getBoundingClientRect();
  return {
    x: Math.max(0, Math.min(WIDTH - 1, Math.floor(((event.clientX - rect.left) / rect.width) * WIDTH))),
    y: Math.max(0, Math.min(HEIGHT - 1, Math.floor(((event.clientY - rect.top) / rect.height) * HEIGHT))),
  };
}

function handleCanvasPointerDown(event) {
  if (!state.project || state.busy || (event.button !== 0 && event.button !== 2)) return;
  event.preventDefault();
  const position = canvasPosition(event);
  state.pointerDown = true;
  state.pointerTool = event.button === 2 ? "floor" : state.activeTool;
  state.lastPaintKey = "";
  elements.canvas.setPointerCapture(event.pointerId);

  if (state.pointerTool === "move") {
    if (state.selectedObject?.roomIndex === currentIndex()) {
      beginEdit();
      moveSelectedObject(position.x, position.y);
    } else {
      selectObject(objectAt(currentRoom(), position.x, position.y));
    }
    return;
  }

  beginEdit();
  state.lastPaintKey = `${position.x},${position.y}`;
  applyToolAt(position.x, position.y, state.pointerTool);
}

function handleCanvasPointerMove(event) {
  if (!state.project) return;
  const position = canvasPosition(event);
  state.hover = position;
  elements.coordinateReadout.textContent = `x ${String(position.x).padStart(2, "0")} · y ${String(position.y).padStart(2, "0")}`;

  if (
    state.pointerDown &&
    (state.pointerTool === "wall" || state.pointerTool === "floor")
  ) {
    const key = `${position.x},${position.y}`;
    if (key !== state.lastPaintKey) {
      state.lastPaintKey = key;
      applyToolAt(position.x, position.y, state.pointerTool);
    }
  } else {
    drawCanvas();
  }
}

function handleCanvasPointerUp(event) {
  if (!state.pointerDown) return;
  state.pointerDown = false;
  state.pointerTool = null;
  state.lastPaintKey = "";
  if (elements.canvas.hasPointerCapture(event.pointerId)) {
    elements.canvas.releasePointerCapture(event.pointerId);
  }
  finishEdit();
}

function setValidation(kind, title, message) {
  elements.validationPanel.className = `validation-panel panel ${kind}`;
  elements.validationIcon.textContent = kind === "success" ? "✓" : kind === "failure" ? "!" : "i";
  elements.validationTitle.textContent = title;
  elements.validationMessage.textContent = message;
}

function markValidationStale() {
  setValidation("", "Changes not checked", "Run validation before saving to check reachability, spacing, pacing, and topology.");
}

function setBusy(busy) {
  state.busy = busy;
  elements.editorLayout.setAttribute("aria-busy", busy ? "true" : "false");
  renderDocumentState();
}

async function apiRequest(url, options = {}) {
  const response = await fetch(url, options);
  let body;
  try {
    body = await response.json();
  } catch {
    body = {};
  }
  if (!response.ok) {
    const error = new Error(body.message || body.error || `Request failed (${response.status})`);
    error.status = response.status;
    error.body = body;
    throw error;
  }
  return body;
}

async function validateProject() {
  if (!state.project || state.busy) return;
  setBusy(true);
  setValidation("", "Checking all 21 rooms…", "The game validator is testing structure, progression, reachability, pacing, and maze topology.");
  try {
    const result = await apiRequest("/api/validate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ revision: state.revision, project: state.project }),
    });
    setValidation("success", "Campaign passes validation", result.message);
    toast("All rooms pass the game content validator.", "success");
  } catch (error) {
    setValidation("failure", "Validation found a problem", error.message);
    toast(error.message, "error");
  } finally {
    setBusy(false);
  }
}

async function saveProject() {
  if (!state.project || state.busy || !isDirty()) return;
  setBusy(true);
  setValidation("", "Validating before save…", "No source file is changed until the full campaign passes.");
  try {
    const result = await apiRequest("/api/project", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ revision: state.revision, project: state.project }),
    });
    state.revision = result.revision;
    state.baseline = clone(state.project);
    state.history = [];
    state.future = [];
    setValidation("success", "Saved to assembly source", result.message);
    toast("src/game/data.asm was updated atomically.", "success");
  } catch (error) {
    setValidation("failure", "Source was not changed", error.message);
    toast(error.message, "error");
  } finally {
    setBusy(false);
    renderAll();
  }
}

function validateImportedProject(project) {
  if (!project || project.formatVersion !== 1 || project.width !== WIDTH || project.height !== HEIGHT) {
    throw new Error("This is not a compatible Tutankham level-editor draft.");
  }
  if (
    !Array.isArray(project.rooms) ||
    project.rooms.length !== state.project.rooms.length ||
    project.rooms.some((room, index) => room.id !== state.project.rooms[index].id)
  ) {
    throw new Error("The draft’s room list does not match this campaign.");
  }
  if (
    JSON.stringify(project.stageRoomCounts) !==
    JSON.stringify(state.project.stageRoomCounts)
  ) {
    throw new Error("The draft’s chamber structure does not match this campaign.");
  }
  for (const room of project.rooms) {
    if (!Array.isArray(room.tiles) || room.tiles.length !== HEIGHT || room.tiles.some((row) => typeof row !== "string" || row.length !== WIDTH || !/^[#.KTSVARD]+$/.test(row))) {
      throw new Error(`${room.id} contains an invalid room grid.`);
    }
    if (!room.start || !Number.isInteger(room.start.x) || !Number.isInteger(room.start.y)) {
      throw new Error(`${room.id} has an invalid player start.`);
    }
    if (!Array.isArray(room.enemyStarts)) {
      throw new Error(`${room.id} has invalid guardian starts.`);
    }
  }
}

function exportDraft() {
  if (!state.project) return;
  const payload = {
    editor: "Tutankham Maze Workshop",
    exportedAt: new Date().toISOString(),
    project: state.project,
  };
  const blob = new Blob([`${JSON.stringify(payload, null, 2)}\n`], { type: "application/json" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = "tutankham-levels-draft.json";
  link.click();
  URL.revokeObjectURL(link.href);
  toast("Draft exported. It can be imported without touching the assembly source.");
}

async function importDraft(file) {
  try {
    const payload = JSON.parse(await file.text());
    const project = payload.project ?? payload;
    validateImportedProject(project);
    const imported = clone(project);
    imported.chamberNames = [...state.project.chamberNames];
    imported.doorSprites = clone(state.project.doorSprites);
    imported.wallSymbols = clone(state.project.wallSymbols);
    imported.rooms.forEach((room, index) => {
      room.wallDecorations = clone(state.project.rooms[index].wallDecorations);
      room.name = state.project.rooms[index].name;
      room.stage = state.project.rooms[index].stage;
      room.room = state.project.rooms[index].room;
    });
    state.project = imported;
    state.history = [];
    state.future = [];
    state.selectedObject = null;
    markValidationStale();
    renderAll();
    toast("Draft imported into the editor. Validate or save when ready.", "success");
  } catch (error) {
    toast(error.message, "error");
  } finally {
    elements.importInput.value = "";
  }
}

function toast(message, kind = "") {
  const item = document.createElement("div");
  item.className = `toast ${kind}`;
  item.textContent = message;
  elements.toastRegion.append(item);
  window.setTimeout(() => item.remove(), 4600);
}

async function loadProject() {
  try {
    const payload = await apiRequest("/api/project");
    state.project = payload.project;
    state.baseline = clone(payload.project);
    state.revision = payload.revision;
    elements.sourcePath.textContent = payload.sourcePath;
    elements.canvasEmpty.classList.add("hidden");
    elements.editorLayout.setAttribute("aria-busy", "false");
    renderAll();
  } catch (error) {
    elements.canvasEmpty.querySelector("p").textContent = "Could not read the level source.";
    elements.connectionDot.className = "status-dot error";
    elements.documentStatus.textContent = "Editor server unavailable";
    setValidation("failure", "Could not load levels", error.message);
    toast(error.message, "error");
  }
}

document.querySelectorAll("[data-tool]").forEach((button) => {
  button.addEventListener("click", () => selectTool(button.dataset.tool));
});

elements.stageList.addEventListener("click", (event) => {
  const button = event.target.closest("[data-stage]");
  if (button) navigate(Number(button.dataset.stage), state.currentRoom);
});

elements.roomTabs.addEventListener("click", (event) => {
  const button = event.target.closest("[data-room]");
  if (button) navigate(state.currentStage, Number(button.dataset.room));
});

elements.objectList.addEventListener("click", (event) => {
  const button = event.target.closest("[data-object-id]");
  if (!button) return;
  const object = objectsForRoom(currentRoom()).find((candidate) => candidate.id === button.dataset.objectId);
  selectObject(object);
});

elements.canvas.addEventListener("pointerdown", handleCanvasPointerDown);
elements.canvas.addEventListener("pointermove", handleCanvasPointerMove);
elements.canvas.addEventListener("pointerup", handleCanvasPointerUp);
elements.canvas.addEventListener("pointercancel", handleCanvasPointerUp);
elements.canvas.addEventListener("pointerleave", () => {
  if (!state.pointerDown) {
    state.hover = null;
    elements.coordinateReadout.textContent = "x — · y —";
    drawCanvas();
  }
});
elements.canvas.addEventListener("contextmenu", (event) => event.preventDefault());

elements.undoButton.addEventListener("click", undo);
elements.redoButton.addEventListener("click", redo);
elements.resetRoomButton.addEventListener("click", () => {
  if (!state.project) return;
  withEdit(() => {
    state.project.rooms[currentIndex()] = clone(state.baseline.rooms[currentIndex()]);
    state.selectedObject = null;
  });
  toast("Room restored to the last saved version. Undo is still available.");
});
elements.validateButton.addEventListener("click", validateProject);
elements.saveButton.addEventListener("click", saveProject);
elements.exportButton.addEventListener("click", exportDraft);
elements.importInput.addEventListener("change", () => {
  if (elements.importInput.files[0]) importDraft(elements.importInput.files[0]);
});

window.addEventListener("keydown", (event) => {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "z") {
    event.preventDefault();
    if (event.shiftKey) redo();
    else undo();
    return;
  }
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "y") {
    event.preventDefault();
    redo();
    return;
  }
  if (event.ctrlKey || event.metaKey || event.altKey) return;
  if (event.key === "Escape") {
    state.selectedObject = null;
    selectTool("move", false);
    renderRoomDetails();
    return;
  }
  const key = event.key.toUpperCase();
  const tool = Object.entries(toolDefinitions).find(([, definition]) => definition.shortcut === key)?.[0];
  if (tool) {
    event.preventDefault();
    selectTool(tool);
  }
});

window.addEventListener("beforeunload", (event) => {
  if (!isDirty()) return;
  event.preventDefault();
  event.returnValue = "";
});

loadProject();
