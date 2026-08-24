// Generates the ROUTE PARITY fixture consumed by tests/test_route.gd.
//
// Run from the ALPHA repo so its node_modules resolve, but this file lives in
// the BETA repo so the alpha stays untouched (D-003, D-010):
//
//   cd C:\Users\chode\breach
//   node_modules/.bin/tsx ../1C38R34KR/tools/gen/gen_route_fixture.ts
//
// ---------------------------------------------------------------------------
// What this exists to catch
// ---------------------------------------------------------------------------
//
// Route offer generation is the one part of the beta 0.2 port where a
// *reasonable-looking* reimplementation silently diverges. Every generator
// consumes the route stream in a specific order, and three of them resolve
// their constraints with RETRY LOOPS rather than by exclusion. An
// implementation that sampled without replacement, or filtered the pool before
// picking, would produce offers that are individually legal, satisfy every
// behavioural rule, and still be the wrong offers for a given seed.
//
// Behavioural tests cannot see that. This fixture can: it captures the exact
// offers the alpha produces for fixed seeds, plus the route RNG state after
// each generation, which is what pins the DRAW COUNT rather than just the
// result. A beta that consumed one extra draw would still produce plausible
// offers but a different trailing state.
//
// Beta 0.2 authorization review §C1.

import { writeFileSync } from 'node:fs';
import { loadNodeContent } from '../../../breach/scripts/dataNode';
import { setActiveContent } from '../../../breach/src/logic/data/content';
import { makeRNG } from '../../../breach/src/logic/rng';
import {
  initialPathOffers,
  laterPathOffers,
  bossPathOffers,
  acquireUpgrade,
  randomBuild,
  randomSystem,
  randomHost,
  type PendingPath,
} from '../../../breach/src/logic/session';
import { inventoryProgramIds, DEFAULT_HACKER_ID, DEFAULT_DECK_ID } from '../../../breach/src/logic/data/content';

const SEEDS = [0, 1, 7, 42, 1337, 2147483647];
const BOSS_ID = 'BOS_01';

interface Generation {
  kind: 'initial' | 'later' | 'boss';
  step: number;
  acquired: string[];       // acquisitions going IN
  offers: {
    index: number;
    opponentKind: string;
    opponentId: string;
    hostId: string;
    upgradeId: string;
  }[];
  upgradeExhausted: boolean;
  stateAfter: number;       // route RNG state once generation finished
}

// One full four-battle route walk. Taking offer 0 every time is arbitrary but
// deterministic, and it drives the acquired pool down to the exhaustion case by
// the final route — which is exactly the edge worth pinning.
function walk(seed: number): Generation[] {
  const rng = makeRNG(seed);
  const out: Generation[] = [];
  let acquired: string[] = [];

  const record = (kind: Generation['kind'], step: number, going_in: string[], p: PendingPath): void => {
    out.push({
      kind,
      step,
      acquired: [...going_in],
      offers: p.offers.map((o) => ({
        index: o.index,
        opponentKind: o.opponentKind,
        opponentId: o.opponentId,
        hostId: o.hostId,
        upgradeId: o.upgradeId,
      })),
      upgradeExhausted: p.upgradeExhausted,
      stateAfter: rng.getState(),
    });
    acquired = acquireUpgrade(going_in, p.offers[0].upgradeId);
  };

  record('initial', 1, acquired, initialPathOffers(rng, acquired));
  record('later', 2, acquired, laterPathOffers(rng, 2, acquired));
  record('later', 3, acquired, laterPathOffers(rng, 3, acquired));
  record('boss', 4, acquired, bossPathOffers(rng, 4, BOSS_ID, acquired));
  return out;
}

const result = loadNodeContent();
const errors = result.issues.filter((i) => i.severity === 'error');
if (errors.length > 0 || !result.content) {
  console.error('alpha content failed to load; cannot generate a route fixture');
  for (const e of errors) console.error('  ', e);
  process.exit(1);
}
setActiveContent(result.content);

// Random Quick Match setup, from one isolated stream. The DRAW ORDER is the
// point: the alpha rolls the BUILD first, then the System, then the HOST.
// Rolling the opponent first would be the natural reading and would produce a
// different, still-legal, result for the same seed.
function quickMatch(seed: number): Record<string, unknown> {
  const rng = makeRNG(seed);
  const inventory = inventoryProgramIds(DEFAULT_HACKER_ID, DEFAULT_DECK_ID);
  const build = randomBuild(inventory, rng);
  const systemId = randomSystem(rng, 'QUICK_RANDOM').id;
  const hostId = randomHost(rng);
  return { build, systemId, hostId, stateAfter: rng.getState() };
}

const fixture = {
  note: 'Generated from the alpha by tools/gen/gen_route_fixture.ts. Do not hand-edit.',
  bossId: BOSS_ID,
  walks: Object.fromEntries(SEEDS.map((s) => [String(s), walk(s)])),
  quickMatch: Object.fromEntries(SEEDS.map((s) => [String(s), quickMatch(s)])),
};

const out = 'C:\\Users\\chode\\1C38R34KR\\tests\\fixtures\\route.json';
writeFileSync(out, JSON.stringify(fixture, null, 2) + '\n');
console.log(`wrote ${out} — ${SEEDS.length} seeds x 4 generations`);
