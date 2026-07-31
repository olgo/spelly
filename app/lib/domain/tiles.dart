/// Spiegelt supabase/functions/_shared/tiles.ts.
/// Änderungen hier gehören in dieselbe Commit-Einheit wie dort.
library;

const int kSize = 15;
const int kCenter = 7 * kSize + 7;
const int kRackSize = 7;
const int kBingoBonus = 50;

const Map<String, int> letterValues = {
  'E': 1, 'N': 1, 'S': 1, 'I': 1, 'R': 1, 'T': 1, 'U': 1, 'A': 1, 'D': 1,
  'H': 2, 'G': 2, 'L': 2, 'O': 2,
  'M': 3, 'B': 3, 'W': 3, 'Z': 3,
  'C': 4, 'F': 4, 'K': 4, 'P': 4,
  'Ä': 6, 'J': 6, 'Ü': 6, 'V': 6,
  'Ö': 8, 'X': 8,
  'Q': 10, 'Y': 10,
};

const Map<String, int> distribution = {
  'E': 15, 'N': 9, 'S': 7, 'I': 6, 'R': 6, 'T': 6, 'U': 6, 'A': 5, 'D': 4,
  'H': 4, 'G': 3, 'L': 3, 'O': 3,
  'M': 4, 'B': 2, 'W': 1, 'Z': 1,
  'C': 2, 'F': 2, 'K': 2, 'P': 1,
  'Ä': 1, 'J': 1, 'Ü': 1, 'V': 1,
  'Ö': 1, 'X': 1,
  'Q': 1, 'Y': 1,
  '?': 2,
};

/// T/D = Wort dreifach/doppelt, t/d = Buchstabe dreifach/doppelt.
const String premium =
    'T..d...T...d..T'
    '.D...t...t...D.'
    '..D...d.d...D..'
    'd..D...d...D..d'
    '....D.....D....'
    '.t...t...t...t.'
    '..d...d.d...d..'
    'T..d...D...d..T'
    '..d...d.d...d..'
    '.t...t...t...t.'
    '....D.....D....'
    'd..D...d...D..d'
    '..D...d.d...D..'
    '.D...t...t...D.'
    'T..d...T...d..T';

int rackValue(List<String> tiles) =>
    tiles.fold(0, (sum, t) => sum + (t == '?' ? 0 : letterValues[t] ?? 0));
