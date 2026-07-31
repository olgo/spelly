// Wörterbuch als DAWG (Directed Acyclic Word Graph).
//
// Binärformat (little endian):
//   Offset 0   : Magic "DAWG" (4 Byte)
//   Offset 4   : uint32  Formatversion
//   Offset 8   : uint32  Index des ersten Kindknotens der Wurzel
//   Offset 12  : uint32  Anzahl Knoten
//   Offset 16  : nodeCount * uint32
//
// Knoten-Encoding pro uint32:
//   Bit  0..7  : Buchstabenindex (0..28)
//   Bit  8     : Wortende
//   Bit  9     : letzter Knoten in der Geschwisterliste
//   Bit 10..31 : Index des ersten Kindes (0 = keine Kinder)
//
// Die Datei wird vom Wörterbuch-Build erzeugt und liegt im Storage-Bucket
// "dict" unter "<version>.dawg".

const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ";
const LETTER_INDEX = new Map<string, number>(
  [...ALPHABET].map((ch, i) => [ch, i]),
);

const CHAR_MASK = 0xff;
const TERMINAL_BIT = 1 << 8;
const LAST_BIT = 1 << 9;
const CHILD_SHIFT = 10;

export class Dawg {
  private constructor(
    private readonly nodes: Uint32Array,
    private readonly root: number,
    readonly version: string,
  ) {}

  static fromBuffer(buffer: ArrayBuffer, version: string): Dawg {
    const view = new DataView(buffer);
    const magic = String.fromCharCode(
      view.getUint8(0), view.getUint8(1), view.getUint8(2), view.getUint8(3),
    );
    if (magic !== "DAWG") throw new Error("dict_bad_magic");

    const root = view.getUint32(8, true);
    const count = view.getUint32(12, true);
    const nodes = new Uint32Array(buffer, 16, count);
    return new Dawg(nodes, root, version);
  }

  has(word: string): boolean {
    if (word.length === 0) return false;
    let node = this.root;
    if (node === 0) return false;

    for (let i = 0; i < word.length; i++) {
      const target = LETTER_INDEX.get(word[i]);
      if (target === undefined) return false;

      // Geschwisterliste linear durchsuchen (max. 29 Einträge).
      let found = -1;
      for (let n = node; ; n++) {
        const cell = this.nodes[n];
        if ((cell & CHAR_MASK) === target) { found = n; break; }
        if (cell & LAST_BIT) break;
      }
      if (found === -1) return false;

      const cell = this.nodes[found];
      if (i === word.length - 1) return (cell & TERMINAL_BIT) !== 0;

      node = cell >>> CHILD_SHIFT;
      if (node === 0) return false;
    }
    return false;
  }
}

// Kaltstart einmal laden, danach im Modulscope halten. Eine Instanz überlebt
// so viele Requests hinweg; ~5 MB sind im Speicherbudget unkritisch.
let cached: Promise<Dawg> | null = null;
let cachedVersion: string | null = null;

export function loadDawg(supabaseUrl: string, serviceKey: string, version: string): Promise<Dawg> {
  if (cached && cachedVersion === version) return cached;

  cachedVersion = version;
  cached = (async () => {
    const res = await fetch(
      `${supabaseUrl}/storage/v1/object/dict/${version}.dawg`,
      { headers: { Authorization: `Bearer ${serviceKey}` } },
    );
    if (!res.ok) throw new Error(`dict_fetch_failed_${res.status}`);
    return Dawg.fromBuffer(await res.arrayBuffer(), version);
  })();

  return cached;
}
