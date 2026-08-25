// The ALPHA half of the Run differential harness.
//
// Run from the alpha repo so its node_modules resolve, but this file lives in
// the BETA repo so the alpha stays untouched (D-003, D-010):
//
//   cd C:\Users\chode\breach
//   node_modules/.bin/tsx ../1C38R34KR/tools/gen/run_trace_alpha.ts --seeds 0-199
//   node_modules/.bin/tsx ../1C38R34KR/tools/gen/run_trace_alpha.ts --seed 42 --full
//
// Emits exactly the record format `tools/run_trace.gd` emits, so the two can be
// hashed and diffed. Every token order, separator, and spelling below is
// load-bearing; see that file's header for why the records are ordered token
// arrays rather than stringified objects.
//
// THE CHOICE POLICY MUST MATCH. `choose()` is the beta's `_choose` verbatim.

import { createHash } from 'node:crypto';
import { loadNodeContent } from '../../../breach/scripts/dataNode';
import {
  setActiveContent,
  DEFAULT_HACKER_ID,
  DEFAULT_DECK_ID,
  PATH_CHOICE_COUNT,
  inventoryProgramIds,
} from '../../../breach/src/logic/data/content';
import {
  commitBossSelection,
  commitSetupHacker,
  commitSetupDeck,
  openPathChoice,
  selectPath,
  resolveRunIce,
  RUN_LENGTH,
  type RunInfo,
  type RunStep,
} from '../../../breach/src/logic/session';
import { DEFAULT_BATTLE_SETTINGS } from '../../../breach/src/logic/constants';

const BOSS_ID = 'BOS_01';

function arg(name: string, fallback?: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}

function parseRange(spec: string): number[] {
  if (!spec.includes('-')) return [Number(spec)];
  const [lo, hi] = spec.split('-').map(Number);
  return Array.from({ length: hi - lo + 1 }, (_, i) => lo + i);
}

const full = process.argv.includes('--full');
const single = arg('seed');
const seeds = single !== undefined ? [Number(single)] : parseRange(arg('seeds', '0')!);

// The beta's `_choose`, verbatim.
const choose = (seed: number, step: number): number => (seed + step) % PATH_CHOICE_COUNT;

function walk(seed: number): string[] {
  const lines: string[] = [];

  let setup = commitBossSelection(BOSS_ID, { ...DEFAULT_BATTLE_SETTINGS }, seed);
  setup = commitSetupHacker(setup, DEFAULT_HACKER_ID);
  let r: RunInfo = commitSetupDeck(setup, DEFAULT_DECK_ID);

  lines.push(
    [
      'setup',
      r.bossId,
      r.identity.hackerId,
      r.identity.deckId,
      String(r.hackerMaxLink),
      inventoryProgramIds(r.identity.hackerId, r.identity.deckId).join(','),
      r.build.join(','),
    ].join('|'),
  );

  for (;;) {
    const pending = r.pendingPath!;
    lines.push(
      [
        'offers',
        String(pending.step),
        ...pending.offers.map((o) =>
          [String(o.index), o.opponentKind, o.opponentId, o.hostId, o.upgradeId].join(':'),
        ),
        `exhausted=${pending.upgradeExhausted ? '1' : '0'}`,
        `route=${r.routeRngState}`,
      ].join('|'),
    );

    const choice = choose(seed, r.step);
    r = selectPath(r, choice);
    lines.push(
      [
        'commit',
        String(r.step),
        String(choice),
        r.opponent.kind,
        r.opponent.id,
        r.hostId,
        r.upgradeIds.join(','),
        r.build.join(','),
        r.buildOrigin,
        `ice=${resolveRunIce(r.settings, r.opponent, r.step)}`,
        `route=${r.routeRngState}`,
      ].join('|'),
    );

    if (r.step === RUN_LENGTH) {
      // The beta stops here rather than fighting the Boss. The alpha CAN
      // continue, but the comparison is of the pre-Boss layer, so this emits
      // the same terminal record the beta does.
      lines.push(
        ['stop', 'PENDING_BOSS_BATTLE', String(r.step), r.opponent.id, r.hostId, r.upgradeIds.join(',')].join('|'),
      );
      break;
    }

    r = openPathChoice(r, (r.step + 1) as RunStep);
  }

  return lines;
}

const result = loadNodeContent();
const errors = result.issues.filter((i) => i.severity === 'error');
if (errors.length > 0 || !result.content) {
  console.error('alpha content failed to load');
  for (const e of errors) console.error('  ', e);
  process.exit(1);
}
setActiveContent(result.content);

for (const seed of seeds) {
  const lines = walk(seed);
  if (full) {
    console.log(`# seed ${seed}`);
    for (const l of lines) console.log(l);
  } else {
    const h = createHash('sha256');
    for (const l of lines) h.update(l + '\n');
    console.log(JSON.stringify({ seed, hash: h.digest('hex').slice(0, 16) }));
  }
}
