#!/usr/bin/env python3
"""Gebaute DAWG-Datei abnehmen.

    python3 scripts/verify.py dist/de-2026.1.dawg --source sources/filtered.txt

Läuft in der CI vor jedem Release. Die Datei landet in der App und lässt sich
danach nicht mehr korrigieren, ohne ein Update auszurollen – ein kaputter Build
fällt hier auf oder gar nicht.
"""

import argparse
import hashlib
import struct
import sys

ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ"
LETTER_INDEX = {ch: i for i, ch in enumerate(ALPHABET)}
CHILD_SHIFT = 10

# Wörter, die drin sein müssen: Alltagsvokabular, Flexionen, Umlaute,
# ß-Normalisierung, sowie kurze Formen, die im Spiel viel entscheiden.
MUST_CONTAIN = [
    "HAUS", "HAUSES", "HÄUSER",
    "GEHEN", "GING", "GEGANGEN",
    "MÜHE", "ÖFEN", "ÄPFEL",
    "STRASSE", "FUSS",
    "AB", "ZU", "EI",
    "SPIEL", "SPIELTE", "GESPIELT",
]

# Wörter, die draussen bleiben müssen: Eigennamen, Marken, Abkürzungen,
# Fantasieformen.
MUST_NOT_CONTAIN = [
    "BERLIN", "SIEMENS", "MERKEL", "GOOGLE", "DUDEN",
    "XQZ", "BLARGH", "QQQQ",
]


class Reader:
    def __init__(self, path):
        with open(path, "rb") as fh:
            self.raw = fh.read()

        if self.raw[:4] != b"DAWG":
            raise SystemExit("Kopfkennung fehlt – falsche oder beschädigte Datei")

        self.version, self.root, self.count = struct.unpack_from("<III", self.raw, 4)
        self.body = self.raw[16:]

        expected = 4 * self.count
        if len(self.body) != expected:
            raise SystemExit(
                f"Länge passt nicht: {len(self.body)} Byte statt {expected}"
            )

    def has(self, word):
        node = self.root
        if node == 0 or not word:
            return False
        for position, ch in enumerate(word):
            target = LETTER_INDEX.get(ch)
            if target is None:
                return False
            found = None
            n = node
            while True:
                if n >= self.count:
                    raise SystemExit(f"Index {n} ausserhalb des Knotenfeldes")
                cell = struct.unpack_from("<I", self.body, 4 * n)[0]
                if cell & 0xFF == target:
                    found = cell
                    break
                if cell & 0x200:
                    break
                n += 1
            if found is None:
                return False
            if position == len(word) - 1:
                return bool(found & 0x100)
            node = found >> CHILD_SHIFT
            if node == 0:
                return False
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dawg")
    ap.add_argument("--source", help="Wortliste, aus der gebaut wurde")
    ap.add_argument("--max-mb", type=float, default=8.0,
                    help="Obergrenze für die Dateigrösse im App-Bundle")
    ap.add_argument("--min-words", type=int, default=100_000)
    args = ap.parse_args()

    reader = Reader(args.dawg)
    size_mb = len(reader.raw) / 1_000_000
    digest = hashlib.sha256(reader.raw).hexdigest()

    print(f"Version      {reader.version}")
    print(f"Übergänge    {reader.count}")
    print(f"Grösse       {size_mb:.2f} MB")
    print(f"sha256       {digest}")

    problems = []

    if size_mb > args.max_mb:
        problems.append(f"Datei zu gross: {size_mb:.2f} MB > {args.max_mb} MB")

    missing = [w for w in MUST_CONTAIN if not reader.has(w)]
    if missing:
        problems.append(f"Pflichtwörter fehlen: {', '.join(missing)}")

    present = [w for w in MUST_NOT_CONTAIN if reader.has(w)]
    if present:
        problems.append(f"Unerwünschte Einträge enthalten: {', '.join(present)}")

    if args.source:
        total = 0
        failed = []
        with open(args.source, encoding="utf-8") as fh:
            for line in fh:
                word = line.strip()
                if not word:
                    continue
                total += 1
                # Vollständig gegenprüfen: der Bau darf kein einziges Wort verlieren.
                if not reader.has(word):
                    failed.append(word)
                    if len(failed) > 20:
                        break

        print(f"Quellwörter  {total}")
        if failed:
            problems.append(
                f"{len(failed)}+ Wörter aus der Quelle nicht auffindbar, "
                f"z. B. {', '.join(failed[:5])}"
            )
        if total < args.min_words:
            problems.append(f"Nur {total} Wörter – erwartet mindestens {args.min_words}")

    if problems:
        print("\nAbnahme fehlgeschlagen:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        sys.exit(1)

    print("\nAbnahme bestanden.")


if __name__ == "__main__":
    main()
