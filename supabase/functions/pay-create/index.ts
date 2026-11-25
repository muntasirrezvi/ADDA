// POST { pack: "p10" }  ->  { url, paymentId, amount, currency }
// Starts a SSLCommerz checkout (bKash, Nagad, Rocket, Visa, Mastercard, Amex, net banking).
// The app opens `url` in a web view; SSLCommerz then calls pay-sslcommerz-ipn.
import { adminClient, env, HttpError, json, requireUser, serve, sslBase, userClient } from "../_shared/util.ts";

serve(async (req) => {
  const user = await requireUser(req);
  const { pack } = await req.json().catch(() => ({}));
  if (!pack) throw new HttpError(400, "Choose a coin pack");

  // create_payment runs as the user, so the price and discount are computed in the database
  const { data: pay, error } = await userClient(req).rpc("create_payment", { p_pack: pack, p_provider: "sslcommerz" });
  if (error) throw new HttpError(400, error.message);

  const db = adminClient();
  const [{ data: prof }, { data: priv }] = await Promise.all([
    db.from("profiles").select("username, country").eq("id", user.id).single(),
    db.from("profile_private").select("email, phone").eq("user_id", user.id).single(),
  ]);

  const ipn = `${env("SUPABASE_URL")}/functions/v1/pay-sslcommerz-ipn`;
  const form = new URLSearchParams({
    store_id: env("SSLCOMMERZ_STORE_ID"),
    store_passwd: env("SSLCOMMERZ_STORE_PASSWORD"),
    total_amount: Number(pay.amount).toFixed(2),
    currency: pay.currency,
    tran_id: pay.id,
    product_name: `${Number(pay.coins).toLocaleString("en-US")} Adda coins`,
    product_category: "Digital goods",
    product_profile: "non-physical-goods",
    success_url: `${ipn}?r=success`,
    fail_url: `${ipn}?r=fail`,
    cancel_url: `${ipn}?r=cancel`,
    ipn_url: `${ipn}?r=ipn`,
    cus_name: prof?.username ?? "Adda user",
    cus_email: priv?.email || "noreply@adda.app",
    cus_phone: priv?.phone || "01700000000",
    cus_add1: "N/A",
    cus_city: "Dhaka",
    cus_postcode: "1000",
    cus_country: prof?.country || "Bangladesh",
    shipping_method: "NO",
    num_of_item: "1",
    value_a: user.id,
  });

  const res = await fetch(`${sslBase()}/gwprocess/v4/api.php`, { method: "POST", body: form });
  const body = await res.json().catch(() => ({}));
  if (body.status !== "SUCCESS" || !body.GatewayPageURL) {
    await db.rpc("fail_payment", { p_id: pay.id, p_status: "failed", p_raw: body });
    throw new HttpError(502, body.failedreason || "Payment gateway is unavailable, try again");
  }
  return json({ url: body.GatewayPageURL, paymentId: pay.id, amount: pay.amount, currency: pay.currency });
});
