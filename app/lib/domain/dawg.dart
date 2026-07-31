/// Liest dasselbe Binärformat wie supabase/functions/_shared/dawg.ts.
/// Der Aufbau ist dort ausführlich dokumentiert.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'rules.dart' show WordSource;

const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ';
const int _charMask = 0xFF;
const int _terminalBit = 1 << 8;
const int _lastBit = 1 << 9;
const int _childShift = 10;

class Dawg implements WordSource {
  Dawg._(this._nodes, this._root, this.version);

  final Uint32List _nodes;
  final int _root;
  final String version;

  static final Map<String, int> _letterIndex = {
    for (var i = 0; i < _alphabet.length; i++) _alphabet[i]: i,
  };

  /// Lädt die Wortliste aus dem App-Bundle. Rund fünf Megabyte, also einmal
  /// beim Öffnen einer Partie und danach halten – nicht pro Zug.
  static Future<Dawg> load(String version) async {
    final data = await rootBundle.load('assets/dict/$version.dawg');
    return Dawg.fromBytes(data, version);
  }

  factory Dawg.fromBytes(ByteData data, String version) {
    final magic = String.fromCharCodes([
      data.getUint8(0),
      data.getUint8(1),
      data.getUint8(2),
      data.getUint8(3),
    ]);
    if (magic != 'DAWG') {
      throw StateError('Wortliste beschädigt: Kopfkennung fehlt');
    }

    final root = data.getUint32(8, Endian.little);
    final count = data.getUint32(12, Endian.little);
    final nodes = data.buffer.asUint32List(data.offsetInBytes + 16, count);
    return Dawg._(nodes, root, version);
  }

  @override
  bool has(String word) {
    if (word.isEmpty) return false;
    var node = _root;
    if (node == 0) return false;

    for (var i = 0; i < word.length; i++) {
      final target = _letterIndex[word[i]];
      if (target == null) return false;

      int? found;
      var n = node;
      while (true) {
        final cell = _nodes[n];
        if ((cell & _charMask) == target) {
          found = cell;
          break;
        }
        if (cell & _lastBit != 0) break;
        n++;
      }
      if (found == null) return false;

      if (i == word.length - 1) return (found & _terminalBit) != 0;

      node = found >> _childShift;
      if (node == 0) return false;
    }
    return false;
  }
}

/// Ersatz für Tests und für den Fall, dass die Wortliste noch lädt: erlaubt
/// nichts. Besser eine Vorschau, die "prüfe noch" sagt, als eine, die lügt.
class EmptyWordSource implements WordSource {
  const EmptyWordSource();

  @override
  bool has(String word) => false;
}

/// Für Tests: ein einfaches Set.
class SetWordSource implements WordSource {
  const SetWordSource(this._words);
  final Set<String> _words;

  @override
  bool has(String word) => _words.contains(word);
}
