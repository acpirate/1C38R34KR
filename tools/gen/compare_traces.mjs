// Differential comparator (D-019).
//
//   node tools/gen/compare_traces.mjs <alpha.jsonl> <godot.jsonl>
//
// Each engine emits ONE hash line per battle over its normalized event stream.
// This diffs those lines. On a mismatch it reports the battle's identity in the
// exact form both trace tools accept, so the divergence can be reproduced with
// full records immediately:
//
//   node_modules/.bin/tsx scripts/trace.ts --sys S --host H --seed N --full
//   godot --headless -s res://tools/trace.gd -- --sys S --host H --seed N --full
//
// Comparing hashes rather than whole traces is what keeps the full matrix
// affordable: 5,250 battles per engine would otherwise be gigabytes of JSONL,
// and the pressure to shrink the matrix for performance is exactly what the
// authorization forbids.

import { readFileSync } from 'node:fs';

const [alphaPath, godotPath] = process.argv.slice(2);
if (!alphaPath || !godotPath) {
  console.error('usage: compare_traces.mjs <alpha.jsonl> <godot.jsonl>');
  process.exit(2);
}

const load = (p) =>
  readFileSync(p, 'utf8')
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.startsWith('{'))
    .map((l) => JSON.parse(l));

const key = (b) => `${b.variant}/${b.sys}/${b.host}/${b.seed}`;

const alpha = load(alphaPath);
const godot = new Map(load(godotPath).map((b) => [key(b), b]));

const divergences = [];
let matched = 0;

for (const a of alpha) {
  const g = godot.get(key(a));
  if (!g) {
    divergences.push({ key: key(a), reason: 'absent from the Godot run' });
    continue;
  }
  // Event count is compared alongside the hash. A hash mismatch alone says
  // only "different"; a count difference immediately distinguishes "diverged
  // partway" from "same length, different content".
  if (g.hash === a.hash && g.events === a.events) {
    matched++;
    continue;
  }
  divergences.push({
    key: key(a),
    reason:
      `alpha ${a.events}ev/${a.turns}t/${a.winner}` +
      `  godot ${g.events}ev/${g.turns}t/${g.winner}` +
      (g.events === a.events ? '  [same length, different content]' : ''),
    repro: a,
  });
}

console.log(`matched ${matched}/${alpha.length} battles`);

if (divergences.length === 0) {
  console.log('no divergence');
  process.exit(0);
}

console.log(`\n${divergences.length} divergence(s):\n`);
for (const d of divergences.slice(0, 15)) {
  console.log(`  ${d.key}`);
  console.log(`    ${d.reason}`);
  if (d.repro) {
    console.log(`    reproduce:`);
    console.log(`      node_modules/.bin/tsx scripts/trace.ts --sys ${d.repro.sys} --host ${d.repro.host} --seed ${d.repro.seed} --variant ${d.repro.variant} --full`);
    console.log(`      godot --headless -s res://tools/trace.gd -- --sys ${d.repro.sys} --host ${d.repro.host} --seed ${d.repro.seed} --variant ${d.repro.variant} --full`);
  }
}
if (divergences.length > 15) console.log(`  … and ${divergences.length - 15} more`);

process.exit(1);
