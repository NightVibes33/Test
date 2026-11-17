/**
 * Real DeepAI Code 0.3.40 startup with error reporting on iOS.
 * Uses the original unmodified bin.mjs main() path and network bootstrap.
 */
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
const entry = join(dirname(fileURLToPath(import.meta.url)), 'apps/server/dist/bin.mjs');
const show = (label, error) => {
  try { process.stderr.write(`[DeepAI iOS] ${label}: ${error?.stack ?? String(error)}\n`); }
  catch {}
};
process.on('uncaughtExceptionMonitor', error => show('uncaught exception', error));
process.on('unhandledRejection', error => show('unhandled rejection', error));
process.argv[1] = entry;
try {
  process.stderr.write('[DeepAI iOS] Entering original DeepAI Code 0.3.40 CLI\n');
  await import(pathToFileURL(entry).href);
} catch (error) {
  show('Original DeepAI CLI failed to load', error);
  process.exitCode = 1;
}
