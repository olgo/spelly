# Wörterbuch-Pipeline

Erzeugt aus einem Rechtschreibwörterbuch die spielbare Wortliste im
DAWG-Binärformat, das `supabase/functions/_shared/dawg.ts` und der Client lesen.

```
sources/de_DE.dic ──expand.py──▶ fullforms.txt ──filter.py──▶ filtered.txt
                                                    ▲              │
                          curation/propernouns.txt ─┤              │
                          curation/extra.txt ───────┘              │
                                              build_dawg.py ◀──────┘
                                                     │
                                            dist/de-2026.1.dawg
                                                     │
                                              verify.py (Abnahme)
                                                     │
                                        app/assets/dict/  +  Storage-Bucket
```

Was im Repo liegt und was nicht:

| Verzeichnis | im Repo | warum |
|---|---|---|
| `curation/` | **ja** | Handarbeit. Über Monate gewachsene Entscheidungen, die sich nicht wiederbeschaffen lassen |
| `sources/` | nein | Rohdaten von igerman98, bleiben aus Lizenzgründen draussen (siehe unten) |
| `dist/` | nein | Bauergebnis. Die abgenommene Fassung liegt in `app/assets/dict/` |

Die ausgelieferte Datei ist damit **reproduzierbar**: Wer `sources/de_DE.dic`
neu bezieht und `make` laufen lässt, bekommt dieselbe `.dawg` Byte für Byte.

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
als Vorname, Nachname, Toponym oder Eigenname ausgezeichnet sind. Das Ergebnis
steht in `curation/propernouns.txt`, `filter.py --exclude` zieht es ab.

Rechne damit, dass Rest bleibt. Schiebe alle paar Monate eine neue
Wörterbuchversion nach.

## Wörter nachtragen

`curation/extra.txt` ist die Gegenrichtung: Wörter, die trotz allem gelten
sollen. Sie wirkt **nach** der Ausschlussprüfung, ein Eintrag hier schlägt also
`propernouns.txt`. Dafür ist sie da – es gibt Wörter, die als Eigenname
ausgezeichnet sind und trotzdem im Duden stehen.

Ein Wort pro Zeile, Gross- und Kleinschreibung egal. Zeilen mit `#` sind
Notizen: Hier wird über Monate von Hand entschieden, und warum ein Wort
drinsteht, ist später oft wichtiger als das Wort selbst.

```bash
cd dict
echo "Abece" >> curation/extra.txt
make install
```

`filter.py` gibt aus, welche Wörter tatsächlich neu dazugekommen sind – stand
eines schon in der Liste, sieht man das sofort.

Danach muss die neue Datei auch in den Storage-Bucket, sonst rechnet
`submit-move` weiter mit der alten. Und weil `games.dict_version` festhält,
unter welcher Liste eine Partie begonnen wurde, wirkt eine neue Version erst
für neue Partien (siehe *Versionierung*).

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

`curation/propernouns.txt` geht auf einen Wiktionary-Dump zurück und ist von
Hand nachgeschärft. Wiktionary steht unter CC BY-SA – die Herkunft gehört
deshalb in denselben Lizenzhinweis wie igerman98.

Duden-Inhalte lassen sich hier nicht einsetzen, ohne eine Lizenz beim
Bibliographischen Institut zu erwerben.
