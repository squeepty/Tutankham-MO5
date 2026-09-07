import test from "node:test";
import assert from "node:assert/strict";

import { createLevelEditorServer } from "../server.mjs";

async function withServer(callback) {
  const server = createLevelEditorServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  try {
    const address = server.address();
    await callback(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("serves the editor project and validates an unchanged campaign", async () => {
  await withServer(async (baseUrl) => {
    const projectResponse = await fetch(`${baseUrl}/api/project`);
    assert.equal(projectResponse.status, 200);
    const payload = await projectResponse.json();
    assert.equal(payload.project.rooms.length, 21);
    assert.deepEqual(
      payload.project.stageRoomCounts,
      [1, 2, 2, 2, 2, 3, 3, 3, 3],
    );
    assert.equal(payload.revision.length, 64);

    const validationResponse = await fetch(`${baseUrl}/api/validate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        revision: payload.revision,
        project: payload.project,
      }),
    });
    assert.equal(validationResponse.status, 200);
    assert.equal((await validationResponse.json()).ok, true);
  });
});

test("rejects a stale editor revision without writing", async () => {
  await withServer(async (baseUrl) => {
    const payload = await (await fetch(`${baseUrl}/api/project`)).json();
    const response = await fetch(`${baseUrl}/api/validate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ revision: "stale", project: payload.project }),
    });
    assert.equal(response.status, 409);
    assert.match((await response.json()).error, /changed after the editor loaded/);
  });
});

test("serves the shared preview module as executable JavaScript", async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/room-art.mjs`);
    assert.equal(response.status, 200);
    assert.match(response.headers.get("content-type"), /^text\/javascript/);
    assert.match(await response.text(), /export function doorCells/);
  });
});
