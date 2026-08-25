import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/rules.dart';
import '../../domain/tiles.dart';
import 'game_controller.dart';

/// Das Brett, und sonst nichts: 225 Felder, die Steine darauf, und die Gesten,
/// mit denen man sie bewegt.
///
/// Der Zugwert und der Grund, warum ein Zug nicht durchgeht, standen früher
/// als Zettel mitten auf dem Brett. Sie stehen jetzt unter den Knöpfen
/// (`_StatusLine` in `game_page.dart`) – dort verdecken sie keine Steine, und
/// das Brett muss sich nicht mehr merken, an welchem Stein der Zettel klebt.
class BoardView extends StatelessWidget {
  const BoardView({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final cell = (side - Metrics.boardPadding * 2) / kSize;
        final board = controller.displayBoard;
        final pending = controller.pendingIndices;

        return SizedBox(
          width: side,
          height: side,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Palette.boardInk,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Palette.hairline),
            ),
            child: Stack(
              children: [
                for (var i = 0; i < kSize * kSize; i++)
                  Positioned(
                    left: Metrics.boardPadding + (i % kSize) * cell,
                    top: Metrics.boardPadding + (i ~/ kSize) * cell,
                    width: cell,
                    height: cell,
                    child: _Cell(
                      index: i,
                      size: cell,
                      tile: board[i],
                      isPending: pending.contains(i),
                      controller: controller,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.index,
    required this.size,
    required this.tile,
    required this.isPending,
    required this.controller,
  });

  final int index;
  final double size;
  final Tile? tile;
  final bool isPending;
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return DragTarget<DragTile>(
      onWillAcceptWithDetails: (details) {
        if (!controller.isMyTurn) return false;
        // Das Ursprungsfeld zählt als frei: Wer es sich anders überlegt und
        // den Stein zurücklegt, soll nicht ins Leere greifen.
        if (details.data.fromIndex == index) return true;
        return tile == null;
      },
      onAcceptWithDetails: (details) {
        final data = details.data;
        final to = Placement(
          index ~/ kSize,
          index % kSize,
          data.letter,
          blank: data.isBlank,
        );
        final from = data.fromIndex;
        if (from == null) {
          controller.place(to);
        } else {
          controller.move(from, to);
        }
      },
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;

        if (tile == null) {
          return _EmptySquare(index: index, size: size, hovering: hovering);
        }

        final face = _TileFace(tile: tile!, size: size, isPending: isPending);
        if (!isPending) return face;

        // Nur eigene, noch nicht abgeschickte Steine lassen sich bewegen – und
        // zwar auf demselben Weg, auf dem sie gekommen sind. Tippen bleibt die
        // Abkürzung zurück aufs Rack.
        //
        // Unter dem Daumen ist ein Stein von zwanzig Pixeln unsichtbar. Der
        // gezogene Stein wächst deshalb auf Rack-Grösse und schwebt über dem
        // Finger; gezielt wird mit dem hervorgehobenen Feld, nicht mit ihm.
        final lifted = math.max(size * 1.6, 44.0);

        return Draggable<DragTile>(
          data: DragTile(tile!.letter, isBlank: tile!.blank, fromIndex: index),
          dragAnchorStrategy: (_, __, ___) => Offset(lifted / 2, lifted + 8),
          feedback: Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: lifted,
              height: lifted,
              child: _TileFace(tile: tile!, size: lifted, isPending: true),
            ),
          ),
          // Das Loch ist beim Ziehen die nützlichere Auskunft als ein blasser
          // Stein: Man hebt den Stein ja gerade hoch, um zu sehen, welche
          // Prämienfelder noch frei sind.
          childWhenDragging:
              _EmptySquare(index: index, size: size, hovering: hovering),
          child: GestureDetector(
            onTap: () => controller.pickUp(index),
            child: face,
          ),
        );
      },
    );
  }
}

class _EmptySquare extends StatelessWidget {
  const _EmptySquare({
    required this.index,
    required this.size,
    required this.hovering,
  });

  final int index;
  final double size;
  final bool hovering;

  @override
  Widget build(BuildContext context) {
    final code = premium[index];
    final label = premiumLabel(code);
    final isCentre = index == kCenter;

    return Padding(
      padding: const EdgeInsets.all(Metrics.cellGap / 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: hovering ? Palette.signal.withValues(alpha: 0.28) : premiumColour(code),
          borderRadius: BorderRadius.circular(2),
          border: isCentre
              ? Border.all(color: Palette.signal.withValues(alpha: 0.5), width: 1)
              : null,
        ),
        // Das Mittelfeld trägt keinen Bonus (siehe premium in tiles.dart) –
        // die Markierung, dass der erste Zug hier durch muss, kommt deshalb
        // als eigenes Symbol statt als Bonus-Text.
        child: isCentre
            ? Center(
                child: Icon(
                  Icons.star_rounded,
                  size: size * 0.5,
                  color: Palette.signal.withValues(alpha: 0.7),
                ),
              )
            : label.isEmpty
                ? null
                : Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.all(1),
                        child: Text(
                          label,
                          // War auf dem Telefon zu klein, um "2B" von "3W" zu
                          // unterscheiden, ohne die Augen zusammenzukneifen –
                          // Grösse und Deckkraft beide angehoben. Laufweite
                          // bleibt trotzdem offen: Auch grössere Schrift auf
                          // zwanzig Pixeln profitiert noch davon.
                          style: TextStyle(
                            fontSize: size * 0.46,
                            height: 1,
                            letterSpacing: 0.2,
                            fontWeight: FontWeight.w700,
                            color: Palette.text.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _TileFace extends StatelessWidget {
  const _TileFace({
    required this.tile,
    required this.size,
    this.isPending = false,
  });

  final Tile tile;
  final double size;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final value = tile.blank ? 0 : (letterValues[tile.letter] ?? 0);

    return Padding(
      padding: const EdgeInsets.all(Metrics.cellGap / 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Palette.bone,
          borderRadius: BorderRadius.circular(Metrics.tileRadius),
          border: Border(
            bottom: BorderSide(color: Palette.boneShade, width: size * 0.06),
          ),
          boxShadow: isPending
              ? const [BoxShadow(color: Palette.signal, blurRadius: 0, spreadRadius: 1)]
              : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                tile.letter,
                style: TextStyle(
                  fontSize: size * 0.56,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  // Ein eingesetzter Blanko trägt den Buchstaben blasser –
                  // sonst sieht man nach drei Zügen nicht mehr, wo er steckt.
                  color: tile.blank
                      ? Palette.boneInk.withValues(alpha: 0.45)
                      : Palette.boneInk,
                ),
              ),
            ),
            if (value > 0)
              Positioned(
                right: size * 0.08,
                bottom: size * 0.06,
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontSize: size * 0.24,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: Palette.boneInk.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ein Stein unterwegs. [fromIndex] sagt, woher er kommt: null heisst Rack,
/// sonst das Brettfeld, das er beim Ablegen wieder freigibt. Ohne diese Angabe
/// wüsste das Zielfeld nicht, ob es einen Stein aufnimmt oder einen umsetzt.
class DragTile {
  const DragTile(this.letter, {this.isBlank = false, this.fromIndex});
  final String letter;
  final bool isBlank;
  final int? fromIndex;
}
