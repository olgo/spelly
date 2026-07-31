// flutter test test/domain/rules_test.dart
//
// Liest shared/rules-cases.json – dieselbe Datei wie
// supabase/functions/_shared/rules.test.ts. Kommen hier andere Zahlen heraus
// als dort, sind Client und Server auseinandergelaufen, und die Live-Vorschau
// würde etwas anderes versprechen, als der Server am Ende verbucht.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spelly/domain/dawg.dart';
import 'package:spelly/domain/rules.dart';
import 'package:spelly/domain/tiles.dart';

void main() {
  final file = File('../shared/rules-cases.json');
  final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final dict = SetWordSource(
    (fixture['dictionary'] as List).cast<String>().toSet(),
  );

  List<Tile?> buildBoard(List<dynamic> tiles) {
    final board = emptyBoard();
    for (final raw in tiles) {
      final t = raw as Map<String, dynamic>;
      board[(t['r'] as int) * kSize + (t['c'] as int)] =
          Tile(t['l'] as String, blank: t['b'] as bool);
    }
    return board;
  }

  List<Placement> buildPlacements(List<dynamic> raw) => raw
      .map((e) => Placement(
            e['r'] as int,
            e['c'] as int,
            e['l'] as String,
            blank: e['b'] as bool,
          ))
      .toList();

  group('gemeinsame Regelfälle', () {
    for (final raw in fixture['cases'] as List) {
      final testCase = raw as Map<String, dynamic>;

      test(testCase['name'] as String, () {
        final board = buildBoard(testCase['board'] as List);
        final rack = (testCase['rack'] as List).cast<String>();
        final placements = buildPlacements(testCase['placements'] as List);

        if (testCase.containsKey('error')) {
          expect(
            () => playMove(board, rack, placements, dict),
            throwsA(isA<RuleException>()
                .having((e) => e.code, 'code', testCase['error'])),
          );

          // Die Vorschau muss denselben Code melden, nur ohne Exception.
          final preview = previewMove(board, rack, placements, dict);
          expect(preview.isValid, isFalse);
          expect(preview.error, testCase['error']);
          return;
        }

        final expected = testCase['expect'] as Map<String, dynamic>;
        final result = playMove(board, rack, placements, dict);

        expect(result.score, expected['score']);
        expect(
          result.words.map((w) => '${w.word}:${w.score}').toList()..sort(),
          (expected['words'] as List)
              .map((w) => '${w['w']}:${w['s']}')
              .toList()
            ..sort(),
        );

        // Vorschau und autoritative Rechnung müssen übereinstimmen.
        final preview = previewMove(board, rack, placements, dict);
        expect(preview.isValid, isTrue);
        expect(preview.score, result.score);
      });
    }
  });

  test('playMove verändert das Eingabebrett nicht', () {
    // Die Vorschau ruft playMove bei jedem abgelegten Stein erneut auf. Würde
    // die Funktion in das übergebene Brett schreiben, schaukelte sich der
    // Zustand mit jedem Zug auf.
    final board = emptyBoard();
    final before = List<Tile?>.of(board);

    playMove(
      board,
      ['H', 'A', 'U', 'S'],
      const [
        Placement(7, 7, 'H'),
        Placement(7, 8, 'A'),
        Placement(7, 9, 'U'),
        Placement(7, 10, 'S'),
      ],
      dict,
    );

    expect(board, before);
  });

  test('DAWG-Leser versteht das Format des Builders', () {
    // Gegenprobe zum Binärformat: eine von Hand gebaute Minimaldatei mit dem
    // Wort AB. Fällt hier etwas um, stimmt die Bitbelegung zwischen
    // dict/scripts/build_dawg.py und dawg.dart nicht mehr überein.
    final bytes = BytesBuilder();
    bytes.add(utf8.encode('DAWG'));
    final header = ByteData(12)
      ..setUint32(0, 1, Endian.little) // Version
      ..setUint32(4, 1, Endian.little) // Wurzelblock
      ..setUint32(8, 3, Endian.little); // Anzahl Knoten
    bytes.add(header.buffer.asUint8List());

    final nodes = ByteData(12)
      ..setUint32(0, 0, Endian.little) // Index 0 bleibt frei
      // Index 1: Buchstabe A (0), kein Wortende, letzter Eintrag, Kind bei 2
      ..setUint32(4, 0 | 0x200 | (2 << 10), Endian.little)
      // Index 2: Buchstabe B (1), Wortende, letzter Eintrag, kein Kind
      ..setUint32(8, 1 | 0x100 | 0x200, Endian.little);
    bytes.add(nodes.buffer.asUint8List());

    final dawg = Dawg.fromBytes(
      ByteData.sublistView(bytes.toBytes()),
      'test',
    );

    expect(dawg.has('AB'), isTrue);
    expect(dawg.has('A'), isFalse);
    expect(dawg.has('ABC'), isFalse);
    expect(dawg.has('B'), isFalse);
  });
}
