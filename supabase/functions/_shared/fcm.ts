// Firebase Cloud Messaging – HTTP v1 API.
//
// Das alte Legacy-Protokoll mit statischem Server-Key ist abgeschaltet. v1
// verlangt ein OAuth2-Access-Token, das aus einem selbst signierten JWT des
// Service Accounts entsteht. Das Token gilt eine Stunde und wird hier gecacht.
//
// Benötigte Secrets (supabase secrets set …):
//   FCM_PROJECT_ID
//   FCM_CLIENT_EMAIL
//   FCM_PRIVATE_KEY      (der PEM-Block aus der Service-Account-JSON)

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_URL = "https://oauth2.googleapis.com/token";

function b64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string"
    ? bytes
    : String.fromCharCode(...bytes);
  return btoa(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

let tokenCache: { value: string; expiresAt: number } | null = null;

async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (tokenCache && tokenCache.expiresAt > now + 60) return tokenCache.value;

  const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL")!;
  // Aus der JSON kopierte Keys enthalten literale \n – die müssen echt werden.
  const privateKey = Deno.env.get("FCM_PRIVATE_KEY")!.replace(/\\n/g, "\n");

  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: clientEmail,
    scope: SCOPE,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  }));

  const key = await importPrivateKey(privateKey);
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(`${header}.${claims}`),
    ),
  );
  const assertion = `${header}.${claims}.${b64url(signature)}`;

  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`oauth_failed_${res.status}: ${await res.text()}`);

  const data = await res.json();
  tokenCache = { value: data.access_token, expiresAt: now + data.expires_in };
  return tokenCache.value;
}

export type PushResult = "sent" | "invalid_token" | "retry";

export interface PushMessage {
  token: string;
  title: string;
  body: string;
  /** Landet als Key-Value-Map in der App – für Deeplinks in die richtige Partie. */
  data: Record<string, string>;
  /** Anzahl offener Partien, in denen der Empfänger am Zug ist. */
  badge?: number;
  collapseKey?: string;
}

export async function sendPush(msg: PushMessage): Promise<PushResult> {
  const projectId = Deno.env.get("FCM_PROJECT_ID")!;
  const token = await accessToken();

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: msg.token,
          notification: { title: msg.title, body: msg.body },
          data: msg.data,
          android: {
            priority: "high",
            // collapse_key: neuere Nachricht zur selben Partie ersetzt die alte,
            // damit im Schacht nicht fünf Zug-Hinweise derselben Partie liegen.
            collapse_key: msg.collapseKey,
            notification: { channel_id: "turns", tag: msg.collapseKey },
          },
          apns: {
            headers: {
              "apns-priority": "10",
              ...(msg.collapseKey ? { "apns-collapse-id": msg.collapseKey } : {}),
            },
            payload: {
              aps: {
                sound: "default",
                ...(msg.badge !== undefined ? { badge: msg.badge } : {}),
                "thread-id": msg.data.game_id,
              },
            },
          },
        },
      }),
    },
  );

  if (res.ok) return "sent";

  const text = await res.text();

  // 404 UNREGISTERED oder 400 INVALID_ARGUMENT: Token ist tot, Gerät entfernen.
  if (res.status === 404 || text.includes("UNREGISTERED") || text.includes("INVALID_ARGUMENT")) {
    return "invalid_token";
  }
  // 429 / 5xx: später erneut versuchen.
  console.error(`fcm_error ${res.status}: ${text}`);
  return "retry";
}
