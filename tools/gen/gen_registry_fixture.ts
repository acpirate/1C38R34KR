// Generates the Effect and PASSIVE registry parity fixture.
//
//   cd C:\Users\chode\breach
//   node_modules/.bin/tsx ../1C38R34KR/tools/gen/gen_registry_fixture.ts
//
// The registries are validation contracts, so a divergence here does not
// misbehave visibly — it silently accepts content the alpha would reject, or
// rejects content the alpha accepts. Neither shows up until someone edits a
// spreadsheet months later, which is exactly why it is pinned.

import { writeFileSync } from 'node:fs';
import { EFFECT_AXIS_NAMES, EFFECT_PARAM_NAMES, effectContract } from '../../../breach/src/logic/data/effects';
import { passiveContract, passiveEffectIds } from '../../../breach/src/logic/data/passives';

// The Effect registry exposes no enumerator, so the ID list is stated here and
// cross-checked: a new Effect added to the alpha without updating this list
// shows up as a missing contract rather than being silently skipped.
const EFFECT_IDS = [
  'EFFECT_BOMB', 'EFFECT_BUFF', 'EFFECT_ATTACK', 'EFFECT_DRAIN',
  'EFFECT_SHIELD', 'EFFECT_SHAKE', 'EFFECT_LINESLICE', 'EFFECT_TRANSFORM',
];

const effects: Record<string, unknown> = {};
for (const id of EFFECT_IDS) {
  const c = effectContract(id);
  if (!c) throw new Error(`no contract registered for ${id}`);
  effects[id] = {
    required: [...c.required],
    optional: [...(c.optional ?? [])],
    targeted: c.targeted,
    targetKind: c.targetKind ?? null,
    tuple: (c.tuple ?? []).map((f) => ({ name: f.name, min: f.min, max: f.max })),
    axes: [...(c.axes ?? [])],
  };
}

const passives: Record<string, unknown> = {};
for (const id of passiveEffectIds()) {
  const c = passiveContract(id);
  if (!c) throw new Error(`no contract registered for ${id}`);
  passives[id] = { params: [...c.params], activation: c.activation, payload: c.payload };
}

const fixture = {
  _comment: 'Generated from the alpha registries. Do not hand-edit.',
  effect_param_names: [...EFFECT_PARAM_NAMES],
  effect_axis_names: [...EFFECT_AXIS_NAMES],
  effects,
  passives,
};

const out = process.argv[2] ?? '../1C38R34KR/tests/fixtures/registries.json';
writeFileSync(out, JSON.stringify(fixture, null, 2) + '\n');
console.log(`wrote ${out}`);
console.log(`  effects:  ${Object.keys(effects).length}`);
console.log(`  passives: ${Object.keys(passives).length}`);
for (const [id, c] of Object.entries(effects)) {
  const e = c as { required: string[]; tuple: unknown[]; targeted: boolean };
  console.log(`    ${id.padEnd(20)} required=[${e.required.join(',')}] tuple=${e.tuple.length} targeted=${e.targeted}`);
}
