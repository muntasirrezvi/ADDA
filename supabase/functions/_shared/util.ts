// Shared helpers for Adda Edge Functions
import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

export function env(name: string, required = true): string {
  const v = Deno.env.get(name) ?? "";
  if (required && !v) throw new Error(`Missing secret ${name}`);
  return v;
}

/** Service-role client: bypasses row level security. Server use only. */
export function adminClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });
}

/** Client that acts as the signed-in user, so database rules and auth.uid() apply. */
export function userClient(req: Request): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    auth: { persistSession: false },
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
}

export async function requireUser(req: Request): Promise<User> {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) throw new HttpError(401, "Sign in first");
  const { data, error } = await adminClient().auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, "Session expired, sign in again");
  return data.user;
}

export class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

/** Wraps a handler with CORS and error handling. */
export function serve(handler: (req: Request) => Promise<Response>) {
  Deno.serve(async (req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    try {
      return await handler(req);
    } catch (e) {
      const status = e instanceof HttpError ? e.status : 500;
      const message = e instanceof Error ? e.message : String(e);
      if (status >= 500) console.error(e);
      return json({ error: message }, status);
    }
  });
}

/** OAuth access token for a Google service account (Play Developer API, Firebase Cloud Messaging). */
const tokenCache = new Map<string, { token: string; exp: number }>();
export async function googleAccessToken(serviceAccountJson: string, scope: string): Promise<string> {
  const cached = tokenCache.get(scope);
  if (cached && cached.exp > Date.now() + 60_000) return cached.token;
  const sa = JSON.parse(serviceAccountJson) as { client_email: string; private_key: string; token_uri?: string };
  const aud = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const key = await importPKCS8(sa.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email).setSubject(sa.client_email).setAudience(aud)
    .setIssuedAt(now).setExpirationTime(now + 3600)
    .sign(key);
  const res = await fetch(aud, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`Google auth failed: ${body.error_description ?? body.error ?? res.status}`);
  tokenCache.set(scope, { token: body.access_token, exp: Date.now() + body.expires_in * 1000 });
  return body.access_token;
}

/** SSLCommerz host: sandbox until the SSLCOMMERZ_LIVE secret is "true". */
export function sslBase(): string {
  return env("SSLCOMMERZ_LIVE", false) === "true" ? "https://securepay.sslcommerz.com" : "https://sandbox.sslcommerz.com";
}
