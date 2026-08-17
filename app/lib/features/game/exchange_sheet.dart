import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'rack_view.dart';

/// Fragt, welche Steine zurück in den Beutel sollen. Liefert die gewählten
/// Buchstaben, oder `null` beim Abbrechen.
///
/// Als eigenes Blatt und nicht als Auswahlmodus auf dem Rack: Dort hängen
/// Ziehen, Antippen und die Blanko-Wahl schon aneinander, ein vierter Zustand
/// darüber wäre kaum noch zu durchschauen. Hier ist Tippen eindeutig.
Future<List<String>?> showExchangeSheet(
  BuildContext context,
  List<String> rack, {
  bool hasPending = false,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    backgroundColor: Palette.graphite,
    builder: (context) => _ExchangeSheet(rack: rack, hasPending: hasPending),
  );
}

class _ExchangeSheet extends StatefulWidget {
  const _ExchangeSheet({required this.rack, required this.hasPending});
  final List<String> rack;

  /// Ob gerade Steine auf dem Brett liegen. Gezeigt werden hier alle sieben,
  /// auch die abgelegten – wer tauscht, bekommt sie ohnehin zurück, und das
  /// gehört gesagt, bevor jemand tippt.
  final bool hasPending;

  @override
  State<_ExchangeSheet> createState() => _ExchangeSheetState();
}

class _ExchangeSheetState extends State<_ExchangeSheet> {
  /// Gewählt wird über die Position, nicht über den Buchstaben: Wer zwei E hat,
  /// soll eines abgeben können und nicht beide auf einmal.
  final Set<int> _chosen = {};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Steine tauschen',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Die gewählten Steine gehen zurück in den Beutel, du ziehst '
              'genauso viele nach. Punkte gibt es dafür keine, und der Zug '
              'ist danach beim Gegner.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (widget.hasPending) ...[
              const SizedBox(height: 6),
              Text(
                'Was du schon aufs Brett gelegt hast, kommt dabei zurück.',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: Palette.warn),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < widget.rack.length; i++)
                  _SelectableTile(
                    letter: widget.rack[i],
                    selected: _chosen.contains(i),
                    onTap: () => setState(() {
                      if (!_chosen.remove(i)) _chosen.add(i);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.signal,
                    foregroundColor: Palette.boneInk,
                    disabledBackgroundColor: Palette.hairline,
                    disabledForegroundColor: Palette.textDim,
                  ),
                  onPressed: _chosen.isEmpty
                      ? null
                      : () => Navigator.pop(
                            context,
                            [for (final i in _chosen) widget.rack[i]],
                          ),
                  child: Text(
                    _chosen.isEmpty
                        ? 'Steine wählen'
                        : 'Tauschen (${_chosen.length})',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Gewählte Steine rücken hoch und bekommen einen Ring – dieselbe Sprache, mit
/// der schon auf dem Brett gezeigt wird, was noch nicht abgeschickt ist.
class _SelectableTile extends StatelessWidget {
  const _SelectableTile({
    required this.letter,
    required this.selected,
    required this.onTap,
  });

  final String letter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        transform: Matrix4.translationValues(0, selected ? -6 : 0, 0),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Metrics.tileRadius + 3),
          border: Border.all(
            color: selected ? Palette.signal : Colors.transparent,
            width: 2,
          ),
        ),
        child: RackTileFace(letter: letter, blank: letter == '?'),
      ),
    );
  }
}
