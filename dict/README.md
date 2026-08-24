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

Die ausgelieferte Datei ist damit reproduzierbar – **mit derselben
Quelldatei**. `make` ist deterministisch: gleiche `de_DE.dic`, gleiche
Kuratierung, Byte für Byte dieselbe `.dawg`.

Kompletter Durchlauf:

```bash
cd dict
make            # baut dist/de-2026.1.dawg
make check      # Abnahme
make install    # kopiert nach app/assets/dict/
```

Die gebaute Datei muss zusätzlich in den Storage-Bucket `dict`, weil
`submit-move` sie serverseitig lädt. `storage cp` verlangt das
`--experimental`-Flag; ausserdem verweigert es sich, wenn unter demselben
Namen schon etwas liegt (`KeyAlreadyExists`, HTTP 409) – ein Überschreiben
kennt der Befehl nicht. Solange der Dateiname gleich bleibt (Version nicht
hochgezählt, siehe *Versionierung*), also erst löschen, dann neu hochladen:

```bash
supabase storage rm ss:///dict/de-2026.1.dawg --experimental
supabase storage cp dist/de-2026.1.dawg ss:///dict/de-2026.1.dawg --experimental
```

Nur beim allerersten Hochladen unter einem neuen Dateinamen reicht `cp`
allein.

## Die Quelldateien gut aufheben

`sources/` ist leer, wenn du das Repo frisch klonst – die Rohdaten bleiben aus
Lizenzgründen draussen. Ohne sie bricht `make` sofort ab:

```
Fehlt: sources/de_DE.dic und de_DE.aff
```

**„Einfach neu beziehen" ist keine verlässliche Antwort.** igerman98 wird an
mehreren Stellen gespiegelt, und die Fassungen unterscheiden sich: Das
`de_DE_frami.dic` aus dem LibreOffice-Repo hat 4.356.903 Bytes, die hier
verwendete Datei 4.419.933. Damit gebaut, käme eine andere Wortliste heraus –
nicht falsch, aber eben nicht dieselbe, die in laufenden Partien gilt.

Bewahre `de_DE.dic` und `de_DE.aff` deshalb ausserhalb des Projekts auf
(Backup, USB-Stick, privater Speicher). Sie gehören nicht ins Repo, aber sie
sind auch nicht beliebig ersetzbar.

## Ein Wort nachtragen, Schritt für Schritt

Der häufigste Handgriff im laufenden Betrieb: Jemand legt ein Wort, das im
Duden steht, aber die Liste kennt es nicht.

### 1. Eintragen

`curation/extra.txt` öffnen und anhängen – ein Wort pro Zeile, Gross- und
Kleinschreibung egal, `ß` wird zu `SS`. Zeilen mit `#` sind Notizen:

```
# 2026-08-17, von Anna gemeldet: Städtenamen wie Duden-Wort spielbar
Aachen
```

### 2. Bauen

```bash
cd dict
make install
```

Auf diese Zeilen achten:

```
[filter] behalten 541340, davon 1 aus der Nachtragsliste
[filter] nachgetragen: AACHEN
```

Steht dort `davon 0`, war das Wort längst in der Liste – dann liegt das
Problem woanders, und die Schritte 3 bis 5 kannst du dir sparen.

### 3. Server versorgen

```bash
supabase storage rm ss:///dict/de-2026.1.dawg --experimental
supabase storage cp dist/de-2026.1.dawg ss:///dict/de-2026.1.dawg --experimental
```

Erst löschen, dann neu hochladen: `storage cp` überschreibt nicht, unter
diesem Namen liegt beim Nachtragen ja schon eine Fassung (Details oben unter
*Kompletter Durchlauf*). Ohne diesen Schritt rechnet `submit-move` weiter mit
der alten Liste: Die App zeigt den Zug als gültig an, der Server lehnt ihn ab.

### 4. App neu ausrollen

Der Client liest die Wortliste aus dem App-Bundle (`rootBundle.load` in
`app/lib/domain/dawg.dart`), nicht aus dem Netz. Eine neue Liste erreicht die
Spieler also erst mit einem neuen Build – Befehl siehe
[`docs/distribution.md`](../docs/distribution.md).

### 5. Sichern

```bash
git add dict/curation/extra.txt app/assets/dict/
git commit -m "Wörterbuch: Abece nachgetragen"
git push
```

### Und die Version?

Beim **Nachtragen bleibt `de-2026.1` stehen**, die Datei wird überschrieben.
Das ist unbedenklich, weil nur etwas dazukommt: Laufende Partien gewinnen ein
paar Wörter, aber nichts, was gestern galt, wird ungültig.

Wann du sie doch hochzählen musst, steht unter *Versionierung*.

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

Rechne damit, dass Rest bleibt. `curation/extra.txt` ist die Gegenrichtung –
Wörter, die trotz allem gelten sollen, weil sie als Eigenname ausgezeichnet
sind und trotzdem im Duden stehen. Schritt für Schritt oben unter
*Ein Wort nachtragen*.

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
