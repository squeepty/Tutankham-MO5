#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

import { doorCells } from "./level-editor/public/room-art.mjs";

import { parseGameData } from "./level-editor/lib/data-file.mjs";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, "..");
const sourcePath = path.join(projectRoot, "src/game/data.asm");
const outputDirectory = path.resolve(
  projectRoot,
  process.argv[2] ?? "levels_current",
);

const CELL_SIZE = 8;
const SCALE = 4;

const colors = {
  background: "#080a09",
  door: "#d38b43",
  exit: "#f3e7bf",
  key: "#f4d35e",
  player: "#f8f1d4",
  spawn: "#d062b4",
  treasure: "#f4d35e",
  warp: "#72d6cb",
};

const wallColors = new Map([
  ["COLOR_WALL_ROOM_ONE", "#c89a4d"],
  ["COLOR_WALL_ROOM_TWO", "#cc7567"],
  ["COLOR_WALL_ROOM_THREE", "#5a9bb1"],
  ["COLOR_WALL_GREEN", "#77a16d"],
  ["COLOR_WALL_PURPLE", "#9772a3"],
]);

const tilePatterns = new Map([
  ["D", "CellExit"],
  ["K", "CellKey"],
  ["T", "CellTreasure"],
  ["S", "CellSpawn"],
  ["V", "CellWarp"],
  ["A", "CellWarp"],
  ["R", "CellRoomExit"],
]);

const tileColors = new Map([
  ["D", colors.door],
  ["K", colors.key],
  ["T", colors.treasure],
  ["S", colors.spawn],
  ["V", colors.warp],
  ["A", colors.warp],
  ["R", colors.exit],
]);

function blockFor(source, label) {
  const marker = new RegExp(`^${label}:`, "m");
  const match = marker.exec(source);
  if (!match) throw new Error(`Missing artwork label ${label}`);
  const rest = source.slice(match.index + match[0].length);
  const nextLabel = /^[A-Za-z_][A-Za-z0-9_]*:/m.exec(rest);
  return nextLabel ? rest.slice(0, nextLabel.index) : rest;
}

function bytesFor(source, label) {
  const bytes = [...blockFor(source, label).matchAll(/\$([0-9a-f]{2})/gi)].map(
    (match) => Number.parseInt(match[1], 16),
  );
  if (bytes.length < CELL_SIZE) {
    throw new Error(`${label} does not contain an 8-row cell pattern`);
  }
  return bytes.slice(0, CELL_SIZE);
}

function rgb(hex) {
  return [
    Number.parseInt(hex.slice(1, 3), 16),
    Number.parseInt(hex.slice(3, 5), 16),
    Number.parseInt(hex.slice(5, 7), 16),
    255,
  ];
}

function setPixel(pixels, width, x, y, color) {
  const offset = (y * width + x) * 4;
  pixels.set(color, offset);
}

function fill(pixels, color) {
  for (let offset = 0; offset < pixels.length; offset += 4) {
    pixels.set(color, offset);
  }
}

function drawPattern(pixels, width, pattern, cellX, cellY, color) {
  for (let row = 0; row < CELL_SIZE; row += 1) {
    for (let column = 0; column < CELL_SIZE; column += 1) {
      if ((pattern[row] & (0x80 >> column)) === 0) continue;
      const startX = (cellX * CELL_SIZE + column) * SCALE;
      const startY = (cellY * CELL_SIZE + row) * SCALE;
      for (let y = 0; y < SCALE; y += 1) {
        for (let x = 0; x < SCALE; x += 1) {
          setPixel(pixels, width, startX + x, startY + y, color);
        }
      }
    }
  }
}

function crcTable() {
  return Array.from({ length: 256 }, (_, value) => {
    let crc = value;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) === 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
    return crc >>> 0;
  });
}

const crcValues = crcTable();

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc = crcValues[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const typeBuffer = Buffer.from(type, "ascii");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])));
  return Buffer.concat([length, typeBuffer, data, checksum]);
}

function pngFor(width, height, pixels) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;

  const stride = width * 4;
  const scanlines = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y += 1) {
    const destination = y * (stride + 1);
    scanlines[destination] = 0;
    pixels.copy(scanlines, destination + 1, y * stride, (y + 1) * stride);
  }

  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk("IHDR", header),
    pngChunk("IDAT", zlib.deflateSync(scanlines, { level: 9 })),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function renderRoom(room, patterns, widthInCells, heightInCells) {
  const width = widthInCells * CELL_SIZE * SCALE;
  const height = heightInCells * CELL_SIZE * SCALE;
  const pixels = Buffer.alloc(width * height * 4);
  fill(pixels, rgb(colors.background));

  const wallColor = rgb(
    wallColors.get(room.wallColor) ?? wallColors.get("COLOR_WALL_ROOM_ONE"),
  );
  for (let y = 0; y < heightInCells; y += 1) {
    for (let x = 0; x < widthInCells; x += 1) {
      const tile = room.tiles[y][x];
      if (tile === "#") {
        const decoration = room.wallDecorations
          ? room.wallDecorations.find(item => x >= item.x && x < item.x + 2 && item.y === y
            && room.tiles[y][item.x] === "#" && room.tiles[y][item.x + 1] === "#") : undefined;
        const pattern = decoration
          ? project.wallSymbols[decoration.symbol].bitmap.slice((x - decoration.x) * 8, (x - decoration.x + 1) * 8)
          : patterns.get((x + y) % 2 === 0 ? "CellWallA" : "CellWallB");
        drawPattern(pixels, width, pattern, x, y, wallColor);
        continue;
      }
      const patternName = tilePatterns.get(tile);
      if (patternName) {
        drawPattern(pixels, width, patterns.get(patternName), x, y, rgb(tileColors.get(tile)));
      }
    }
  }

  for (const cell of doorCells(room, project.doorSprites)) {
    const background = rgb(colors.background);
    for (let py = 0; py < CELL_SIZE * SCALE; py += 1) {
      for (let px = 0; px < CELL_SIZE * SCALE; px += 1) {
        setPixel(pixels, width, cell.x * CELL_SIZE * SCALE + px,
          cell.y * CELL_SIZE * SCALE + py, background);
      }
    }
    drawPattern(pixels, width, cell.bitmap, cell.x, cell.y, rgb(cell.color));
  }

  drawPattern(
    pixels,
    width,
    patterns.get("CellPlayerLife"),
    room.start.x,
    room.start.y,
    rgb(colors.player),
  );
  return pngFor(width, height, pixels);
}

const source = await fs.readFile(sourcePath, "utf8");
const project = parseGameData(source);
const patternNames = new Set([
  "CellWallA",
  "CellWallB",
  "CellExit",
  "CellKey",
  "CellTreasure",
  "CellSpawn",
  "CellWarp",
  "CellRoomExit",
  "CellPlayerLife",
]);
const patterns = new Map(
  [...patternNames].map((name) => [name, bytesFor(source, name)]),
);

await fs.mkdir(outputDirectory, { recursive: true });
for (const room of project.rooms) {
  const filename = `stage-${String(room.stage).padStart(2, "0")}-room-${String(room.room).padStart(2, "0")}.png`;
  const image = renderRoom(room, patterns, project.width, project.height);
  await fs.writeFile(path.join(outputDirectory, filename), image);
}

console.log(
  `Exported ${project.rooms.length} room images to ${path.relative(projectRoot, outputDirectory) || "."}`,
);
