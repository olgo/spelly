// deno test --allow-read supabase/functions/_shared/rules.test.ts
//
// Liest dieselbe Falldatei wie app/test/domain/rules_test.dart. Wer hier etwas
// ändert, muss dort dieselben Zahlen sehen.

import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { emptyBoard, playMove, RuleError, type Board, type Placement } from "./rules.ts";

interface Case {
  name: string;
  board: Placement[];
  rack: string[];
  placements: Placement[];
  expect?: { score: number; words: { w: string; s: number }[] };
  error?: string;
}

const fixture = JSON.parse(
  await Deno.readTextFile(new URL("../../../shared/rules-cases.json", import.meta.url)),
) as { dictionary: string[]; cases: Case[] };

const known = new Set(fixture.dictionary);
const dict = { has: (word: string) => known.has(word) };

function buildBoard(tiles: Placement[]): Board {
  const board = emptyBoard();
  for (const t of tiles) board[t.r * 15 + t.c] = { l: t.l, b: t.b };
  return board;
}

for (const testCase of fixture.cases) {
  Deno.test(testCase.name, () => {
    const board = buildBoard(testCase.board);

    if (testCase.error) {
      const err = assertThrows(
        () => playMove(board, testCase.rack, testCase.placements, dict),
        RuleError,
      );
      assertEquals((err as RuleError).message, testCase.error);
      return;
    }

    const result = playMove(board, testCase.rack, testCase.placements, dict);
    assertEquals(result.score, testCase.expect!.score);
    assertEquals(
      result.words.map((w) => `${w.w}:${w.s}`).sort(),
      testCase.expect!.words.map((w) => `${w.w}:${w.s}`).sort(),
    );
  });
}

// Zusätzlich: das Brett darf beim Prüfen nicht verändert werden. Die Vorschau
// im Client ruft playMove bei jedem abgelegten Stein erneut auf – schriebe die
// Funktion in das übergebene Brett, würde sich der Zustand aufschaukeln.
Deno.test("playMove lässt das Eingabebrett unberührt", () => {
  const board = emptyBoard();
  const before = board.slice();
  playMove(
    board,
    ["H", "A", "U", "S"],
    [
      { r: 7, c: 7, l: "H", b: false },
      { r: 7, c: 8, l: "A", b: false },
      { r: 7, c: 9, l: "U", b: false },
      { r: 7, c: 10, l: "S", b: false },
    ],
    dict,
  );
  assertEquals(board, before);
});
