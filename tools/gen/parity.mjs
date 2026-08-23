// Runs the differential parity check end to end: both engines, then compare.
//
//   node tools/gen/parity.mjs              fast tier — 150 battles, ~2.5 min
//   node tools/gen/parity.mjs --deepscan   the full §6.1 matrix, ~90 min
//   node tools/gen/parity.mjs --variant reinforced --seeds 0-9
//
// Two tiers by design (D-023). The fast tier is for the iterate-and-check loop;
// DEEPSCAN is the release gate. The matrix is never shrunk to make it faster —
// if it becomes painful, batch more work per Godot process instead.
//
// Godot output is captured and re-encoded here because a PowerShell redirect
// writes UTF-16, which the comparator cannot read.

import { execFileSync } from 'node:child_process';
import { writeFileSync, readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const ALPHA = 'C:\\Users\\chode\\breach';
const BETA = 'C:\\Users\\chode\\1C38R34KR';
const GODOT = join(process.env.USERPROFILE ?? '', 'bin', 'godot.cmd');

const SYSTEMS = 'SYS_01,SYS_02,SYS_03';
const HOSTS = 'HST_01,HST_02,HST_03,HST_04,HST_05';

// The full matrix: 200 default seeds plus 50 per settings variation, over all
// 15 pairings — 5,250 battles per engine.
const DEEPSCAN = [
  { variant: 'default', seeds: '0-199' },
  { variant: 'reinforced', seeds: '0-49' },
  { variant: 'timer', seeds: '0-49' },
  { variant: 'uncapped', seeds: '0-49' },
];

const FAST = [{ variant: 'default', seeds: '0-9' }];

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}

const passes = process.argv.includes('--deepscan')
  ? DEEPSCAN
  : arg('variant')
    ? [{ variant: arg('variant'), seeds: arg('seeds', '0-9') }]
    : FAST;

const work = mkdtempSync(join(tmpdir(), 'parity-'));
let failed = 0;

for (const pass of passes) {
  const label = `${pass.variant} seeds ${pass.seeds}`;
  const args = ['--variant', pass.variant, '--seeds', pass.seeds, '--sys', SYSTEMS, '--host', HOSTS];

  process.stdout.write(`\n[${label}]\n  alpha … `);
  let t0 = Date.now();
  const alphaOut = execFileSync(
    join(ALPHA, 'node_modules', '.bin', 'tsx.cmd'),
    ['scripts/trace.ts', ...args],
    // shell:true because tsx and godot are .cmd shims, which Node cannot
    // spawn directly on Windows (EINVAL).
    { cwd: ALPHA, encoding: 'utf8', maxBuffer: 512 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'], shell: true },
  );
  const alphaFile = join(work, `alpha-${pass.variant}.jsonl`);
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
  // Godot prints its banner to stdout; keep only record lines.
  const godotLines = godotOut.split('\n').map((l) => l.trim()).filter((l) => l.startsWith('{'));
  const godotFile = join(work, `godot-${pass.variant}.jsonl`);
  writeFileSync(godotFile, godotLines.join('\n') + '\n');
  console.log(`${godotLines.length} battles in ${((Date.now() - t0) / 1000).toFixed(1)}s`);

  try {
    const out = execFileSync('node', [join(BETA, 'tools', 'gen', 'compare_traces.mjs'), alphaFile, godotFile], {
      encoding: 'utf8',
    });
    process.stdout.write('  ' + out.trim().split('\n').join('\n  ') + '\n');
  } catch (e) {
    failed++;
    process.stdout.write('  ' + String(e.stdout ?? e.message).trim().split('\n').join('\n  ') + '\n');
  }
}

console.log(failed === 0 ? '\nPARITY OK' : `\nPARITY FAILED in ${failed} pass(es)`);
process.exit(failed === 0 ? 0 : 1);
