// Steinwerte, Verteilung und Brettlayout.

export const SIZE = 15;
export const CENTER = 7 * SIZE + 7;
export const RACK_SIZE = 7;
export const BINGO_BONUS = 50;

export const LETTER_VALUES: Record<string, number> = {
  E: 1, N: 1, S: 1, I: 1, R: 1, T: 1, U: 1, A: 1, D: 1,
  H: 2, G: 2, L: 2, O: 2,
  M: 3, B: 3, W: 3, Z: 3,
  C: 4, F: 4, K: 4, P: 4,
  "Ä": 6, J: 6, "Ü": 6, V: 6,
  "Ö": 8, X: 8,
  Q: 10, Y: 10,
};

// 102 Steine. "?" ist der Blanko.
export const DISTRIBUTION: Record<string, number> = {
  E: 15, N: 9, S: 7, I: 6, R: 6, T: 6, U: 6, A: 5, D: 4,
  H: 4, G: 3, L: 3, O: 3,
  M: 4, B: 2, W: 1, Z: 1,
  C: 2, F: 2, K: 2, P: 1,
  "Ä": 1, J: 1, "Ü": 1, V: 1,
  "Ö": 1, X: 1,
  Q: 1, Y: 1,
  "?": 2,
};

export function newBag(): string[] {
  const bag: string[] = [];
  for (const [letter, count] of Object.entries(DISTRIBUTION)) {
    for (let i = 0; i < count; i++) bag.push(letter);
  }
  return bag;
}

// Prämienfelder.  T/D = Wort dreifach/doppelt, t/d = Buchstabe dreifach/doppelt.
// Diese Anordnung ist die klassische, punktsymmetrische Variante. Falls du dich
// vom Original absetzen willst, ist das hier die einzige Stelle, die du ändern
// musst – der Rest der Engine liest das Layout nur aus.
const PREMIUM_ROWS = [
  "T..d...T...d..T",
  ".D...t...t...D.",
  "..D...d.d...D..",
  "d..D...d...D..d",
  "....D.....D....",
  ".t...t...t...t.",
  "..d...d.d...d..",
  "T..d...D...d..T",
  "..d...d.d...d..",
  ".t...t...t...t.",
  "....D.....D....",
  "d..D...d...D..d",
  "..D...d.d...D..",
  ".D...t...t...D.",
  "T..d...T...d..T",
];

export const PREMIUM: string = PREMIUM_ROWS.join("");

/** Fisher-Yates mit deterministischem Seed – macht Partien reproduzierbar. */
export function shuffle<T>(items: T[], seed: number): T[] {
  const out = items.slice();
  let s = seed >>> 0;
  const next = () => {
    // xorshift32
    s ^= s << 13; s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5; s >>>= 0;
    return s / 0x100000000;
  };
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(next() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

/** Restwert eines Racks – für die Schlussabrechnung. */
export function rackValue(tiles: string[]): number {
  return tiles.reduce((sum, t) => sum + (t === "?" ? 0 : LETTER_VALUES[t] ?? 0), 0);
}
