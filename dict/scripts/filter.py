#!/usr/bin/env python3
"""Vollformen zu einer spielbaren Wortliste filtern.

    python3 scripts/filter.py sources/fullforms.txt sources/filtered.txt \\
        --exclude sources/propernouns.txt

Ein Rechtschreibwörterbuch und eine Wortspiel-Liste sind nicht dasselbe. Der
Rechtschreibprüfer soll möglichst wenig anstreichen und nimmt deshalb
Eigennamen, Abkürzungen und Markennamen mit auf. Genau die müssen hier raus,
sonst gewinnt irgendwann jemand mit SIEMENS.

Der Eigennamen-Schritt ist der einzige, der externe Daten braucht. Im Deutschen
sind alle Substantive gross – die Schreibung verrät also nichts. Eine
brauchbare Ausschlussliste baust du aus einem Wiktionary-Dump: alle Einträge
mit der Wortart "Nachname", "Vorname", "Toponym" oder "Eigenname" abziehen.
"""

import argparse
import sys
import unicodedata

ALPHABET = set("ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ")
MIN_LEN = 2
MAX_LEN = 15


def normalise(word):
    """Auf Spielsteine abbilden. Gibt None zurück, wenn das Wort ausscheidet."""
    # Zusammengesetzte Unicode-Formen vereinheitlichen (ä als a+Trema kommt vor).
    word = unicodedata.normalize("NFC", word).strip()
    if not word:
        return None

    word = word.upper()

    # Es gibt keinen ß-Stein. In der deutschen Turnierpraxis wird ß als SS
    # gelegt, also hier genauso normalisiert.
    word = word.replace("ß", "SS").replace("ẞ", "SS")

    # Nach der Ersetzung erneut messen – aus MASS wird nichts, aus STRASSE
    # könnte ein Wort über die Längengrenze rutschen.
    if not (MIN_LEN <= len(word) <= MAX_LEN):
        return None

    if not set(word) <= ALPHABET:
        return None

    return word


def load_list(paths, kind):
    """Wörter aus Kuratierungslisten lesen.

    Zeilen mit # sind Notizen: In diesen Dateien wird über Monate von Hand
    entschieden, und warum etwas drinsteht, ist später oft wichtiger als das
    Wort selbst.
    """
    words = set()
    for path in paths:
        try:
            with open(path, encoding="utf-8") as fh:
                for line in fh:
                    if line.lstrip().startswith("#"):
                        continue
                    form = normalise(line)
                    if form:
                        words.add(form)
        except FileNotFoundError:
            print(f"[filter] {kind} fehlt, übersprungen: {path}",
                  file=sys.stderr)
    return words


def main():
    global MAX_LEN

    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--exclude", action="append", default=[],
                    help="Datei mit auszuschliessenden Wörtern, mehrfach möglich")
    ap.add_argument("--include", action="append", default=[],
                    help="Datei mit Wörtern, die zusätzlich aufgenommen werden")
    ap.add_argument("--max-len", type=int, default=MAX_LEN)
    args = ap.parse_args()

    MAX_LEN = args.max_len

    excluded = load_list(args.exclude, "Ausschlussliste")
    included = load_list(args.include, "Nachtragsliste")
    print(f"[filter] {len(excluded)} Ausschlüsse, {len(included)} Nachträge "
          "geladen", file=sys.stderr)

    stats = {"gelesen": 0, "zeichen": 0, "laenge": 0, "eigenname": 0}
    words = set()

    with open(args.src, encoding="utf-8") as fh:
        for line in fh:
            stats["gelesen"] += 1
            raw = unicodedata.normalize("NFC", line.strip()).upper()
            form = normalise(line)

            if form is None:
                # Für die Statistik grob unterscheiden, woran es lag.
                if raw and not set(raw.replace("ß", "SS")) <= ALPHABET:
                    stats["zeichen"] += 1
                else:
                    stats["laenge"] += 1
                continue

            if form in excluded:
                stats["eigenname"] += 1
                continue

            words.add(form)

    # Nachträge zuletzt und damit nach der Ausschlussprüfung: Ein Wort in der
    # Nachtragsliste schlägt einen Eintrag in der Ausschlussliste. Genau dafür
    # ist sie da – es gibt Wörter, die als Eigenname markiert sind und trotzdem
    # im Duden stehen.
    added = included - words
    words |= included

    with open(args.out, "w", encoding="utf-8") as out:
        for word in sorted(words):
            out.write(word + "\n")

    by_length = {}
    for word in words:
        by_length[len(word)] = by_length.get(len(word), 0) + 1

    print(f"[filter] gelesen {stats['gelesen']}, "
          f"verworfen: Zeichen {stats['zeichen']}, "
          f"Länge {stats['laenge']}, Eigenname {stats['eigenname']}",
          file=sys.stderr)
    print(f"[filter] behalten {len(words)}, davon {len(added)} aus der "
          "Nachtragsliste", file=sys.stderr)
    if added:
        print(f"[filter] nachgetragen: {' '.join(sorted(added))}",
              file=sys.stderr)
    print("[filter] Verteilung nach Länge:", file=sys.stderr)
    for length in sorted(by_length):
        print(f"          {length:2d}: {by_length[length]}", file=sys.stderr)

    # Zweibuchstabige Wörter entscheiden im Wortspiel überproportional viel.
    # Deshalb hier explizit ausgeben, damit du sie einmal von Hand durchsiehst.
    twos = sorted(w for w in words if len(w) == 2)
    print(f"[filter] Zweibuchstabige ({len(twos)}): {' '.join(twos)}",
          file=sys.stderr)


if __name__ == "__main__":
    main()
