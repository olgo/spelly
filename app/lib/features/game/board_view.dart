import 'package:flutter/material.dart';

import '../../core/messages.dart';
import '../../core/theme.dart';
import '../../domain/rules.dart';
import '../../domain/tiles.dart';
import 'game_controller.dart';

/// Das Brett mit dem Kernstück der Oberfläche: der Zugwert klebt am zuletzt
/// gelegten Stein und aktualisiert sich beim Ablegen, nicht erst beim
/// Abschicken. Ist der Zug noch nicht gültig, steht an derselben Stelle der
/// Grund – dieselbe Position, dieselbe Form, andere Farbe. Man muss den Blick
/// nicht vom Brett nehmen, um zu wissen, woran man ist.
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
                if (controller.preview != null)
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
    return DragTarget<RackTile>(
      onWillAcceptWithDetails: (_) => tile == null && controller.isMyTurn,
      onAcceptWithDetails: (details) {
        controller.place(Placement(
          index ~/ kSize,
          index % kSize,
          details.data.letter,
          blank: details.data.isBlank,
        ));
      },
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;

        if (tile == null) {
          return _EmptySquare(index: index, size: size, hovering: hovering);
        }

        final face = _TileFace(tile: tile!, size: size, isPending: isPending);

        // Nur eigene, noch nicht abgeschickte Steine lassen sich zurücknehmen.
        return isPending
            ? GestureDetector(
                onTap: () => controller.pickUp(index),
                child: face,
              )
            : face;
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
          color: hovering ? Palette.signal.withOpacity(0.28) : premiumColour(code),
          borderRadius: BorderRadius.circular(2),
          border: isCentre
              ? Border.all(color: Palette.signal.withOpacity(0.5), width: 1)
              : null,
        ),
        child: label.isEmpty
            ? null
            : Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: size * 0.26,
                        height: 1,
                        letterSpacing: 0.2,
                        fontWeight: FontWeight.w600,
                        color: Palette.text.withOpacity(0.55),
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
                      ? Palette.boneInk.withOpacity(0.45)
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
                    color: Palette.boneInk.withOpacity(0.6),
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
              color: Palette.boneInk.withOpacity(0.72),
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

/// Ein Stein, der vom Rack aus gezogen wird.
class RackTile {
  const RackTile(this.letter, {this.isBlank = false});
  final String letter;
  final bool isBlank;
}
