# Wörterbuch-Pipeline

Erzeugt aus einem Rechtschreibwörterbuch die spielbare Wortliste im
DAWG-Binärformat, das `supabase/functions/_shared/dawg.ts` und der Client lesen.

```
sources/de_DE.dic ──expand.py──▶ fullforms.txt ──filter.py──▶ filtered.txt
                                                                   │
                                              build_dawg.py ◀───────┘
                                                     │
                                            dist/de-2026.1.dawg
                                                     │
                                              verify.py (Abnahme)
                                                     │
                                        app/assets/dict/  +  Storage-Bucket
```

Kompletter Durchlauf:

```bash
cd dict
make            # baut dist/de-2026.1.dawg
make check      # Abnahme
make install    # kopiert nach app/assets/dict/
```

Die gebaute Datei muss zusätzlich in den Storage-Bucket `dict`, weil
`submit-move` sie serverseitig lädt:

```bash
supabase storage cp dist/de-2026.1.dawg ss:///dict/de-2026.1.dawg
```

## Warum die vier Schritte getrennt sind

**expand** ist teuer und deterministisch – einmal pro Quellversion. **filter**
ist der Schritt, an dem du über Monate schrauben wirst, wenn Spieler Wörter
melden. Die Trennung heisst: Filterregel ändern kostet Sekunden, nicht den
kompletten Neubau.

## Der eigentliche Knackpunkt: Eigennamen

Ein Rechtschreibwörterbuch will möglichst wenig anstreichen und nimmt deshalb
Städte, Vornamen und Marken mit auf. Im Deutschen sind alle Substantive gross
geschrieben, die Schreibung verrät also nichts.

Der Weg, der funktioniert: aus einem Wiktionary-Dump alle Einträge ziehen, die
als Vorname, Nachname, Toponym oder Eigenname ausgezeichnet sind, und diese
Liste als `sources/propernouns.txt` ablegen. `filter.py --exclude` zieht sie ab.
Ohne diese Datei läuft die Pipeline durch und meldet es – die Liste ist dann
aber spielerisch angreifbar.

Praktisch bezogen werden kann diese Liste aus dem PyPI-Paket `german_nouns`
(selbst aus einem Wiktionary-Dump gebaut): jedes `lemma`, dessen `pos`-Spalte
`Toponym`, `Vorname`, `Nachname`, `Eigenname` oder `Straßenname` enthält.
Homographen mit einem gewöhnlichen Substantiv-Eintrag (z.B. "Mühe" ist
zugleich Nachname) dabei aussparen, sonst verschwinden Alltagswörter aus der
Liste. Marken- und Firmennamen wie "Siemens" (dort als SI-Einheit geführt,
nicht als Eigenname) fängt das nicht ab – die kommen manuell in
`sources/brands.txt`, das genauso per `--exclude` eingebunden wird.

Rechne damit, dass Rest bleibt. Plane die Melde-Funktion in der App ein
(`word_reports` liegt schon im Schema) und schiebe alle paar Monate eine neue
Wörterbuchversion nach.

## Versionierung

Der Dateiname ist die Version, und `games.dict_version` hält fest, unter welcher
Liste eine Partie begonnen wurde. Laufende Partien behalten ihre Version –
sonst wird ein Wort, das gestern gültig war, morgen rückwirkend ungültig.
Erst neue Partien starten mit der neuen Liste.

## Lizenz

igerman98 steht unter GPL 2/3, LGPL 2.1/3 und MPL 1.1 zur Wahl. Die abgeleitete
Wortliste erbt diese Bedingungen – kläre vor dem Store-Release, welche der drei
Optionen zu deinem Vorhaben passt, und lege den Lizenztext der App bei. Halte
`sources/` aus dem Repo heraus und beziehe die Rohdaten über `make`.

Duden-Inhalte lassen sich hier nicht einsetzen, ohne eine Lizenz beim
Bibliographischen Institut zu erwerben.
