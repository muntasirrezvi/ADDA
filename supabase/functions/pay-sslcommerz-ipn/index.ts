// Receives SSLCommerz callbacks. Deploy with --no-verify-jwt (SSLCommerz cannot send a Supabase token).
//  ?r=ipn                    server-to-server notification
//  ?r=success|fail|cancel    the customer's browser coming back from the payment page
// Coins are added only after SSLCommerz's validation API confirms the payment and the
// amount, currency and transaction id match what we stored. Calling it twice is safe.
import { adminClient, env, sslBase } from "../_shared/util.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function validate(valId: string) {
  const q = new URLSearchParams({
    val_id: valId,
    store_id: env("SSLCOMMERZ_STORE_ID"),
    store_passwd: env("SSLCOMMERZ_STORE_PASSWORD"),
    format: "json",
    v: "1",
  });
  const res = await fetch(`${sslBase()}/validator/api/validationserverAPI.php?${q}`);
  return await res.json().catch(() => ({ status: "INVALID_RESPONSE" }));
}

type Outcome = "paid" | "failed" | "cancelled" | "review" | "pending";

async function settle(fields: Record<string, string>): Promise<Outcome> {
  const db = adminClient();
  const tranId = fields.tran_id ?? "";
  if (!UUID.test(tranId)) return "failed";
  const status = (fields.status ?? "").toUpperCase();

  if (status === "FAILED" || status === "CANCELLED" || status === "EXPIRED" || status === "UNATTEMPTED") {
    // only a validated result can credit coins, but anyone could post a failure: only mark pending payments
    await db.rpc("fail_payment", { p_id: tranId, p_status: status === "CANCELLED" ? "cancelled" : "failed", p_raw: fields });
    return status === "CANCELLED" ? "cancelled" : "failed";
  }
  if (!fields.val_id) return "pending";

  const v = await validate(fields.val_id);
  if (!["VALID", "VALIDATED"].includes(v.status) || v.tran_id !== tranId) return "failed";
  if (String(v.risk_level) === "1") {
    // SSLCommerz marks the card as high risk: hold for manual review in the admin panel
    await db.from("payments").update({ raw: { ...v, review: "high_risk" } }).eq("id", tranId).eq("status", "pending");
    return "review";
  }
  // currency_type / currency_amount are what the customer was charged in our currency
  const amount = Number(v.currency_amount ?? v.amount);
  const currency = String(v.currency_type ?? v.currency);
  const { data, error } = await db.rpc("complete_payment", {
    p_id: tranId, p_ref: v.bank_tran_id || v.val_id, p_raw: v, p_amount: amount, p_currency: currency,
  });
  if (error) { console.error(error); return "pending"; }
  return data?.ok ? "paid" : "failed";
}

function page(outcome: Outcome): Response {
  const back = env("APP_RETURN_URL", false) || "adda://wallet";
  const text: Record<Outcome, [string, string]> = {
    paid: ["Payment successful", "Your coins are in your wallet."],
    pending: ["Payment processing", "We will add your coins as soon as the payment is confirmed."],
    review: ["Payment under review", "Our team will confirm this payment shortly."],
    cancelled: ["Payment cancelled", "No money was taken."],
    failed: ["Payment failed", "No coins were added. If money was taken it will be refunded by your bank or wallet."],
  };
  const [title, body] = text[outcome];
  const url = `${back}?payment=${outcome}`;
  const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title><meta http-equiv="refresh" content="2;url=${url}">
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0c0a09;color:#f4ede1;font:16px system-ui,sans-serif;text-align:center}
h1{font-size:22px;color:${outcome === "paid" ? "#d8b77a" : outcome === "failed" ? "#c9506c" : "#f4ede1"}}a{color:#d8b77a}</style></head>
<body><main><h1>${title}</h1><p>${body}</p><p><a href="${url}">Back to Adda</a></p></main></body></html>`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}

Deno.serve(async (req) => {
  const r = new URL(req.url).searchParams.get("r") ?? "ipn";
  let fields: Record<string, string> = {};
  if (req.method === "POST") {
    const form = await req.formData().catch(() => null);
    if (form) fields = Object.fromEntries([...form.entries()].map(([k, v]) => [k, String(v)]));
  } else {
    fields = Object.fromEntries(new URL(req.url).searchParams);
  }

  let outcome: Outcome = "pending";
  try {
    outcome = await settle(fields);
  } catch (e) {
    console.error(e);
  }
  if (r === "ipn") return new Response(outcome, { status: 200 });
  if (r === "cancel" && outcome === "pending") outcome = "cancelled";
  return page(outcome);
});
