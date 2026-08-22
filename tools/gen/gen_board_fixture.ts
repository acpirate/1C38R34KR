// Generates board-generation and Sync-detection parity fixtures.
//
//   cd C:\Users\chode\breach
//   node_modules/.bin/tsx ../1C38R34KR/tools/gen/gen_board_fixture.ts
//
// Board generation is where RNG consumption ORDER first becomes observable.
// The distribution of Packets could match perfectly while the draw sequence
// differs, and everything downstream would then diverge from the first turn.
// Emitting the full board per seed — plus the RNG state and id counter AFTER
// generation — pins the sequence itself, not just its statistics.
//
// The retry loops make this a sharp test: `generateInitialBoard` redraws on a
// completed run and restarts the whole board if the result has a pre-existing
// Sync or no legal move, so the number of draws consumed depends on the
// rejection path taken. A port that redraws at a different point lands on a
// different board.

import { writeFileSync } from 'node:fs';
import { generateInitialBoard, findValidMove, reshuffleBoard } from '../../../breach/src/logic/board';
import { computeLineClears, detectMatches } from '../../../breach/src/logic/match';
import { makeRNG } from '../../../breach/src/logic/rng';
import type { Board, Tile } from '../../../breach/src/logic/types';

const SEEDS = [0, 1, 7, 42, 1337, 99999, 2147483647];

// [id, kind, color, shape] — kind 0 standard, 1 neutral. Compact enough that a
// seven-seed fixture stays readable, explicit enough that a mismatch names the
// exact cell.
function encodeBoard(board: Board): number[][] {
  const out: number[][] = [];
  for (const row of board) {
    for (const t of row) {
      const tile = t as Tile;
      out.push([tile.id, tile.kind === 'neutral' ? 1 : 0, tile.color ?? -1, tile.shape ?? -1]);
    }
  }
  return out;
}

const CONDITION_INDEX: Record<string, number> = { color: 0, shape: 1, neutral: 2 };
const ORIENTATION_INDEX: Record<string, number> = { h: 0, v: 1 };

function encodeMatches(board: Board): unknown[] {
  return detectMatches(board).map((m) => ({
    condition: CONDITION_INDEX[m.condition],
    value: m.value,
    length: m.length,
    isLine: m.isLine,
    orientation: m.orientation ? ORIENTATION_INDEX[m.orientation] : -1,
    cells: m.cells.map((c) => [c.x, c.y]),
  }));
}

const cases = SEEDS.map((seed) => {
  const rng = makeRNG(seed);
  const gen = { rng, nextId: 1 };
  const board = generateInitialBoard(gen);
  // Captured HERE, not in the returned object literal: that literal is
  // evaluated at `return` time, by which point reshuffleBoard below has already
  // consumed draws and moved the state on.
  const nextIdAfterGenerate = gen.nextId;
  const rngStateAfterGenerate = rng.getState();

  // A settled opening board has no Syncs by construction, so detection is
  // exercised against deliberately disturbed states as well: every east/south
  // swap that produces a Sync is a real detection case with real merges.
  const disturbed: unknown[] = [];
  const move = findValidMove(board);
  if (move) {
    const t = board[move.a.y][move.a.x];
    board[move.a.y][move.a.x] = board[move.b.y][move.b.x];
    board[move.b.y][move.b.x] = t;
    const matches = detectMatches(board);
    disturbed.push({
      swap: [[move.a.x, move.a.y], [move.b.x, move.b.y]],
      matches: encodeMatches(board),
      lineClears: computeLineClears(matches).map((lc) => ({
        orientation: ORIENTATION_INDEX[lc.orientation],
        index: lc.index,
      })),
    });
    // restore
    const u = board[move.a.y][move.a.x];
    board[move.a.y][move.a.x] = board[move.b.y][move.b.x];
    board[move.b.y][move.b.x] = u;
  }

  // Reshuffle is a permutation, so it consumes shuffle draws and must land on
  // the same arrangement.
  const rstate = { board, rng, nextId: gen.nextId };
  reshuffleBoard(rstate);

  return {
    seed,
    board: encodeBoard(board),
    nextIdAfterGenerate,
    rngStateAfterGenerate,
    firstValidMove: move ? [[move.a.x, move.a.y], [move.b.x, move.b.y]] : null,
    disturbed,
    reshuffled: encodeBoard(rstate.board),
    rngStateAfterReshuffle: rng.getState(),
  };
});

const fixture = {
  _comment: 'Board generation and Sync detection, generated from the alpha. Pins RNG consumption ORDER.',
  boardWidth: 8,
  boardHeight: 8,
  cases,
};

const out = process.argv[2] ?? '../1C38R34KR/tests/fixtures/board.json';
writeFileSync(out, JSON.stringify(fixture, null, 2) + '\n');
console.log(`wrote ${out}`);
for (const c of cases) {
  const neutrals = c.board.filter((t) => t[1] === 1).length;
  console.log(
    `  seed ${String(c.seed).padStart(10)}  nextId=${String(c.nextIdAfterGenerate).padStart(4)}` +
      `  neutrals=${String(neutrals).padStart(2)}  disturbedMatches=${(c.disturbed[0] as { matches: unknown[] } | undefined)?.matches.length ?? 0}`,
  );
}
