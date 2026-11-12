// Levanta Deepy en local para el E2E de sincronización de la app: Postgres embebido (pgserver, con el
// python de deepy_core), TODAS las migraciones de deepy_core en orden y deepy_web ya compilado
// (`npm run build` en deepy_web). Nunca toca producción. Mismo patrón que deepy_web/e2e/global-setup.ts.
// Uso: node ios/scripts/servidor_deepy.mjs → imprime "LISTO http://127.0.0.1:3108" y sigue hasta SIGTERM.
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { homedir, tmpdir } from "node:os";
import path from "node:path";

const DEEPY_WEB = process.env.DEEPY_WEB ?? path.join(homedir(), "Personal/deepy_web");
const DEEPY_CORE = process.env.DEEPY_CORE ?? path.join(homedir(), "Personal/deepy_core");
const PUERTO = Number(process.env.KANA_E2E_PUERTO ?? 3108);
const PASSWORD_ROL = "e2e-kana";

function fallar(mensaje) {
  console.error(`servidor_deepy: ${mensaje}`);
  process.exit(1);
}
if (!existsSync(path.join(DEEPY_WEB, ".next/BUILD_ID"))) fallar(`falta compilar deepy_web: cd ${DEEPY_WEB} && npm run build`);
const python = path.join(DEEPY_CORE, ".venv/bin/python");
if (!existsSync(python)) fallar(`falta el entorno de deepy_core: ${python}`);
const { Client } = createRequire(path.join(DEEPY_WEB, "package.json"))("pg");

const datos = mkdtempSync(path.join(tmpdir(), "kana-e2e-pg-"));
const pg = spawn(python, [path.join(DEEPY_WEB, "e2e/pg_start.py"), datos], { stdio: ["pipe", "pipe", "inherit"] });
const uriAdmin = await new Promise((resolve, reject) => {
  let buf = "";
  pg.stdout.on("data", (d) => {
    buf += d;
    if (buf.includes("\n")) resolve(buf.split("\n")[0].trim());
  });
  pg.on("exit", (c) => reject(new Error(`pg_start.py terminó con código ${c}`)));
});

const admin = new Client({ connectionString: uriAdmin });
await admin.connect();
const migraciones = path.join(DEEPY_CORE, "migrations");
for (const f of readdirSync(migraciones).filter((n) => n.endsWith(".sql")).sort()) {
  try {
    await admin.query(readFileSync(path.join(migraciones, f), "utf8"));
  } catch (e) {
    fallar(`la migración ${f} falló: ${e.message}`);
  }
}
await admin.query(`ALTER ROLE deepy_web PASSWORD '${PASSWORD_ROL}'`);
await admin.end();

const app = spawn(process.execPath, [path.join(DEEPY_WEB, "node_modules/next/dist/bin/next"), "start", "-p", String(PUERTO)], {
  cwd: DEEPY_WEB,
  stdio: ["ignore", "ignore", "inherit"],
  env: {
    ...process.env,
    DATABASE_URL: uriAdmin.replace(/^postgresql:\/\/[^@]*@/, `postgresql://deepy_web:${PASSWORD_ROL}@`),
    DEEPY_ACCESS_PASSWORD: "password-de-prueba",
    DEEPY_ACCESS_TOKEN: "token-de-prueba",
    DEEPY_API_TOKEN: "api-token-de-prueba",
    DEEPY_ENLACES_SECRET: "secreto-e2e-kana-enlaces-0123456789abcdef",
  },
});

const url = `http://127.0.0.1:${PUERTO}`;
for (let i = 0; ; i++) {
  try {
    if ((await fetch(`${url}/acceso`, { redirect: "manual" })).status < 500) break;
  } catch {
    // aún no escucha
  }
  if (i > 60) fallar(`Deepy no respondió en ${url}`);
  await new Promise((r) => setTimeout(r, 500));
}
console.log(`LISTO ${url}`);

const cerrar = () => {
  app.kill();
  pg.stdin.end();
  setTimeout(() => {
    pg.kill();
    rmSync(datos, { recursive: true, force: true });
    process.exit(0);
  }, 3000);
};
process.on("SIGTERM", cerrar);
process.on("SIGINT", cerrar);
