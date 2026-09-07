// Shared by the browser preview and PNG exporter. Coordinates are physical
// map cells; each returned bitmap contains the eight scanlines of one cell.
export function exitTileFor(room, stageRoomCounts) {
  return room.room === stageRoomCounts[room.stage - 1] ? "D" : "R";
}

export function doorCells(room, doorSprites) {
  const cells = [];
  const height = room.tiles.length;
  const width = room.tiles[0].length;
  const sprite = doorSprites[(room.stage - 1) % 2];
  const color = sprite.name === "Yellow" ? "#f4d35e" : "#d93824";
  for (let y = 1; y < height - 1; y += 2) {
    for (let x = 0; x < width; x += 1) {
      if (room.tiles[y][x] !== "D" || room.tiles[y + 1][x] !== "D") continue;
      for (let dy = 0; dy < 2; dy += 1) {
        for (let dx = 0; dx < 2 && x + dx + 1 < width; dx += 1) {
          const offset = (dy * 2 + dx) * 8;
          cells.push({ x: x + dx + 1, y: y + dy, color,
            bitmap: sprite.bitmap.slice(offset, offset + 8) });
        }
      }
    }
  }
  return cells;
}
