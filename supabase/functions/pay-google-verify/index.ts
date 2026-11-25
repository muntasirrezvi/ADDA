// POST { productId: "coins_5m", purchaseToken: "..." }
// Called by the app right after a Google Play purchase. Verifies the token with Google,
// adds the coins once, then consumes the purchase so the user can buy the same pack again.
// In the app, set obfuscatedAccountId to the user's id when starting the purchase.
import { adminClient, env, googleAccessToken, HttpError, json, requireUser, serve } from "../_shared/util.ts";

const SCOPE = "https://www.googleapis.com/auth/androidpublisher";

serve(async (req) => {
  const user = await requireUser(req);
  const { productId, purchaseToken } = await req.json().catch(() => ({}));
  if (!productId || !purchaseToken) throw new HttpError(400, "productId and purchaseToken are required");

  const pkg = env("ANDROID_PACKAGE_NAME");
  const token = await googleAccessToken(env("GOOGLE_SERVICE_ACCOUNT_JSON"), SCOPE);
  const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}`;

  const res = await fetch(base, { headers: { Authorization: `Bearer ${token}` } });
  const p = await res.json();
  if (!res.ok) throw new HttpError(400, p.error?.message ?? "Google could not find this purchase");
  if (p.purchaseState !== 0) throw new HttpError(402, p.purchaseState === 2 ? "Payment is still pending" : "Purchase was cancelled");
  if (p.obfuscatedExternalAccountId && p.obfuscatedExternalAccountId !== user.id) throw new HttpError(403, "This purchase belongs to another account");

  const { data, error } = await adminClient().rpc("record_store_purchase", {
    p_user: user.id, p_provider: "google_play", p_product: productId, p_token: purchaseToken,
    p_raw: { ...p, test: p.purchaseType === 0 },
  });
  if (error) throw new Error(error.message);
  if (!data?.ok) throw new HttpError(400, data?.error ?? "Could not record the purchase");

  if (p.consumptionState === 0) {
    const c = await fetch(`${base}:consume`, { method: "POST", headers: { Authorization: `Bearer ${token}` } });
    if (!c.ok) console.error("consume failed", c.status, await c.text()); // coins are already safe; the app retries consume
  }
  const { data: w } = await adminClient().from("wallets").select("coins").eq("user_id", user.id).single();
  return json({ ok: true, already: !!data.already, coins: w?.coins });
});
