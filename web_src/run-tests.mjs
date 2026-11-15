// Bundle test/*.test.ts with esbuild, then run them with Node's test runner.
// (Node strips types itself only from 22.18, so bundle to stay version-proof.)
import { readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import * as esbuild from 'esbuild';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '.test-build');
const entries = readdirSync(join(here, 'test'))
  .filter((f) => f.endsWith('.test.ts'))
  .map((f) => join(here, 'test', f));

await esbuild.build({
  entryPoints: entries,
  outdir: out,
  outExtension: { '.js': '.mjs' },
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node20',
  logLevel: 'warning',
});

const files = entries.map((e) => join(out, e.split(/[\\/]/).pop().replace(/\.ts$/, '.mjs')));
const result = spawnSync(process.execPath, ['--test', ...files], { stdio: 'inherit' });
process.exit(result.status ?? 1);
