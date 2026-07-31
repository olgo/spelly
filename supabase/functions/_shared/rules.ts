// Reine Spiellogik – keine Datenbank, keine Netzwerkaufrufe.
// Dadurch komplett unit-testbar und später auch im Client wiederverwendbar
// (etwa für eine sofortige Vorschau des Zugwerts, bevor der Server antwortet).

import { BINGO_BONUS, CENTER, LETTER_VALUES, PREMIUM, SIZE } from "./tiles.ts";

/** Alles, was ein Wort bestätigen kann. Dawg erfüllt das; Tests reichen ein Set. */
export interface WordSource {
  has(word: string): boolean;
}

export type Tile = { l: string; b: boolean };
export type Board = (Tile | null)[];
export type Placement = { r: number; c: number; l: string; b: boolean };
export type ScoredWord = { w: string; s: number };

export class RuleError extends Error {
  readonly detail?: unknown;
  constructor(code: string, detail?: unknown) {
    super(code);
    this.detail = detail;
  }
}

const idx = (r: number, c: number) => r * SIZE + c;
const inBounds = (r: number, c: number) => r >= 0 && r < SIZE && c >= 0 && c < SIZE;

export function emptyBoard(): Board {
  return new Array(SIZE * SIZE).fill(null);
}

/** Sammelt ein durchgehendes Wort ab (r,c) in Richtung (dr,dc) inkl. Rückwärtslauf. */
function collectWord(board: Board, r: number, c: number, dr: number, dc: number) {
  let sr = r, sc = c;
  while (inBounds(sr - dr, sc - dc) && board[idx(sr - dr, sc - dc)]) {
    sr -= dr; sc -= dc;
  }
  const cells: number[] = [];
  let cr = sr, cc = sc;
  while (inBounds(cr, cc) && board[idx(cr, cc)]) {
    cells.push(idx(cr, cc));
    cr += dr; cc += dc;
  }
  return cells;
}

function wordText(board: Board, cells: number[]): string {
  return cells.map((i) => board[i]!.l).join("");
}

function scoreWord(board: Board, cells: number[], fresh: Set<number>): number {
  let sum = 0;
  let wordMult = 1;

  for (const i of cells) {
    const tile = board[i]!;
    let value = tile.b ? 0 : (LETTER_VALUES[tile.l] ?? 0);

    // Prämienfelder zählen nur für in diesem Zug neu gelegte Steine.
    if (fresh.has(i)) {
      switch (PREMIUM[i]) {
        case "d": value *= 2; break;
        case "t": value *= 3; break;
        case "D": wordMult *= 2; break;
        case "T": wordMult *= 3; break;
      }
    }
    sum += value;
  }
  return sum * wordMult;
}

export interface MoveResult {
  board: Board;
  words: ScoredWord[];
  score: number;
  used: string[]; // die tatsächlich vom Rack verbrauchten Steine ("?" für Blanko)
}

/**
 * Prüft einen Legezug vollständig und berechnet die Punkte.
 * Wirft RuleError bei jedem Regelverstoß – der Aufrufer gibt den Code 1:1
 * an den Client weiter, damit die App eine passende Meldung anzeigen kann.
 */
export function playMove(
  board: Board,
  rack: string[],
  placements: Placement[],
  dict: WordSource,
): MoveResult {
  if (placements.length === 0) throw new RuleError("no_placements");
  if (placements.length > 7) throw new RuleError("too_many_tiles");

  // --- 1. Geometrie der einzelnen Felder ---
  const seen = new Set<number>();
  for (const p of placements) {
    if (!inBounds(p.r, p.c)) throw new RuleError("out_of_bounds");
    const i = idx(p.r, p.c);
    if (seen.has(i)) throw new RuleError("duplicate_square");
    if (board[i]) throw new RuleError("square_occupied");
    if (!(p.l in LETTER_VALUES)) throw new RuleError("unknown_letter");
    seen.add(i);
  }

  // --- 2. Deckt der Spieler die Steine wirklich ab? ---
  const pool = new Map<string, number>();
  for (const t of rack) pool.set(t, (pool.get(t) ?? 0) + 1);
  const used: string[] = [];
  for (const p of placements) {
    const need = p.b ? "?" : p.l;
    const have = pool.get(need) ?? 0;
    if (have === 0) throw new RuleError("tile_not_in_rack", need);
    pool.set(need, have - 1);
    used.push(need);
  }

  // --- 3. Eine Reihe oder eine Spalte? ---
  const rows = new Set(placements.map((p) => p.r));
  const cols = new Set(placements.map((p) => p.c));
  const horizontal = rows.size === 1;
  const vertical = cols.size === 1;
  if (!horizontal && !vertical) throw new RuleError("not_in_line");

  // --- 4. Provisorisches Brett ---
  const next: Board = board.slice();
  for (const p of placements) next[idx(p.r, p.c)] = { l: p.l, b: p.b };

  // --- 5. Lückenlosigkeit (bestehende Steine dürfen Lücken füllen) ---
  if (placements.length > 1) {
    const axis = horizontal ? placements.map((p) => p.c) : placements.map((p) => p.r);
    const fixed = horizontal ? placements[0].r : placements[0].c;
    for (let k = Math.min(...axis); k <= Math.max(...axis); k++) {
      const i = horizontal ? idx(fixed, k) : idx(k, fixed);
      if (!next[i]) throw new RuleError("gap_in_word");
    }
  }

  // --- 6. Anbindung ans bestehende Spiel ---
  const isFirstMove = board.every((cell) => cell === null);
  if (isFirstMove) {
    if (!seen.has(CENTER)) throw new RuleError("first_move_must_cover_center");
    if (placements.length < 2) throw new RuleError("first_move_too_short");
  } else {
    const touches = placements.some((p) =>
      [[-1, 0], [1, 0], [0, -1], [0, 1]].some(([dr, dc]) => {
        const nr = p.r + dr, nc = p.c + dc;
        return inBounds(nr, nc) && board[idx(nr, nc)] !== null;
      })
    );
    if (!touches) throw new RuleError("not_connected");
  }

  // --- 7. Gebildete Wörter einsammeln ---
  const first = placements[0];
  const collected: number[][] = [];

  const pushed = new Set<string>();
  const push = (cells: number[]) => {
    if (cells.length < 2) return;
    const key = `${cells[0]}:${cells.length}`;
    if (pushed.has(key)) return;
    pushed.add(key);
    collected.push(cells);
  };

  if (placements.length === 1) {
    // Richtung ist nicht bestimmt – beide prüfen, mindestens eine muss greifen.
    push(collectWord(next, first.r, first.c, 0, 1));
    push(collectWord(next, first.r, first.c, 1, 0));
  } else {
    // Hauptwort entlang der Legerichtung …
    const [mdr, mdc] = horizontal ? [0, 1] : [1, 0];
    push(collectWord(next, first.r, first.c, mdr, mdc));
    // … plus je ein Kreuzwort senkrecht dazu an jedem neuen Stein.
    const [cdr, cdc] = horizontal ? [1, 0] : [0, 1];
    for (const p of placements) push(collectWord(next, p.r, p.c, cdr, cdc));
  }

  if (collected.length === 0) throw new RuleError("no_word_formed");

  // --- 8. Wörterbuch ---
  const words: ScoredWord[] = [];
  let total = 0;
  for (const cells of collected) {
    const text = wordText(next, cells);
    if (!dict.has(text)) throw new RuleError("invalid_word", text);
    const s = scoreWord(next, cells, seen);
    words.push({ w: text, s });
    total += s;
  }

  if (placements.length === 7) total += BINGO_BONUS;

  return { board: next, words, score: total, used };
}
