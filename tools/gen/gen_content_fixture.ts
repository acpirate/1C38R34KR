// Generates the content-layer parity fixtures consumed by Phase 2 tests.
//
//   cd C:\Users\chode\breach
//   node_modules/.bin/tsx ../1C38R34KR/tools/gen/gen_content_fixture.ts
//
// Three fixtures, each pinning a different layer of the content pipeline so a
// divergence lands on the stage that caused it rather than surfacing as one
// opaque fingerprint mismatch at the end:
//
//   areas.json    — area-pattern registry. CELL ORDER matters: the patterns are
//                   built by first-seen-order union and the ordered cells are
//                   fingerprint input, so a port that produced the same SET in a
//                   different order would pass a naive check and change the
//                   fingerprint.
//   csv_rows.json — the alpha parser's output for all ten datasets, including
//                   1-based start lines. Pins BOM handling, empty-row skipping,
//                   quote escaping, and line tracking.
//   content.json  — the fingerprint, plus the resolved facts Phase 2 must agree
//                   on. A5: also reports whether any fingerprinted value is
//                   non-integer, which decides how hard byte-exact canonical
//                   serialization will be.

import { readFileSync, writeFileSync } from 'node:fs';
import { AREA_PATTERNS, AREA_PATTERN_ORDER } from '../../../breach/src/logic/data/areas';
import { parseCsv } from '../../../breach/src/logic/data/csv';
// Reuse the alpha's own adapter rather than restating the DataFiles mapping —
// it already owns the filename-to-slot wiring, and duplicating it here would be
// a second authority that could drift.
import { loadNodeContent } from '../../../breach/scripts/dataNode';

const OUT_DIR = process.argv[2] ?? '../1C38R34KR/tests/fixtures';
const DATA_DIR = 'data';

// The beta shortened the filenames; contents are byte-identical.
const DATASETS: Record<string, string> = {
  bos: 'breach datastructures - BOS.csv',
  dek: 'breach datastructures - DEK.csv',
  fnc: 'breach datastructures - FNC.csv',
  hak: 'breach datastructures - HAK.csv',
  hst: 'breach datastructures - HST.csv',
  prg_h: 'breach datastructures - PRG_H.csv',
  prg_s: 'breach datastructures - PRG_S.csv',
  psv: 'breach datastructures - PSV.csv',
  sys: 'breach datastructures - SYS.csv',
  upg: 'breach datastructures - UPG.csv',
};

// ---------------------------------------------------------------------------
// areas
// ---------------------------------------------------------------------------

const areas = {
  _comment: 'Generated from the alpha. Cell ORDER is significant — it is fingerprint input.',
  order: [...AREA_PATTERN_ORDER],
  patterns: Object.fromEntries(
    Object.entries(AREA_PATTERNS).map(([id, cells]) => [id, cells.map((c) => [c.x, c.y])]),
  ),
};
writeFileSync(`${OUT_DIR}/areas.json`, JSON.stringify(areas, null, 2) + '\n');
console.log('areas.json');
for (const id of AREA_PATTERN_ORDER) {
  console.log(`  ${id.padEnd(28)} ${AREA_PATTERNS[id].length} cells`);
}

// ---------------------------------------------------------------------------
// csv rows
// ---------------------------------------------------------------------------

const raw: Record<string, string> = {};
const csvRows: Record<string, unknown> = {};
for (const [key, filename] of Object.entries(DATASETS)) {
  const text = readFileSync(`${DATA_DIR}/${filename}`, 'utf8');
  raw[key] = text;
  const parsed = parseCsv(text);
  csvRows[key] = {
    rows: parsed.rows.map((r) => ({ line: r.line, fields: r.fields })),
    error: parsed.error ?? null,
  };
}
writeFileSync(
  `${OUT_DIR}/csv_rows.json`,
  JSON.stringify({ _comment: 'Alpha parseCsv output. Pins line numbers and empty-row handling.', datasets: csvRows }, null, 2) + '\n',
);
console.log('\ncsv_rows.json');
for (const [key, v] of Object.entries(csvRows)) {
  console.log(`  ${key.padEnd(6)} ${(v as { rows: unknown[] }).rows.length} rows`);
}

// ---------------------------------------------------------------------------
// loaded content
// ---------------------------------------------------------------------------

const result = loadNodeContent();

const errors = result.issues.filter((i) => i.severity === 'error');
const warnings = result.issues.filter((i) => i.severity === 'warning');
const content = result.content;

console.log('\ncontent.json');
console.log(`  errors:   ${errors.length}`);
console.log(`  warnings: ${warnings.length}`);
console.log(`  fingerprint: ${content?.fingerprint ?? '(none — load failed)'}`);

if (errors.length) {
  console.log('\n  the alpha datasets do not load cleanly:');
  for (const e of errors.slice(0, 10)) console.log(`    ${JSON.stringify(e)}`);
}

// A5: byte-exact canonical serialization is straightforward if every
// fingerprinted value is an integer, and fiddly if any is a float.
function scanNumbers(v: unknown, path: string, out: string[]): void {
  if (typeof v === 'number') {
    if (!Number.isInteger(v)) out.push(`${path} = ${v}`);
    return;
  }
  if (Array.isArray(v)) {
    v.forEach((x, i) => scanNumbers(x, `${path}[${i}]`, out));
    return;
  }
  if (v && typeof v === 'object') {
    for (const [k, x] of Object.entries(v)) scanNumbers(x, `${path}.${k}`, out);
  }
}
const nonIntegers: string[] = [];
scanNumbers(content ?? {}, 'content', nonIntegers);

writeFileSync(
  `${OUT_DIR}/content.json`,
  JSON.stringify(
    {
      _comment: 'Generated from the alpha. The fingerprint here must be reproduced byte-for-byte.',
      fingerprint: content?.fingerprint ?? null,
      error_count: errors.length,
      warning_count: warnings.length,
      // The actual diagnostics, not just counts. A count match can be a
      // coincidence; comparing dataset/id/field/reason proves the warning RULES
      // ported, and names which one is missing when they have not.
      issues: result.issues.map((i) => ({
        severity: i.severity,
        dataset: i.dataset,
        id: i.id ?? null,
        field: i.field ?? null,
        reason: i.reason,
      })),
      non_integer_values: nonIntegers,
    },
    null,
    2,
  ) + '\n',
);

console.log(`\n  A5 — non-integer values reachable in content: ${nonIntegers.length}`);
for (const n of nonIntegers.slice(0, 20)) console.log(`    ${n}`);
