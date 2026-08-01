// OneSignal REST API – ersetzt die eigene FCM-Anbindung.
//
// Zielt per external_id (= Supabase user_id, gesetzt via OneSignal.login im
// Client) statt über selbst verwaltete Geräte-Tokens. OneSignal fächert
// selbst auf alle Geräte/Browser dieser external_id auf.
//
// Benötigte Secrets (supabase secrets set …):
//   ONESIGNAL_APP_ID
//   ONESIGNAL_REST_API_KEY

const API_URL = "https://onesignal.com/api/v1/notifications";

export type PushResult = "sent" | "no_recipient" | "retry";

export interface PushMessage {
  externalUserId: string;
  title: string;
  body: string;
  /** Landet als Key-Value-Map in der App – für Deeplinks in die richtige Partie. */
  data: Record<string, string>;
  /** Anzahl offener Partien, in denen der Empfänger am Zug ist. */
  badge?: number;
  collapseKey?: string;
}

export async function sendPush(msg: PushMessage): Promise<PushResult> {
  const appId = Deno.env.get("ONESIGNAL_APP_ID")!;
  const apiKey = Deno.env.get("ONESIGNAL_REST_API_KEY")!;

  const res = await fetch(API_URL, {
    method: "POST",
    headers: {
      Authorization: `Basic ${apiKey}`,
      "Content-Type": "application/json; charset=utf-8",
    },
    body: JSON.stringify({
      app_id: appId,
      include_aliases: { external_id: [msg.externalUserId] },
      target_channel: "push",
      headings: { en: msg.title, de: msg.title },
      contents: { en: msg.body, de: msg.body },
      data: msg.data,
      collapse_id: msg.collapseKey,
      ...(msg.badge !== undefined
        ? { ios_badgeType: "SetTo", ios_badgeCount: msg.badge }
        : {}),
    }),
  });

  if (res.ok) {
    const result = await res.json();
    // Leere recipients-Liste: external_id kennt (noch) kein registriertes
    // Gerät – nichts zuzustellen, aber auch kein Fehler.
    if (!result.id || result.recipients === 0) return "no_recipient";
    return "sent";
  }

  const text = await res.text();
  // 429 / 5xx: später erneut versuchen.
  if (res.status === 429 || res.status >= 500) {
    console.error(`onesignal_error ${res.status}: ${text}`);
    return "retry";
  }
  console.error(`onesignal_error ${res.status}: ${text}`);
  return "no_recipient";
}
