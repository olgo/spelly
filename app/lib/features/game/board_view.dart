import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/messages.dart';
import '../../core/theme.dart';
import '../../domain/rules.dart';
import '../../domain/tiles.dart';
import 'game_controller.dart';

/// Das Brett mit dem Kernstück der Oberfläche: der Zugwert klebt am zuletzt
/// gelegten Stein und aktualisiert sich beim Ablegen, nicht erst beim
/// Abschicken. Man muss den Blick nicht vom Brett nehmen, um zu wissen, woran
/// man ist.
///
/// An derselben Stelle steht in Warnfarbe der Grund, wenn der Zug nicht
/// durchgeht – aber nur für die Gründe, die man den Steinen nicht ansieht
/// (siehe `showsWhilePlacing`). Dass vier Steine über Kreuz keine Reihe
/// ergeben, ist beim Legen der Normalzustand und keine Meldung wert.
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

        // Beim Legen sind die meisten Regelverstösse Zwischenstände. Der
        // Zettel erscheint nur für das, was man den Steinen nicht ansieht.
        final preview = controller.preview;
        final showPreview = preview != null &&
            (preview.isValid || showsWhilePlacing(preview.error!));

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
                if (showPreview)
                  _PreviewChip(controller: controller, cell: cell),
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
        child: label.isEmpty
            ? null
            : Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(1),
                    child: Text(
                      label,
                      // Auf dem Telefon ist ein Feld gut zwanzig Pixel breit.
                      // Die Deckkraft trägt hier mehr als die Grösse: Sie
                      // kauft Lesbarkeit, ohne dem Feld Gewicht zu geben, das
                      // den Steinen zusteht. Laufweite bleibt bewusst offen –
                      // kleine Schrift braucht mehr davon, nicht weniger.
                      style: TextStyle(
                        fontSize: size * 0.40,
                        height: 1,
                        letterSpacing: 0.2,
                        fontWeight: FontWeight.w700,
                        color: Palette.text.withValues(alpha: 0.85),
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

/// Die Vorschau selbst. Sie sitzt über dem zuletzt gelegten Stein und rückt
/// mit, statt in einer Statusleiste am Rand zu stehen.
class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.controller, required this.cell});

  final GameController controller;
  final double cell;

  @override
  Widget build(BuildContext context) {
    final preview = controller.preview!;
    final anchor = controller.pending.last;
    final valid = preview.isValid;

    // Über dem Stein, ausser er liegt in der obersten Zeile – dann darunter.
    final above = anchor.row > 0;
    final top = Metrics.boardPadding +
        (above ? (anchor.row - 1) * cell : (anchor.row + 1) * cell);
    final left = (anchor.col * cell + Metrics.boardPadding - cell * 1.5)
        .clamp(4.0, double.infinity);

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          child: Container(
            key: ValueKey('${preview.score}-${preview.error}'),
            constraints: BoxConstraints(maxWidth: cell * 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: valid ? Palette.signal : Palette.warn,
              borderRadius: BorderRadius.circular(4),
            ),
            child: valid
                ? _ValidPreview(preview: preview)
                : Text(
                    moveMessage(preview.error!, preview.detail),
                    style: const TextStyle(
                      color: Palette.bone,
                      fontSize: 11.5,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ValidPreview extends StatelessWidget {
  const _ValidPreview({required this.preview});
  final MovePreview preview;

  @override
  Widget build(BuildContext context) {
    // Bei mehreren Wörtern zählt die Summe; die Einzelwerte stehen klein
    // darunter, damit nachvollziehbar bleibt, woher die Punkte kommen.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '+${preview.score}',
          style: const TextStyle(
            color: Palette.boneInk,
            fontSize: 15,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        if (preview.words.length > 1) ...[
          const SizedBox(height: 2),
          Text(
            preview.words.map((w) => '${w.word} ${w.score}').join(' · '),
            style: TextStyle(
              color: Palette.boneInk.withValues(alpha: 0.72),
              fontSize: 10,
              height: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
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
