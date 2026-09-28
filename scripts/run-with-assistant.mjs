import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import net from 'node:net';
import { setTimeout } from 'node:timers/promises';
import { CodexSession, createAssistantServer } from './assistant-server.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const port = Number(process.env.MANA_ASSISTANT_PORT || 8012);
const apiPort = Number(process.env.MANA_API_PORT || 8013);
if (port === apiPort) throw new Error('Choisir deux ports distincts.');
for (const value of [port, apiPort]) {
  if (!Number.isInteger(value) || value < 1 || value > 65535) throw new Error('Port invalide');
  const probe = net.createServer();
  await new Promise((resolve, reject) => probe.once('error', reject).listen(value, '127.0.0.1', resolve));
  await new Promise(resolve => probe.close(resolve));
}
const bundled = path.join(root, '.tools', 'R', 'bin', process.platform === 'win32' ? 'Rscript.exe' : 'Rscript');
const executable = process.env.MANA_RSCRIPT || (existsSync(bundled) ? bundled : 'Rscript');
const api = spawn(executable, ['scripts/run-api.R'], {
  cwd: root, windowsHide: true, stdio: ['ignore', 'inherit', 'inherit'],
  env: { ...process.env, R_LIBS_USER: [path.join(root, '.r-lib'), process.env.R_LIBS_USER].filter(Boolean).join(path.delimiter),
    MTGCODEX_API_PROJECT_DIR: root, MTGCODEX_API_HOST: '127.0.0.1', MTGCODEX_API_PORT: String(apiPort), MTGCODEX_API_SWAGGER: 'false' }
});
let apiError;
api.on('error', error => { apiError = error; });
const session = new CodexSession();
const server = createAssistantServer({ session, upstream: `http://127.0.0.1:${apiPort}` });
function close() { session.close(); server.close(); api.kill(); }
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, close);
api.on('exit', () => { session.close(); server.close(); });
try {
  let ready = false;
  for (let attempt = 0; attempt < 40; attempt++) {
    if (apiError) throw apiError;
    if (api.exitCode !== null) throw new Error('L’API R s’est arrêtée. Voir son erreur ci-dessus.');
    try {
      const response = await fetch(`http://127.0.0.1:${apiPort}/health`, { signal: AbortSignal.timeout(500) });
      if (response.ok) { ready = true; break; }
    } catch { /* Wait for Plumber startup. */ }
    await setTimeout(500);
  }
  if (!ready) throw new Error('L’API R ne répond pas.');
  await new Promise((resolve, reject) => server.once('error', reject).listen(port, '127.0.0.1', resolve));
  console.log(`Mana Engine + assistant : http://127.0.0.1:${port}/ui`);
} catch (error) { close(); throw error; }
