import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/tiles.dart';
import 'board_view.dart';
import 'game_controller.dart';

class RackView extends StatelessWidget {
  const RackView({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final tiles = controller.availableRack;

    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Palette.boardInk,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Palette.hairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < tiles.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _DraggableTile(
                letter: tiles[i],
                enabled: controller.isMyTurn,
                onBlankChosen: (letter) => _showBlankPicker(context, letter),
              ),
            ),
          if (tiles.isEmpty)
            Text('Rack leer', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }

  Future<String?> _showBlankPicker(BuildContext context, String _) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Palette.graphite,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Blanko festlegen',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Der Buchstabe bleibt für den Rest der Partie stehen.',
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final letter in letterValues.keys)
                    GestureDetector(
                      onTap: () => Navigator.pop(context, letter),
                      child: Container(
                        width: 40,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Palette.bone,
                          borderRadius:
                              BorderRadius.circular(Metrics.tileRadius),
                        ),
                        child: Text(
                          letter,
                          style: const TextStyle(
                            color: Palette.boneInk,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraggableTile extends StatefulWidget {
  const _DraggableTile({
    required this.letter,
    required this.enabled,
    required this.onBlankChosen,
  });

  final String letter;
  final bool enabled;
  final Future<String?> Function(String) onBlankChosen;

  @override
  State<_DraggableTile> createState() => _DraggableTileState();
}

class _DraggableTileState extends State<_DraggableTile> {
  /// Beim Blanko muss vor dem Ziehen feststehen, welcher Buchstabe gemeint
  /// ist – sonst wüsste die Vorschau nicht, welches Wort sie prüfen soll.
  String? _chosen;

  @override
  Widget build(BuildContext context) {
    final isBlank = widget.letter == '?';
    final shown = isBlank ? (_chosen ?? '?') : widget.letter;
    final face = _Face(letter: shown, blank: isBlank);

    if (!widget.enabled) return Opacity(opacity: 0.45, child: face);

    if (isBlank && _chosen == null) {
      return GestureDetector(
        onTap: () async {
          final chosen = await widget.onBlankChosen(widget.letter);
          if (chosen != null && mounted) setState(() => _chosen = chosen);
        },
        child: face,
      );
    }

    return Draggable<RackTile>(
      data: RackTile(shown, isBlank: isBlank),
      feedback: _Face(letter: shown, blank: isBlank, elevated: true),
      childWhenDragging: Opacity(opacity: 0.25, child: face),
      // Nochmal antippen erlaubt, den Blanko-Buchstaben zu ändern, solange
      // der Stein noch auf dem Rack liegt.
      onDragCompleted: () {
        if (isBlank && mounted) setState(() => _chosen = null);
      },
      child: isBlank
          ? GestureDetector(
              onTap: () async {
                final chosen = await widget.onBlankChosen(widget.letter);
                if (chosen != null && mounted) setState(() => _chosen = chosen);
              },
              child: face,
            )
          : face,
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({
    required this.letter,
    this.blank = false,
    this.elevated = false,
  });

  final String letter;
  final bool blank;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final value = blank ? 0 : (letterValues[letter] ?? 0);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 42,
        height: 48,
        decoration: BoxDecoration(
          color: Palette.bone,
          borderRadius: BorderRadius.circular(Metrics.tileRadius + 1),
          border: const Border(
            bottom: BorderSide(color: Palette.boneShade, width: 3),
          ),
          boxShadow: elevated
              ? const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                letter,
                style: TextStyle(
                  color: blank
                      ? Palette.boneInk.withValues(alpha: 0.4)
                      : Palette.boneInk,
                  fontSize: 22,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (value > 0)
              Positioned(
                right: 4,
                bottom: 3,
                child: Text(
                  '$value',
                  style: TextStyle(
                    color: Palette.boneInk.withValues(alpha: 0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
