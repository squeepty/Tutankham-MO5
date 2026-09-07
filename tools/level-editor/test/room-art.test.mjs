import test from "node:test";
import assert from "node:assert/strict";
import { doorCells, exitTileFor } from "../public/room-art.mjs";

const sprites = ["Yellow", "Red"].map(name => ({ name,
  bitmap: Array.from({ length: 32 }, (_, i) => i) }));
function roomAt(x, stage = 1) {
  const tiles = Array.from({ length: 6 }, () => Array(8).fill("#"));
  tiles[1][x] = tiles[2][x] = "D";
  return { stage, room: 1, tiles: tiles.map(row => row.join("")) };
}

test("door quadrants retain their source offsets and alternate stage colors", () => {
  const cells = doorCells(roomAt(4), sprites);
  assert.deepEqual(cells.map(({ x, y, bitmap }) => [x, y, bitmap[0]]),
    [[5, 1, 0], [6, 1, 8], [5, 2, 16], [6, 2, 24]]);
  assert.ok(cells.every(cell => cell.color === "#f4d35e"));
  assert.ok(doorCells(roomAt(4, 2), sprites).every(cell => cell.color === "#d93824"));
});

test("right-edge clipping keeps the left leaf, and unpaired markers draw nothing", () => {
  assert.deepEqual(doorCells(roomAt(6), sprites).map(cell => cell.bitmap[0]), [0, 16]);
  assert.deepEqual(doorCells(roomAt(7), sprites), []);
  const room = roomAt(4);
  room.tiles[2] = "########";
  assert.deepEqual(doorCells(room, sprites), []);
});

test("exit tool chooses a stage door for final rooms in variable-length stages", () => {
  const counts = [1, 2, 3];
  for (let stage = 1; stage <= 3; stage += 1) {
    for (let room = 1; room <= counts[stage - 1]; room += 1) {
      assert.equal(exitTileFor({ stage, room }, counts), room === counts[stage - 1] ? "D" : "R");
    }
  }
});
