// POST /functions/v1/send-push
//
// Wird angestossen vom DB-Trigger (sofort nach einem Zug) und zusätzlich
// minütlich von pg_cron als Netz für ausgefallene Zustellungen. Der Body ist
// leer – die Function holt sich ihre Arbeit selbst aus der Warteschlange.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendPush } from "../_shared/fcm.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BATCH = 50;

type Locale = "de" | "en";

interface QueueRow {
  id: number;
  recipient_id: string;
  game_id: string;
  kind:
    | "your_turn"
    | "reminder"
    | "game_over"
    | "invite"
    | "invite_accepted"
    | "invite_declined";
  payload: {
    move_kind?: string;
    score?: number;
    words?: { w: string; s: number }[];
    actor_id?: string;
  };
}

// ---------- Texte ----------
// Bewusst hier und nicht im Client: eine Push-Nachricht muss auch ankommen,
// wenn die App gar nicht läuft. Fällt die Sprache weg, greift Deutsch.

const TEXTS = {
  de: {
    your_turn: (name: string) => ({
      title: "Du bist dran",
      body: `${name} hat gezogen.`,
    }),
    your_turn_scored: (name: string, word: string, score: number) => ({
      title: "Du bist dran",
      body: `${name} legt ${word} für ${score} Punkte.`,
    }),
    passed: (name: string) => ({
      title: "Du bist dran",
      body: `${name} hat gepasst.`,
    }),
    reminder: (name: string) => ({
      title: "Deine Partie wartet",
      body: `Gegen ${name} bist du seit einem Tag am Zug.`,
    }),
    won: (name: string) => ({ title: "Gewonnen", body: `Du schlägst ${name}.` }),
    lost: (name: string) => ({ title: "Partie beendet", body: `${name} gewinnt.` }),
    invite: (name: string) => ({
      title: "Herausforderung",
      body: `${name} will gegen dich spielen.`,
    }),
    accepted: (name: string) => ({
      title: "Angenommen",
      body: `${name} spielt mit. Los geht's.`,
    }),
    declined: (name: string) => ({
      title: "Abgelehnt",
      body: `${name} mag gerade nicht.`,
    }),
  },
  en: {
    your_turn: (name: string) => ({
      title: "Your turn",
      body: `${name} has played.`,
    }),
    your_turn_scored: (name: string, word: string, score: number) => ({
      title: "Your turn",
      body: `${name} played ${word} for ${score} points.`,
    }),
    passed: (name: string) => ({ title: "Your turn", body: `${name} passed.` }),
    reminder: (name: string) => ({
      title: "A game is waiting",
      body: `It has been your turn against ${name} for a day.`,
    }),
    won: (name: string) => ({ title: "You won", body: `You beat ${name}.` }),
    lost: (name: string) => ({ title: "Game over", body: `${name} wins.` }),
    invite: (name: string) => ({
      title: "Challenge",
      body: `${name} wants to play you.`,
    }),
    accepted: (name: string) => ({
      title: "Accepted",
      body: `${name} is in. Your move.`,
    }),
    declined: (name: string) => ({
      title: "Declined",
      body: `${name} passed on this one.`,
    }),
  },
} as const;

function buildText(row: QueueRow, opponentName: string, won: boolean, locale: Locale) {
  const t = TEXTS[locale] ?? TEXTS.de;

  switch (row.kind) {
    case "invite":
      return t.invite(opponentName);
    case "invite_accepted":
      return t.accepted(opponentName);
    case "invite_declined":
      return t.declined(opponentName);
    case "reminder":
      return t.reminder(opponentName);
    case "game_over":
      return won ? t.won(opponentName) : t.lost(opponentName);
    case "your_turn": {
      if (row.payload.move_kind === "pass" || row.payload.move_kind === "exchange") {
        return t.passed(opponentName);
      }
      const best = row.payload.words?.[0];
      return best && row.payload.score
        ? t.your_turn_scored(opponentName, best.w, row.payload.score)
        : t.your_turn(opponentName);
    }
  }
}

Deno.serve(async (req) => {
  // Nur der Service-Role-Key darf hier hinein – kein Nutzer-JWT.
  const auth = req.headers.get("Authorization") ?? "";
  if (auth !== `Bearer ${SERVICE_KEY}`) {
    return new Response("forbidden", { status: 403 });
  }

  const db = createClient(SUPABASE_URL, SERVICE_KEY);

  const { data: jobs, error } = await db.rpc("claim_notifications", { p_limit: BATCH });
  if (error) {
    console.error("claim failed", error);
    return new Response("claim_failed", { status: 500 });
  }
  if (!jobs?.length) return Response.json({ processed: 0 });

  let sent = 0;
  let dropped = 0;

  for (const row of jobs as QueueRow[]) {
    try {
      // Empfänger, Gegner und Geräte in einem Rutsch.
      const [profileRes, playersRes, devicesRes, gameRes] = await Promise.all([
        db.from("profiles").select("display_name, locale").eq("id", row.recipient_id).single(),
        db.from("game_players").select("player_id, score, profiles(display_name)").eq("game_id", row.game_id),
        db.from("devices").select("id, fcm_token").eq("user_id", row.recipient_id),
        db.from("games").select("winner_id").eq("id", row.game_id).single(),
      ]);

      const devices = devicesRes.data ?? [];
      if (devices.length === 0) {
        // Kein Gerät registriert – nichts zuzustellen, aber auch kein Fehler.
        await db.from("notification_queue")
          .update({ state: "sent", sent_at: new Date().toISOString(), last_error: "no_devices" })
          .eq("id", row.id);
        continue;
      }

      const opponent = (playersRes.data ?? []).find((p) => p.player_id !== row.recipient_id);
      const opponentName =
        (opponent?.profiles as { display_name?: string } | null)?.display_name ?? "Dein Gegner";
      const locale = (profileRes.data?.locale ?? "de") as Locale;
      const won = gameRes.data?.winner_id === row.recipient_id;

      const { title, body } = buildText(row, opponentName, won, locale);

      // Badge: in wie vielen aktiven Partien ist der Empfänger am Zug?
      const { data: badge } = await db.rpc("turns_waiting", { p_user: row.recipient_id });

      const results = await Promise.all(
        devices.map((d) =>
          sendPush({
            token: d.fcm_token,
            title,
            body,
            badge: badge ?? undefined,
            // Eine neuere Meldung zur selben Partie ersetzt die ältere.
            collapseKey: `game_${row.game_id}`,
            data: {
              game_id: row.game_id,
              kind: row.kind,
              // Der Client öffnet damit direkt die richtige Partie.
              route: `/game/${row.game_id}`,
            },
          }).then((result) => ({ deviceId: d.id, result }))
        ),
      );

      // Tote Tokens sofort entfernen – sie werden sonst bei jedem Zug erneut
      // angefragt und zählen gegen das FCM-Kontingent.
      const dead = results.filter((r) => r.result === "invalid_token").map((r) => r.deviceId);
      if (dead.length) {
        await db.from("devices").delete().in("id", dead);
        dropped += dead.length;
      }

      const anySent = results.some((r) => r.result === "sent");
      const anyRetry = results.some((r) => r.result === "retry");

      if (anySent || !anyRetry) {
        await db.from("notification_queue")
          .update({ state: "sent", sent_at: new Date().toISOString() })
          .eq("id", row.id);
        if (anySent) sent++;
      } else {
        // Alles auf retry: zurück in die Schlange, claim_notifications holt
        // den Eintrag beim nächsten Lauf erneut (max. 5 Versuche).
        await db.from("notification_queue")
          .update({ state: "failed", last_error: "fcm_retry" })
          .eq("id", row.id);
      }
    } catch (err) {
      console.error(`notification ${row.id} failed`, err);
      await db.from("notification_queue")
        .update({ state: "failed", last_error: String(err).slice(0, 500) })
        .eq("id", row.id);
    }
  }

  return Response.json({ processed: jobs.length, sent, dropped_tokens: dropped });
});
