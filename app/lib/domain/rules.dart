/// Spiegelt supabase/functions/_shared/rules.ts.
///
/// Zwei Implementierungen derselben Regeln sind eine Fehlerquelle. Beide
/// Seiten laufen deshalb gegen dieselbe Falldatei, shared/rules-cases.json –
/// siehe app/test/domain/rules_test.dart.
library;

import 'tiles.dart';

class Tile {
  const Tile(this.letter, {this.blank = false});
  final String letter;
  final bool blank;

  @override
  bool operator ==(Object other) =>
      other is Tile && other.letter == letter && other.blank == blank;

  @override
  int get hashCode => Object.hash(letter, blank);
}

class Placement {
  const Placement(this.row, this.col, this.letter, {this.blank = false});
  final int row;
  final int col;
  final String letter;
  final bool blank;

  int get index => row * kSize + col;

  Map<String, dynamic> toJson() =>
      {'r': row, 'c': col, 'l': letter, 'b': blank};
}

class ScoredWord {
  const ScoredWord(this.word, this.score);
  final String word;
  final int score;
}

class RuleException implements Exception {
  const RuleException(this.code, [this.detail]);
  final String code;
  final Object? detail;

  @override
  String toString() => 'RuleException($code${detail == null ? '' : ': $detail'})';
}

class MoveResult {
  const MoveResult(this.board, this.words, this.score, this.used);
  final List<Tile?> board;
  final List<ScoredWord> words;
  final int score;
  final List<String> used;
}

/// Was die Vorschau anzeigt: entweder ein Ergebnis oder ein Grund, warum der
/// Zug so noch nicht geht. Ohne Exception, weil das beim Ziehen jedes Steins
/// aufgerufen wird und ein halb gelegtes Wort der Normalfall ist.
class MovePreview {
  const MovePreview.valid(this.score, this.words)
      : error = null,
        detail = null;
  const MovePreview.invalid(this.error, [this.detail])
      : score = null,
        words = const [];

  final int? score;
  final List<ScoredWord> words;
  final String? error;
  final Object? detail;

  bool get isValid => error == null;
}

abstract class WordSource {
  bool has(String word);
}

List<Tile?> emptyBoard() => List<Tile?>.filled(kSize * kSize, null);

bool _inBounds(int r, int c) => r >= 0 && r < kSize && c >= 0 && c < kSize;
int _idx(int r, int c) => r * kSize + c;

List<int> _collectWord(List<Tile?> board, int r, int c, int dr, int dc) {
  var sr = r, sc = c;
  while (_inBounds(sr - dr, sc - dc) && board[_idx(sr - dr, sc - dc)] != null) {
    sr -= dr;
    sc -= dc;
  }
  final cells = <int>[];
  var cr = sr, cc = sc;
  while (_inBounds(cr, cc) && board[_idx(cr, cc)] != null) {
    cells.add(_idx(cr, cc));
    cr += dr;
    cc += dc;
  }
  return cells;
}

int _scoreWord(List<Tile?> board, List<int> cells, Set<int> fresh) {
  var sum = 0;
  var wordMultiplier = 1;

  for (final i in cells) {
    final tile = board[i]!;
    var value = tile.blank ? 0 : (letterValues[tile.letter] ?? 0);

    if (fresh.contains(i)) {
      switch (premium[i]) {
        case 'd':
          value *= 2;
        case 't':
          value *= 3;
        case 'D':
          wordMultiplier *= 2;
        case 'T':
          wordMultiplier *= 3;
      }
    }
    sum += value;
  }
  return sum * wordMultiplier;
}

MoveResult playMove(
  List<Tile?> board,
  List<String> rack,
  List<Placement> placements,
  WordSource dict,
) {
  if (placements.isEmpty) throw const RuleException('no_placements');
  if (placements.length > 7) throw const RuleException('too_many_tiles');

  // 1. Felder einzeln prüfen.
  final seen = <int>{};
  for (final p in placements) {
    if (!_inBounds(p.row, p.col)) throw const RuleException('out_of_bounds');
    if (seen.contains(p.index)) throw const RuleException('duplicate_square');
    if (board[p.index] != null) throw const RuleException('square_occupied');
    if (!letterValues.containsKey(p.letter)) {
      throw const RuleException('unknown_letter');
    }
    seen.add(p.index);
  }

  // 2. Deckt das Rack die Steine?
  final pool = <String, int>{};
  for (final t in rack) {
    pool[t] = (pool[t] ?? 0) + 1;
  }
  final used = <String>[];
  for (final p in placements) {
    final need = p.blank ? '?' : p.letter;
    final have = pool[need] ?? 0;
    if (have == 0) throw RuleException('tile_not_in_rack', need);
    pool[need] = have - 1;
    used.add(need);
  }

  // 3. Eine Zeile oder eine Spalte?
  final horizontal = placements.map((p) => p.row).toSet().length == 1;
  final vertical = placements.map((p) => p.col).toSet().length == 1;
  if (!horizontal && !vertical) throw const RuleException('not_in_line');

  // 4. Provisorisches Brett.
  final next = List<Tile?>.of(board);
  for (final p in placements) {
    next[p.index] = Tile(p.letter, blank: p.blank);
  }

  // 5. Lückenlos?
  if (placements.length > 1) {
    final axis = horizontal
        ? placements.map((p) => p.col).toList()
        : placements.map((p) => p.row).toList();
    final fixed = horizontal ? placements.first.row : placements.first.col;
    final lo = axis.reduce((a, b) => a < b ? a : b);
    final hi = axis.reduce((a, b) => a > b ? a : b);
    for (var k = lo; k <= hi; k++) {
      final i = horizontal ? _idx(fixed, k) : _idx(k, fixed);
      if (next[i] == null) throw const RuleException('gap_in_word');
    }
  }

  // 6. Anbindung.
  final isFirstMove = board.every((cell) => cell == null);
  if (isFirstMove) {
    if (!seen.contains(kCenter)) {
      throw const RuleException('first_move_must_cover_center');
    }
    if (placements.length < 2) {
      throw const RuleException('first_move_too_short');
    }
  } else {
    final touches = placements.any((p) {
      for (final d in const [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
        final nr = p.row + d[0], nc = p.col + d[1];
        if (_inBounds(nr, nc) && board[_idx(nr, nc)] != null) return true;
      }
      return false;
    });
    if (!touches) throw const RuleException('not_connected');
  }

  // 7. Wörter einsammeln.
  final collected = <List<int>>[];
  final pushed = <String>{};
  void push(List<int> cells) {
    if (cells.length < 2) return;
    final key = '${cells.first}:${cells.length}';
    if (!pushed.add(key)) return;
    collected.add(cells);
  }

  final first = placements.first;
  if (placements.length == 1) {
    push(_collectWord(next, first.row, first.col, 0, 1));
    push(_collectWord(next, first.row, first.col, 1, 0));
  } else {
    final mdr = horizontal ? 0 : 1, mdc = horizontal ? 1 : 0;
    push(_collectWord(next, first.row, first.col, mdr, mdc));
    final cdr = horizontal ? 1 : 0, cdc = horizontal ? 0 : 1;
    for (final p in placements) {
      push(_collectWord(next, p.row, p.col, cdr, cdc));
    }
  }

  if (collected.isEmpty) throw const RuleException('no_word_formed');

  // 8. Wörterbuch und Punkte.
  final words = <ScoredWord>[];
  var total = 0;
  for (final cells in collected) {
    final text = cells.map((i) => next[i]!.letter).join();
    if (!dict.has(text)) throw RuleException('invalid_word', text);
    final s = _scoreWord(next, cells, seen);
    words.add(ScoredWord(text, s));
    total += s;
  }

  if (placements.length == 7) total += kBingoBonus;

  return MoveResult(next, words, total, used);
}

/// Für die Live-Vorschau: dieselbe Prüfung, aber ohne Exception.
MovePreview previewMove(
  List<Tile?> board,
  List<String> rack,
  List<Placement> placements,
  WordSource dict,
) {
  if (placements.isEmpty) return const MovePreview.invalid('no_placements');
  try {
    final result = playMove(board, rack, placements, dict);
    return MovePreview.valid(result.score, result.words);
  } on RuleException catch (e) {
    return MovePreview.invalid(e.code, e.detail);
  }
}
