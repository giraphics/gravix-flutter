// Bundle the gravix worlds into ../assets/www/gravix_worlds.js.
//
//   node build.mjs           one minified build, no source maps
//   node build.mjs --watch   rebuild on change, with source maps (local only)
//
// One file serves every platform: Flutter web loads it from index.html, and
// the Windows / Android WebViews load it from assets/www/world.html.
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import * as esbuild from 'esbuild';

const here = dirname(fileURLToPath(import.meta.url));
const watch = process.argv.includes('--watch');

const ctx = await esbuild.context({
  entryPoints: [join(here, 'src', 'worlds.ts')],
  outfile: join(here, '..', 'assets', 'www', 'gravix_worlds.js'),
  bundle: true,
  format: 'iife',
  platform: 'browser',
  // Android System WebView and WebView2 are evergreen Chromium; es2020 keeps
  // older Android WebViews working too.
  target: 'es2020',
  minify: !watch,
  // The bundle ships inside the app and on GitHub Pages; maps stay local.
  sourcemap: watch,
  logLevel: 'info',
});

if (watch) {
  await ctx.watch();
} else {
  await ctx.rebuild();
  await ctx.dispose();
}
