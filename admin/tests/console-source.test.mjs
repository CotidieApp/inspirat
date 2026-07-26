import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const consoleSourceUrl = new URL("../app/tester-console.tsx", import.meta.url);
const layoutUrl = new URL("../app/layout.tsx", import.meta.url);

test("la consola conserva perfiles y configuración solo en el navegador", async () => {
  const source = await readFile(consoleSourceUrl, "utf8");

  assert.match(source, /localStorage\.setItem\(PROFILES_KEY/);
  assert.match(source, /localStorage\.setItem\(API_URL_KEY/);
  assert.match(source, /Consola local de pruebas/);
  assert.match(source, /No publiques esta consola/);
});

test("renueva sesiones por perfil y reintenta una sola vez tras un 401", async () => {
  const source = await readFile(consoleSourceUrl, "utf8");

  assert.match(source, /new RefreshCoordinator<Person>\(\)/);
  assert.match(source, /"\/auth\/refresh"/);
  assert.match(source, /refresh_token: refreshToken/);
  assert.match(source, /error\.status !== 401/);
  assert.match(
    source,
    /latestPerson\.accessToken !== currentPerson\.accessToken/,
  );
  assert.match(source, /refreshedPerson\.accessToken/);
  assert.match(source, /expirePersonSession/);
  assert.match(source, /localStorage\.setItem\(PROFILES_KEY/);
});

test("integra los contratos comunitarios y de contenido", async () => {
  const source = await readFile(consoleSourceUrl, "utf8");

  for (const endpoint of [
    "/auth/login",
    "/community/users",
    "/community/general/messages",
    "/community/conversations",
    "/community/direct/",
    "/read",
    "/projects",
    "/documents",
  ]) {
    assert.match(source, new RegExp(endpoint.replaceAll("/", "\\/")));
  }
  assert.match(source, /Chat grupal/);
  assert.match(source, /document_id/);
  assert.match(source, /client_id: makeId\(\)/);
  assert.match(source, /ines@example\.com/);
  assert.match(source, /mateo@example\.com/);
  assert.match(source, /Cargar perfiles demo de Inés y Mateo/);
});

test("presenta metadatos y lenguaje propios de inspíraT", async () => {
  const layout = await readFile(layoutUrl, "utf8");

  assert.match(layout, /lang="es"/);
  assert.match(layout, /Consola local de pruebas \| inspíraT/);
  assert.doesNotMatch(layout, /Starter Project|codex-preview/);
});
