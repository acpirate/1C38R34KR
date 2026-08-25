// Boss differential: ODANSHAY across every eligible Boss-battle HOST.
//
//   node tools/gen/boss_parity.mjs
//   node tools/gen/boss_parity.mjs --seeds 0-49
//
// Reuses the ordinary trace instruments on both sides rather than adding a
// third harness (beta 0.3 §20). A `BOS_*` id in --sys selects the Boss fixture
// route: `headlessBoss` on the alpha, `create_boss_trace_battle` on the beta.
// Neither is reachable from player-facing Quick Match, which stays System-only.

import { execFileSync } from 'node:child_process';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const ALPHA = 'C:\\Users\\chode\\breach';
const BETA = 'C:\\Users\\chode\\1C38R34KR';
const GODOT = join(process.env.USERPROFILE ?? '', 'bin', 'godot.cmd');

// Every HOST a Boss route can actually commit: THRESHOLD is out of the random
// pool, so the four escalation HOSTs are the reachable set. THRESHOLD is
// included anyway as the zero-PASSIVE control — it isolates the mechanic from
// HOST interference.
const HOSTS = 'HST_01,HST_02,HST_03,HST_04,HST_05';
const BOSS = 'BOS_01';

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}

const seeds = arg('seeds', '0-19');
const work = mkdtempSync(join(tmpdir(), 'boss-parity-'));
const args = ['--sys', BOSS, '--host', HOSTS, '--seeds', seeds];

process.stdout.write(`\n[ODANSHAY x ${HOSTS.split(',').length} HOSTs, seeds ${seeds}]\n  alpha … `);
let t0 = Date.now();
const alphaOut = execFileSync(
  join(ALPHA, 'node_modules', '.bin', 'tsx.cmd'),
  ['scripts/trace.ts', ...args],
  { cwd: ALPHA, encoding: 'utf8', maxBuffer: 512 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'], shell: true },
);
const alphaFile = join(work, 'alpha-boss.jsonl');
writeFileSync(alphaFile, alphaOut);
const alphaCount = alphaOut.split('\n').filter((l) => l.startsWith('{')).length;
console.log(`${alphaCount} battles in ${((Date.now() - t0) / 1000).toFixed(1)}s`);

process.stdout.write('  godot … ');
t0 = Date.now();
const godotOut = execFileSync(
  GODOT,
  ['--headless', '--path', BETA, '-s', 'res://tools/trace.gd', '--', ...args],
  { encoding: 'utf8', maxBuffer: 512 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'], shell: true },
);
const godotLines = godotOut.split('\n').map((l) => l.trim()).filter((l) => l.startsWith('{'));
const godotFile = join(work, 'godot-boss.jsonl');
writeFileSync(godotFile, godotLines.join('\n') + '\n');
console.log(`${godotLines.length} battles in ${((Date.now() - t0) / 1000).toFixed(1)}s`);

let failed = 0;
try {
  const out = execFileSync('node', [join(BETA, 'tools', 'gen', 'compare_traces.mjs'), alphaFile, godotFile], {
    encoding: 'utf8',
  });
  process.stdout.write('  ' + out.trim().split('\n').join('\n  ') + '\n');
} catch (e) {
  failed = 1;
  process.stdout.write('  ' + String(e.stdout ?? e.message).trim().split('\n').join('\n  ') + '\n');
}

console.log(failed === 0 ? '\nBOSS PARITY OK' : '\nBOSS PARITY FAILED');
process.exit(failed);
