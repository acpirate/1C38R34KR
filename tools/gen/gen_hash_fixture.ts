// Generates djb2 and JSON-canonicalization vectors for the fingerprint port.
//
//   cd C:\Users\chode\breach
//   node_modules/.bin/tsx ../1C38R34KR/tools/gen/gen_hash_fixture.ts
//
// The content fingerprint has two independent halves, and pinning them
// separately means a mismatch says WHICH half is wrong:
//
//   1. the canonical string — JS `JSON.stringify` of the normalized content
//   2. djb2 over that string, formatted as `${hex8}-${length.toString(36)}`
//
// Verified end to end by the real fingerprint, but that check alone would only
// ever say "different", with 11,170 characters of canonical string to search.
//
// The djb2 algorithm below is copied verbatim from the alpha's
// computeFingerprint. It is reproduced rather than imported because it is a
// local inside that function, and exporting it would mean editing the alpha
// beyond the single sanctioned trace instrument (D-010).

import { writeFileSync } from 'node:fs';

function djb2(canonical: string): string {
  let h = 5381;
  for (let i = 0; i < canonical.length; i++) h = ((h << 5) + h + canonical.charCodeAt(i)) >>> 0;
  return `${h.toString(16).padStart(8, '0')}-${canonical.length.toString(36)}`;
}

const STRINGS = [
  '',
  'a',
  'abc',
  '{}',
  '{"schema":1}',
  // Boundary-ish inputs for the 32-bit accumulate-and-mask.
  'x'.repeat(1000),
  // Control characters, deliberately excluding U+0000: GDScript strings are
  // NUL-terminated internally and cannot hold an embedded NUL, so such a vector
  // is untestable on that side rather than awkward. Authored content contains no
  // control characters at all; these pin the escaping path.
  String.fromCharCode(0x01, 0x1f, 0x7f),
  // Non-ASCII: charCodeAt yields UTF-16 code units, so a character outside the
  // BMP contributes TWO units. A GDScript port using codepoints would diverge
  // here and nowhere else — worth pinning even though authored content is ASCII.
  'café',
  'naïve résumé',
  '日本語',
  '🎮',
  'a🎮b',
  // Shapes the real canonical string contains.
  '{"id":"AREA_SELF","cells":[{"x":0,"y":0}]}',
  '[{"x":-1,"y":-1},{"x":0,"y":-1}]',
  JSON.stringify({ a: 1, b: [1, 2, 3], c: { d: 'e' }, f: true, g: null }),
];

const vectors = STRINGS.map((s) => ({
  input: s,
  utf16_length: s.length,
  hash: djb2(s),
}));

// How JS renders values inside a canonical string, which the GDScript
// serializer must reproduce exactly.
const serialization = {
  integer_one: JSON.stringify(1),
  float_one: JSON.stringify(1.0),
  negative: JSON.stringify(-1),
  zero: JSON.stringify(0),
  true_value: JSON.stringify(true),
  false_value: JSON.stringify(false),
  null_value: JSON.stringify(null),
  empty_string: JSON.stringify(''),
  quote_in_string: JSON.stringify('say "hi"'),
  backslash: JSON.stringify('a\\b'),
  newline: JSON.stringify('a\nb'),
  tab: JSON.stringify('a\tb'),
  unicode: JSON.stringify('café'),
  empty_array: JSON.stringify([]),
  empty_object: JSON.stringify({}),
  nested: JSON.stringify({ b: 2, a: 1 }),
  array_of_objects: JSON.stringify([{ x: 1, y: 2 }]),
};

const fixture = {
  _comment: 'djb2 and JSON canonicalization vectors for the fingerprint port. Do not hand-edit.',
  algorithm: 'djb2, h = ((h << 5) + h + charCodeAt(i)) >>> 0, seed 5381',
  format: '${hex8}-${length.toString(36)}',
  vectors,
  serialization,
};

const out = process.argv[2] ?? '../1C38R34KR/tests/fixtures/hash.json';
writeFileSync(out, JSON.stringify(fixture, null, 2) + '\n');
console.log(`wrote ${out}`);
for (const v of vectors) {
  const label = v.input.length > 24 ? `${v.input.slice(0, 21)}...` : v.input;
  console.log(`  ${JSON.stringify(label).padEnd(30)} len=${String(v.utf16_length).padStart(4)}  ${v.hash}`);
}
console.log('\n  JS serialization forms:');
for (const [k, v] of Object.entries(serialization)) console.log(`    ${k.padEnd(18)} ${v}`);
