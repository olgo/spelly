// POST /functions/v1/submit-move
//
// Body:
//   { game_id, kind: "play"|"pass"|"exchange"|"resign",
//     placements?: [{r,c,l,b}], exchange?: ["A","?"] }
//
// Der Client schickt ausschliesslich seine Absicht. Legalität, Wörter, Punkte
// und das Nachziehen passieren hier – nie im Client.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { loadDawg } from "../_shared/dawg.ts";
import { playMove, RuleError, type Board, type Placement } from "../_shared/rules.ts";
import { RACK_SIZE, rackValue, shuffle } from "../_shared/tiles.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

const fail = (code: string, status = 400, detail?: unknown) =>
  json({ error: code, detail }, status);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return fail("method_not_allowed", 405);

  // ---------- Authentifizierung ----------
  const authHeader = req.headers.get("Authorization") ?? "";
  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData } = await asUser.auth.getUser();
  const userId = userData?.user?.id;
  if (!userId) return fail("unauthenticated", 401);

  const db = createClient(SUPABASE_URL, SERVICE_KEY);

  let body: {
    game_id?: string;
    kind?: string;
    placements?: Placement[];
    exchange?: string[];
  };
  try {
    body = await req.json();
  } catch {
    return fail("bad_json");
  }

  const { game_id: gameId, kind } = body;
  if (!gameId || !kind) return fail("missing_fields");

  // ---------- Zustand laden ----------
  const [gameRes, playersRes, rackRes, secretRes] = await Promise.all([
    db.from("games").select("*").eq("id", gameId).single(),
    db.from("game_players").select("*").eq("game_id", gameId),
    db.from("racks").select("*").eq("game_id", gameId).eq("player_id", userId).single(),
    db.from("game_secrets").select("*").eq("game_id", gameId).single(),
  ]);

  if (gameRes.error || !gameRes.data) return fail("game_not_found", 404);
  if (rackRes.error || !rackRes.data) return fail("not_a_participant", 403);

  const game = gameRes.data;
  const players = playersRes.data ?? [];
  const me = players.find((p) => p.player_id === userId);
  const opponent = players.find((p) => p.player_id !== userId);
  if (!me || !opponent) return fail("game_not_ready", 409);

  if (game.status !== "active") return fail("game_not_active", 409);
  if (game.current_seat !== me.seat) return fail("not_your_turn", 409);

  let bag: string[] = secretRes.data.bag;
  let rack: string[] = rackRes.data.tiles;
  let board: Board = game.board as Board;

  // ---------- Zug auswerten ----------
  let words: { w: string; s: number }[] = [];
  let score = 0;
  let placements: Placement[] = [];
  let passes = game.consecutive_passes;

  try {
    switch (kind) {
      case "play": {
        placements = body.placements ?? [];
        const dict = await loadDawg(SUPABASE_URL, SERVICE_KEY, game.dict_version);
        const result = playMove(board, rack, placements, dict);

        board = result.board;
        words = result.words;
        score = result.score;

        // Verbrauchte Steine entfernen, dann nachziehen.
        for (const tile of result.used) rack.splice(rack.indexOf(tile), 1);
        while (rack.length < RACK_SIZE && bag.length > 0) rack.push(bag.pop()!);
        passes = 0;
        break;
      }

      case "exchange": {
        const give = body.exchange ?? [];
        if (give.length === 0) return fail("nothing_to_exchange");
        if (bag.length < RACK_SIZE) return fail("bag_too_small");

        const check = rack.slice();
        for (const tile of give) {
          const at = check.indexOf(tile);
          if (at === -1) return fail("tile_not_in_rack", 400, tile);
          check.splice(at, 1);
        }
        rack = check;
        // Erst nachziehen, dann zurückgeben – sonst zieht man eigene Steine wieder.
        const drawn: string[] = [];
        while (drawn.length < give.length && bag.length > 0) drawn.push(bag.pop()!);
        bag = shuffle([...bag, ...give], secretRes.data.rng_seed ^ game.turn_number);
        rack = [...rack, ...drawn];
        passes = 0;
        break;
      }

      case "pass":
        passes += 1;
        break;

      case "resign":
        break;

      default:
        return fail("unknown_move_kind");
    }
  } catch (err) {
    if (err instanceof RuleError) return fail(err.message, 422, err.detail);
    console.error(err);
    return fail("internal_error", 500);
  }

  // ---------- Partieende prüfen ----------
  let status: string = "active";
  let winnerId: string | null = null;
  const adjustments: { player_id: string; delta: number }[] = [];

  const opponentRack = await db
    .from("racks").select("tiles")
    .eq("game_id", gameId).eq("player_id", opponent.player_id).single();
  const oppTiles: string[] = opponentRack.data?.tiles ?? [];

  if (kind === "resign") {
    status = "finished";
    winnerId = opponent.player_id;
  } else if (kind === "play" && bag.length === 0 && rack.length === 0) {
    // Ausgespielt: Restwerte des Gegners wandern zum Beender.
    const bonus = rackValue(oppTiles);
    adjustments.push({ player_id: userId, delta: bonus });
    adjustments.push({ player_id: opponent.player_id, delta: -bonus });
    status = "finished";
  } else if (passes >= 6) {
    // Sechs Nullzüge in Folge – jeder zieht seinen eigenen Restwert ab.
    adjustments.push({ player_id: userId, delta: -rackValue(rack) });
    adjustments.push({ player_id: opponent.player_id, delta: -rackValue(oppTiles) });
    status = "finished";
  }

  // ---------- Atomar schreiben ----------
  const { data, error } = await db.rpc("apply_move", {
    p: {
      game_id: gameId,
      player_id: userId,
      expected_turn: game.turn_number,
      seq: game.turn_number,
      kind,
      placements,
      words,
      score,
      board,
      rack,
      bag,
      tiles_left: bag.length,
      next_seat: opponent.seat,
      consecutive_passes: passes,
      status,
      winner_id: winnerId,
      adjustments,
    },
  });

  if (error) {
    // stale_turn heisst: der Gegner war schneller bzw. ein Doppel-Tap.
    const conflict = error.message.includes("stale_turn");
    return fail(conflict ? "stale_turn" : "write_failed", conflict ? 409 : 500, error.message);
  }

  return json({ ok: true, score, words, status, state: data });
});
