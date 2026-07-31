#!/usr/bin/env python3
"""Hunspell-Wörterbuch zu Vollformen expandieren.

    python3 scripts/expand.py sources/de_DE.dic sources/fullforms.txt

Hunspell speichert Stämme plus Flags; die Flags verweisen auf Affixregeln in
der .aff-Datei. "Haus/N" heisst sinngemäss: nimm Haus und wende Regelgruppe N
an, das ergibt Hauses, Hause, Häuser und so weiter.

Bewusst nicht umgesetzt:

* Kompositaflags (COMPOUNDFLAG, COMPOUNDBEGIN, ...). Deutsche Komposita sind
  produktiv, die Menge wäre unendlich. Für ein Brett mit 15 Feldern lohnt sich
  der Aufwand nicht – lange Komposita spielt ohnehin niemand.
* Flag-Typ UTF-8 mit Mehrbyte-Flags. Praktisch kommt bei igerman98 der
  Standardtyp (ein Zeichen pro Flag) vor; long und num sind implementiert.

Das offizielle unmunch aus den hunspell-tools tut im Prinzip dasselbe, ist aber
nicht überall paketiert und schluckt Sonderfälle still. Deshalb hier explizit.
"""

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path


class Rule:
    __slots__ = ("kind", "cross", "strip", "add", "condition")

    def __init__(self, kind, cross, strip, add, condition):
        self.kind = kind          # "PFX" oder "SFX"
        self.cross = cross        # dürfen Präfix und Suffix kombiniert werden?
        self.strip = strip if strip != "0" else ""
        self.add = add if add != "0" else ""
        # Bedingung ist ein Zeichenklassen-Muster, verankert am Wortende (SFX)
        # bzw. Wortanfang (PFX).
        pattern = "." if condition == "." else condition
        self.condition = re.compile(
            pattern + "$" if kind == "SFX" else "^" + pattern
        )

    def applies(self, word):
        if self.kind == "SFX":
            if self.strip and not word.endswith(self.strip):
                return False
        else:
            if self.strip and not word.startswith(self.strip):
                return False
        return bool(self.condition.search(word))

    def apply(self, word):
        if self.kind == "SFX":
            base = word[: len(word) - len(self.strip)] if self.strip else word
            return base + self.add
        base = word[len(self.strip):] if self.strip else word
        return self.add + base


def parse_aff(path, encoding):
    """Liest die Affixdatei und gibt {flag: [Rule, ...]} plus Flagtyp zurück."""
    rules = defaultdict(list)
    flag_type = "char"

    with open(path, encoding=encoding, errors="replace") as fh:
        lines = fh.readlines()

    i = 0
    while i < len(lines):
        parts = lines[i].split()
        i += 1
        if not parts:
            continue

        if parts[0] == "FLAG" and len(parts) > 1:
            flag_type = parts[1]
            continue

        if parts[0] in ("PFX", "SFX") and len(parts) >= 4:
            kind, flag, cross, count = parts[0], parts[1], parts[2] == "Y", parts[3]
            if not count.isdigit():
                continue
            for _ in range(int(count)):
                if i >= len(lines):
                    break
                entry = lines[i].split()
                i += 1
                # Format: SFX flag strip add [condition] [morph...]
                if len(entry) < 4 or entry[0] != kind:
                    continue
                strip, add = entry[2], entry[3]
                condition = entry[4] if len(entry) > 4 else "."
                # Morphologische Anhängsel nach dem / abschneiden.
                add = add.split("/")[0]
                rules[flag].append(Rule(kind, cross, strip, add, condition))

    return rules, flag_type


def split_flags(raw, flag_type):
    if not raw:
        return []
    if flag_type == "long":
        return [raw[i:i + 2] for i in range(0, len(raw), 2)]
    if flag_type == "num":
        return [f for f in raw.split(",") if f]
    return list(raw)


def expand(dic_path, aff_path, out_path, encoding):
    rules, flag_type = parse_aff(aff_path, encoding)
    print(f"[expand] {sum(len(v) for v in rules.values())} Affixregeln, "
          f"Flagtyp {flag_type}", file=sys.stderr)

    seen = set()
    stems = 0

    with open(dic_path, encoding=encoding, errors="replace") as fh:
        first = fh.readline()  # erste Zeile ist die Stammanzahl
        for line in fh:
            line = line.strip()
            if not line or line.startswith("\t"):
                continue

            # Morphologie nach Tab verwerfen, dann Stamm/Flags trennen.
            line = line.split("\t")[0]
            if "/" in line:
                word, raw_flags = line.split("/", 1)
            else:
                word, raw_flags = line, ""
            word = word.replace("\\/", "/").strip()
            if not word:
                continue

            stems += 1
            seen.add(word)

            flags = split_flags(raw_flags, flag_type)
            prefixes = [r for f in flags for r in rules.get(f, []) if r.kind == "PFX"]
            suffixes = [r for f in flags for r in rules.get(f, []) if r.kind == "SFX"]

            suffixed = []
            for rule in suffixes:
                if rule.applies(word):
                    form = rule.apply(word)
                    suffixed.append((form, rule.cross))
                    seen.add(form)

            for rule in prefixes:
                if rule.applies(word):
                    seen.add(rule.apply(word))
                # Kreuzprodukt nur, wenn beide Seiten es erlauben.
                if not rule.cross:
                    continue
                for form, sfx_cross in suffixed:
                    if sfx_cross and rule.applies(form):
                        seen.add(rule.apply(form))

    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as out:
        for word in sorted(seen):
            out.write(word + "\n")

    print(f"[expand] {stems} Stämme → {len(seen)} Vollformen", file=sys.stderr)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("dic", help="Pfad zur .dic-Datei")
    ap.add_argument("out")
    ap.add_argument("--aff", help="Pfad zur .aff (Standard: wie .dic)")
    ap.add_argument("--encoding", default="ISO-8859-15",
                    help="Kodierung der Quelldateien; igerman98 nutzt Latin-9")
    args = ap.parse_args()

    aff = args.aff or str(Path(args.dic).with_suffix(".aff"))
    expand(args.dic, aff, args.out, args.encoding)
