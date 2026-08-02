// POST /functions/v1/create-game
//
// Body:
//   { opponent_id: "<uuid>" }   Herausforderung an eine bestimmte Person
//   { random: true }            aus der Warteschlange verkuppeln
//
// Eine Herausforderung erzeugt eine Partie im Status "waiting". Erst die
// Annahme über respond_invitation macht sie aktiv. Beutel und Racks werden
// trotzdem schon hier gemischt und ausgeteilt – sie sind ohnehin für niemanden
// sichtbar, und so muss bei der Annahme nichts mehr schiefgehen können.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { newBag, RACK_SIZE, shuffle } from "../_shared/tiles.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const DICT_VERSION = Deno.env.get("DICT_VERSION") ?? "de-2026.1";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const authHeader = req.headers.get("Authorization") ?? "";
  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData } = await asUser.auth.getUser();
  const userId = userData?.user?.id;
  if (!userId) return json({ error: "unauthenticated" }, 401);

  const db = createClient(SUPABASE_URL, SERVICE_KEY);
  const body = await req.json().catch(() => ({}));

  // ---------- Gegner bestimmen ----------
  let opponentId: string | null = body.opponent_id ?? null;

  if (!opponentId && body.random) {
    const { data: waiting } = await db
      .from("matchmaking_queue")
      .select("player_id")
      .neq("player_id", userId)
      .order("joined_at", { ascending: true })
      .limit(1)
      .maybeSingle();

    if (!waiting) {
      // Niemand da – selbst anstellen und später abholen lassen.
      await db.from("matchmaking_queue").upsert({ player_id: userId });
      return json({ queued: true });
    }
    opponentId = waiting.player_id;
    await db.from("matchmaking_queue").delete().in("player_id", [userId, opponentId]);
  }

  if (!opponentId) return json({ error: "no_opponent" }, 400);
  if (opponentId === userId) return json({ error: "same_player" }, 400);

  // ---------- Beutel mischen und austeilen ----------
  // Seed festhalten, damit sich eine Partie im Zweifel nachstellen lässt.
  const seed = Math.floor(Math.random() * 2 ** 31);
  const bag = shuffle(newBag(), seed);

  const rackA = bag.splice(-RACK_SIZE, RACK_SIZE);
  const rackB = bag.splice(-RACK_SIZE, RACK_SIZE);
  const startingSeat = Math.random() < 0.5 ? 0 : 1;

  // Zufallssuche verkuppelt zwei Wartende und startet sofort – da hat sich
  // niemand jemanden ausgesucht, den man erst noch ablehnen müsste.
  const status = body.random ? "active" : "waiting";

  const { data, error } = await db.rpc("create_game", {
    p: {
      player_a: userId,
      player_b: opponentId,
      bag,
      rack_a: rackA,
      rack_b: rackB,
      tiles_left: bag.length,
      starting_seat: startingSeat,
      rng_seed: seed,
      dict_version: DICT_VERSION,
      status,
    },
  });

  if (error) {
    const known = ["same_player", "invite_pending"].find((code) =>
      error.message.includes(code)
    );
    return json({ error: known ?? "create_failed", detail: error.message }, known ? 409 : 500);
  }

  return json({
    game_id: data,
    status,
    starting_seat: startingSeat,
    dict_version: DICT_VERSION,
  });
});
