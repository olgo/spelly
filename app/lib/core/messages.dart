/// Der Server schickt Codes, keine Sätze – damit sich Texte ohne Deploy ändern
/// lassen. Formuliert ist aus der Sicht der Person am Brett: was ist los und
/// was hilft weiter. Keine Entschuldigungen, keine Schuldzuweisung.
library;

String moveMessage(String code, [Object? detail]) => switch (code) {
      'no_placements' => 'Leg einen Stein aufs Brett.',
      'dict_loading' => 'Wortliste lädt noch.',
      'first_move_must_cover_center' =>
        'Der erste Zug muss über das Mittelfeld gehen.',
      'first_move_too_short' => 'Der erste Zug braucht mindestens zwei Steine.',
      'not_in_line' => 'Alle Steine müssen in eine Zeile oder eine Spalte.',
      'gap_in_word' => 'Zwischen den Steinen bleibt eine Lücke.',
      'not_connected' => 'Das Wort muss an einen liegenden Stein anschliessen.',
      'square_occupied' => 'Auf dem Feld liegt schon ein Stein.',
      'no_word_formed' => 'Daraus entsteht noch kein Wort.',
      'invalid_word' => detail == null
          ? 'Ein Wort steht nicht in der Liste.'
          : '$detail steht nicht in der Liste.',
      'tile_not_in_rack' => 'Diesen Stein hast du nicht.',
      'too_many_tiles' => 'Mehr als sieben Steine gehen nicht.',
      'not_your_turn' => 'Der Gegner ist am Zug.',
      'stale_turn' => 'Die Partie hat sich geändert. Neu geladen.',
      'game_not_active' => 'Die Partie ist beendet.',
      'bag_too_small' => 'Zum Tauschen liegen zu wenige Steine im Beutel.',
      'pass_failed' => 'Passen hat nicht geklappt. Versuch es nochmal.',
      _ => 'Der Zug ging nicht durch ($code).',
    };

/// Nicht jeder Grund gehört aufs Brett. Beim Legen ist „noch keine Zeile" der
/// Normalzustand, und wer mitten im Wort steht, weiss das selbst. Gezeigt wird
/// nur, was man an den Steinen nicht ablesen kann.
///
/// Erlaubnisliste, kein Verbot: ein neuer Code schweigt, bis jemand
/// ausdrücklich entscheidet, dass er die Unterbrechung wert ist. Für den
/// Bericht nach einem abgelehnten Zug gilt das nicht – dort steht weiterhin
/// jeder Code, siehe [moveMessage].
const _spokenWhilePlacing = {
  'invalid_word', // sieht man dem Brett nicht an
  'first_move_must_cover_center', // die eine Regel, die man beim Eröffnen vergisst
  'dict_loading', // erklärt, warum noch keine Zahl dasteht
};

bool showsWhilePlacing(String code) => _spokenWhilePlacing.contains(code);
