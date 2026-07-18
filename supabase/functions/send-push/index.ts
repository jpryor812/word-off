// Sends APNs push via HTTP/2 using an Apple Auth Key (.p8).
// Secrets (Dashboard → Edge Functions → Secrets):
//   APNS_KEY_P8          — full .p8 PEM contents (including BEGIN/END lines)
//   APNS_KEY_ID          — Key ID from Apple Developer
//   APNS_TEAM_ID         — Apple Team ID
//   APNS_BUNDLE_ID       — e.g. com.yourco.Worded
//   APNS_PRODUCTION      — "true" for App Store / TestFlight, "false" for Xcode debug
//   SUPABASE_SERVICE_ROLE_KEY — auto-provided in hosted projects
//   SUPABASE_URL         — auto-provided

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { SignJWT, importPKCS8 } from "https://esm.sh/jose@5.9.6";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type PushBody = {
  to_user_id: string;
  title: string;
  body: string;
  data?: Record<string, string>;
  type?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "missing auth" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? serviceKey;
    const bearer = authHeader.replace(/^Bearer\s+/i, "").trim();

    // Allow service role (dashboard/CLI tests) or a signed-in user JWT.
    const isService =
      bearer === serviceKey || jwtRole(bearer) === "service_role";
    if (!isService) {
      const userClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: authHeader } },
      });
      const { data: authData, error: authErr } = await userClient.auth.getUser();
      if (authErr || !authData.user) {
        return json({ error: "unauthorized" }, 401);
      }
    }

    const payload = (await req.json()) as PushBody;
    if (!payload.to_user_id || !payload.title || !payload.body) {
      return json({ error: "to_user_id, title, body required" }, 400);
    }

    const admin = createClient(supabaseUrl, serviceKey);
    const { data: tokens, error: tokErr } = await admin
      .from("device_tokens")
      .select("token, environment")
      .eq("user_id", payload.to_user_id);

    if (tokErr) return json({ error: tokErr.message }, 500);
    if (!tokens?.length) return json({ sent: 0, reason: "no_tokens" });

    const keyP8 = Deno.env.get("APNS_KEY_P8");
    const keyId = Deno.env.get("APNS_KEY_ID");
    const teamId = Deno.env.get("APNS_TEAM_ID");
    const bundleId = Deno.env.get("APNS_BUNDLE_ID");
    if (!keyP8 || !keyId || !teamId || !bundleId) {
      return json({ error: "APNs secrets not configured" }, 500);
    }

    const jwt = await apnsJwt(keyP8, keyId, teamId);
    let sent = 0;
    const errors: string[] = [];

    for (const row of tokens) {
      // Prefer per-token env; fall back to global flag for older rows.
      const useSandbox =
        row.environment === "sandbox" ||
        (row.environment !== "production" &&
          Deno.env.get("APNS_PRODUCTION") !== "true");
      const base = useSandbox
        ? "https://api.sandbox.push.apple.com"
        : "https://api.push.apple.com";

      const apnsBody = {
        aps: {
          alert: { title: payload.title, body: payload.body },
          sound: "default",
        },
        ...payload.data,
      };

      const res = await fetch(`${base}/3/device/${row.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": bundleId,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: JSON.stringify(apnsBody),
      });

      if (res.ok) {
        sent += 1;
      } else {
        const text = await res.text();
        errors.push(`${res.status}: ${text}`);
        // Drop dead tokens.
        if (res.status === 410 || res.status === 400) {
          await admin
            .from("device_tokens")
            .delete()
            .eq("user_id", payload.to_user_id)
            .eq("token", row.token);
        }
      }
    }

    return json({ sent, errors: errors.slice(0, 5) });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function normalizeApnsKey(raw: string): string {
  let pem = raw.trim();
  // Secrets UI sometimes wraps the whole value in quotes.
  if (
    (pem.startsWith('"') && pem.endsWith('"')) ||
    (pem.startsWith("'") && pem.endsWith("'"))
  ) {
    pem = pem.slice(1, -1);
  }
  pem = pem.replace(/\r\n/g, "\n").replace(/\\n/g, "\n").trim();

  // If only the base64 body was pasted, wrap it as PKCS#8 PEM.
  if (!pem.includes("BEGIN")) {
    const body = pem.replace(/\s+/g, "");
    const lines = body.match(/.{1,64}/g) ?? [body];
    pem = `-----BEGIN PRIVATE KEY-----\n${lines.join("\n")}\n-----END PRIVATE KEY-----`;
  }
  return pem;
}

async function apnsJwt(pem: string, keyId: string, teamId: string) {
  const normalized = normalizeApnsKey(pem);
  const key = await importPKCS8(normalized, "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt()
    .setExpirationTime("50m")
    .sign(key);
}

function jwtRole(token: string): string | null {
  try {
    const part = token.split(".")[1];
    if (!part) return null;
    const json = atob(part.replace(/-/g, "+").replace(/_/g, "/"));
    const payload = JSON.parse(json) as { role?: string };
    return payload.role ?? null;
  } catch {
    return null;
  }
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
