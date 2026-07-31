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
      _ => 'Der Zug ging nicht durch ($code).',
    };
