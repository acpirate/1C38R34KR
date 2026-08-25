// Run/session differential comparator (Phase E).
//
//   node tools/gen/compare_runs.mjs <alpha.jsonl> <godot.jsonl>
//
// Each engine emits ONE hash line per Run walk over its normalized session
// records. This diffs those lines and, on a mismatch, prints the exact commands
// that reproduce the divergence with full records — hash-first, dump on
// mismatch, which is what §21.2 asks for.

import { readFileSync } from 'node:fs';

const [alphaPath, godotPath] = process.argv.slice(2);
if (!alphaPath || !godotPath) {
  console.error('usage: compare_runs.mjs <alpha.jsonl> <godot.jsonl>');
  process.exit(2);
}

const load = (p) =>
  readFileSync(p, 'utf8')
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.startsWith('{'))
    .map((l) => JSON.parse(l));

const alpha = load(alphaPath);
const godot = load(godotPath);

const bySeed = (rows) => new Map(rows.map((r) => [r.seed, r.hash]));
const a = bySeed(alpha);
const g = bySeed(godot);

const seeds = [...new Set([...a.keys(), ...g.keys()])].sort((x, y) => x - y);
const mismatches = [];
let matched = 0;

for (const seed of seeds) {
  if (!a.has(seed)) { mismatches.push({ seed, why: 'missing from alpha' }); continue; }
  if (!g.has(seed)) { mismatches.push({ seed, why: 'missing from godot' }); continue; }
  if (a.get(seed) !== g.get(seed)) {
    mismatches.push({ seed, why: `alpha ${a.get(seed)} vs godot ${g.get(seed)}` });
    continue;
  }
  matched++;
}

console.log(`matched ${matched}/${seeds.length} run walks`);

if (mismatches.length === 0) {
  console.log('no divergence');
  process.exit(0);
}

console.log(`${mismatches.length} divergent walk(s):`);
for (const m of mismatches.slice(0, 10)) {
  console.log(`  seed ${m.seed} — ${m.why}`);
}
if (mismatches.length > 10) console.log(`  … and ${mismatches.length - 10} more`);

const first = mismatches[0].seed;
console.log('\nreproduce with full records:');
console.log(`  node_modules/.bin/tsx ../1C38R34KR/tools/gen/run_trace_alpha.ts --seed ${first} --full`);
console.log(`  godot --headless -s res://tools/run_trace.gd -- --seed ${first} --full`);
process.exit(1);
