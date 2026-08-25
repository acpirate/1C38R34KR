// Runs the Run/session differential end to end: both engines, then compare.
//
//   node tools/gen/run_parity.mjs             default — 50 run walks
//   node tools/gen/run_parity.mjs --seeds 0-1999
//
// 2,000 walks run in under two seconds across BOTH engines, so there is no
// reason to be stingy with the range. Use a wide one before release.
//
// The battle-layer counterpart is tools/gen/parity.mjs. This one is cheap by
// construction: a run walk plays no battles, so hundreds of walks cost seconds
// rather than the minutes a battle matrix takes. There is deliberately no
// DEEPSCAN tier here — multiplying a session matrix by seeds buys far less than
// the battle matrix does, and §21.2 asks for representative fixtures rather
// than a second exhaustive differential system.
//
// Godot output is captured and re-encoded here because a PowerShell redirect
// writes UTF-16, which the comparator cannot read.

import { execFileSync } from 'node:child_process';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const ALPHA = 'C:\\Users\\chode\\breach';
const BETA = 'C:\\Users\\chode\\1C38R34KR';
const GODOT = join(process.env.USERPROFILE ?? '', 'bin', 'godot.cmd');

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}

const seeds = arg('seeds', '0-49');
const work = mkdtempSync(join(tmpdir(), 'run-parity-'));

process.stdout.write(`\n[run walks, seeds ${seeds}]\n  alpha … `);
let t0 = Date.now();
const alphaOut = execFileSync(
  join(ALPHA, 'node_modules', '.bin', 'tsx.cmd'),
  ['../1C38R34KR/tools/gen/run_trace_alpha.ts', '--seeds', seeds],
  // shell:true because tsx and godot are .cmd shims, which Node cannot spawn
  // directly on Windows (EINVAL).
  { cwd: ALPHA, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'], shell: true },
);
const alphaFile = join(work, 'alpha-runs.jsonl');
writeFileSync(alphaFile, alphaOut);
const alphaCount = alphaOut.split('\n').filter((l) => l.startsWith('{')).length;
console.log(`${alphaCount} walks in ${((Date.now() - t0) / 1000).toFixed(1)}s`);

process.stdout.write('  godot … ');
t0 = Date.now();
const godotOut = execFileSync(
  GODOT,
  ['--headless', '--path', BETA, '-s', 'res://tools/run_trace.gd', '--', '--seeds', seeds],
  { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'], shell: true },
);
const godotLines = godotOut.split('\n').map((l) => l.trim()).filter((l) => l.startsWith('{'));
const godotFile = join(work, 'godot-runs.jsonl');
writeFileSync(godotFile, godotLines.join('\n') + '\n');
console.log(`${godotLines.length} walks in ${((Date.now() - t0) / 1000).toFixed(1)}s`);

let failed = 0;
try {
  const out = execFileSync('node', [join(BETA, 'tools', 'gen', 'compare_runs.mjs'), alphaFile, godotFile], {
    encoding: 'utf8',
  });
  process.stdout.write('  ' + out.trim().split('\n').join('\n  ') + '\n');
} catch (e) {
  failed = 1;
  process.stdout.write('  ' + String(e.stdout ?? e.message).trim().split('\n').join('\n  ') + '\n');
}

console.log(failed === 0 ? '\nRUN PARITY OK' : '\nRUN PARITY FAILED');
process.exit(failed);
