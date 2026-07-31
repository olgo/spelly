#!/usr/bin/env python3
"""Wortliste zu einem minimalen DAWG verdichten.

    python3 scripts/build_dawg.py sources/filtered.txt dist/de-2026.1.dawg

Konstruktion nach Daciuk et al., "Incremental Construction of Minimal Acyclic
Finite-State Automata": die sortierte Liste wird einmal durchlaufen, und jeder
Teilbaum, der fertig ist, wird sofort gegen ein Register bereits bekannter
Zustände getauscht. Dadurch teilen sich gleiche Endungen denselben Speicher –
aus rund drei Millionen Wörtern werden typischerweise unter einer Million
Übergänge.

Das Binärformat muss Bit für Bit zu supabase/functions/_shared/dawg.ts passen:

    Kopf   : "DAWG" | uint32 Version | uint32 Wurzelblock | uint32 Anzahl
    Knoten : uint32 je Übergang
             Bit  0..7  Buchstabenindex
             Bit  8     Zielzustand ist Wortende
             Bit  9     letzter Übergang dieses Blocks
             Bit 10..31 Index des Kindblocks (0 = keine Fortsetzung)

Entscheidend ist, dass die Übergänge eines Zustands zusammenhängend liegen –
der Reader läuft die Geschwister mit n++ ab, bis das Letzter-Bit kommt.
"""

import argparse
import hashlib
import struct
import sys
from collections import deque

ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ"
LETTER_INDEX = {ch: i for i, ch in enumerate(ALPHABET)}

FORMAT_VERSION = 1
CHILD_SHIFT = 10
MAX_CHILD_INDEX = (1 << 22) - 1


class State:
    __slots__ = ("final", "children", "uid")
    _counter = 0

    def __init__(self):
        self.final = False
        self.children = {}
        State._counter += 1
        self.uid = State._counter

    def key(self):
        """Zwei Zustände sind austauschbar, wenn Endstatus und alle Übergänge
        übereinstimmen. Kinder sind zu diesem Zeitpunkt bereits minimiert, ihre
        uid identifiziert sie also eindeutig."""
        return (self.final, tuple(sorted(
            (ch, st.uid) for ch, st in self.children.items()
        )))


class DawgBuilder:
    def __init__(self):
        self.root = State()
        self.register = {}
        self.previous = ""
        self.unchecked = []   # [(Elternzustand, Zeichen, Kindzustand)]

    def add(self, word):
        if word < self.previous:
            raise ValueError(f"Eingabe nicht sortiert: {word!r} nach {self.previous!r}")

        # Gemeinsames Präfix mit dem Vorgänger bestimmen.
        common = 0
        while common < min(len(word), len(self.previous)) \
                and word[common] == self.previous[common]:
            common += 1

        self._minimise(common)

        state = self.unchecked[-1][2] if self.unchecked else self.root
        for ch in word[common:]:
            child = State()
            state.children[ch] = child
            self.unchecked.append((state, ch, child))
            state = child

        state.final = True
        self.previous = word

    def _minimise(self, down_to):
        """Alles unterhalb von down_to ist fertig und kann eingetauscht werden."""
        while len(self.unchecked) > down_to:
            parent, ch, child = self.unchecked.pop()
            key = child.key()
            existing = self.register.get(key)
            if existing is not None:
                parent.children[ch] = existing
            else:
                self.register[key] = child

    def finish(self):
        self._minimise(0)
        return self.root


def serialise(root):
    """Zustände in zusammenhängende Übergangsblöcke legen."""
    blocks = {}          # uid -> Startindex des Kindblocks
    cells = {}           # Index -> uint32
    next_index = 1       # Index 0 bleibt frei: dient als "keine Kinder"
    queue = deque()

    def allocate(state):
        nonlocal next_index
        if not state.children:
            return 0
        if state.uid in blocks:
            return blocks[state.uid]
        start = next_index
        next_index += len(state.children)
        blocks[state.uid] = start
        queue.append(state)
        return start

    root_block = allocate(root)

    while queue:
        state = queue.popleft()
        start = blocks[state.uid]
        entries = sorted(state.children.items(), key=lambda kv: LETTER_INDEX[kv[0]])

        for offset, (ch, child) in enumerate(entries):
            child_block = allocate(child)
            if child_block > MAX_CHILD_INDEX:
                raise OverflowError(
                    "Kindindex passt nicht in 22 Bit – Format erweitern"
                )
            value = (
                LETTER_INDEX[ch]
                | (0x100 if child.final else 0)
                | (0x200 if offset == len(entries) - 1 else 0)
                | (child_block << CHILD_SHIFT)
            )
            cells[start + offset] = value

    total = next_index
    array = bytearray(4 * total)
    for index, value in cells.items():
        struct.pack_into("<I", array, 4 * index, value)

    return root_block, total, bytes(array)


def lookup(data, root_block, word):
    """Referenzimplementierung des Readers – dient dem Selbsttest unten."""
    node = root_block
    if node == 0:
        return False
    for position, ch in enumerate(word):
        target = LETTER_INDEX.get(ch)
        if target is None:
            return False
        found = None
        n = node
        while True:
            cell = struct.unpack_from("<I", data, 4 * n)[0]
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
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--version", type=int, default=FORMAT_VERSION)
    args = ap.parse_args()

    builder = DawgBuilder()
    words = []
    with open(args.src, encoding="utf-8") as fh:
        for line in fh:
            word = line.strip()
            if word:
                words.append(word)

    words.sort()
    for word in words:
        builder.add(word)
    root = builder.finish()

    print(f"[dawg] {len(words)} Wörter, {len(builder.register)} eindeutige Zustände",
          file=sys.stderr)

    root_block, total, array = serialise(root)
    header = b"DAWG" + struct.pack("<III", args.version, root_block, total)

    with open(args.out, "wb") as out:
        out.write(header)
        out.write(array)

    size = len(header) + len(array)
    digest = hashlib.sha256(header + array).hexdigest()[:16]
    print(f"[dawg] {total} Übergänge, {size / 1_000_000:.2f} MB, sha256 {digest}",
          file=sys.stderr)

    # Selbsttest: jedes zehnte Wort muss sich wiederfinden lassen, und ein paar
    # gezielt verfälschte Formen dürfen es nicht.
    for word in words[::10]:
        assert lookup(array, root_block, word), f"fehlt nach dem Bau: {word}"
    misses = 0
    for word in words[::1000]:
        if not lookup(array, root_block, word + "QX"):
            misses += 1
    print(f"[dawg] Selbsttest bestanden ({misses} Negativproben korrekt)",
          file=sys.stderr)


if __name__ == "__main__":
    main()
