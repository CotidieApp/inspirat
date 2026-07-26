import assert from "node:assert/strict";
import test from "node:test";

import { RefreshCoordinator } from "../app/session-refresh.ts";

test("comparte una sola renovación entre solicitudes concurrentes del mismo perfil", async () => {
  const coordinator = new RefreshCoordinator();
  let calls = 0;
  let release;

  const refresh = () => {
    calls += 1;
    return new Promise((resolve) => {
      release = resolve;
    });
  };
  const first = coordinator.run("ines", refresh);
  const second = coordinator.run("ines", refresh);

  assert.strictEqual(first, second);
  await Promise.resolve();
  assert.equal(calls, 1);
  assert.equal(coordinator.has("ines"), true);

  release({ accessToken: "rotated" });
  assert.deepEqual(await first, { accessToken: "rotated" });
  assert.deepEqual(await second, { accessToken: "rotated" });
  assert.equal(coordinator.has("ines"), false);
});

test("aísla perfiles y permite reintentar después de un refresh fallido", async () => {
  const coordinator = new RefreshCoordinator();
  let inesCalls = 0;
  let mateoCalls = 0;

  const failed = coordinator.run("ines", async () => {
    inesCalls += 1;
    throw new Error("refresh inválido");
  });
  const mateo = coordinator.run("mateo", async () => {
    mateoCalls += 1;
    return "mateo-token";
  });

  await assert.rejects(failed, /refresh inválido/);
  assert.equal(await mateo, "mateo-token");
  assert.equal(coordinator.has("ines"), false);
  assert.equal(coordinator.has("mateo"), false);

  const recovered = await coordinator.run("ines", async () => {
    inesCalls += 1;
    return "ines-token";
  });
  assert.equal(recovered, "ines-token");
  assert.equal(inesCalls, 2);
  assert.equal(mateoCalls, 1);
});
