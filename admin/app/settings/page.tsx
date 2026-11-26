"use client";
import { useState } from "react";
import { rpc, supabase } from "@/lib/supabase";
import { useMe, useRun } from "@/components/Shell";
import { Field, Loading, Page, useAsync } from "@/components/ui";

const KNOWN: [string, string, string][] = [
  ["pay_agent_enabled", "Agent top-ups (bKash, Nagad, Rocket)", "true or false"],
  ["pay_sslcommerz_enabled", "SSLCommerz card/bKash checkout", "true once your SSLCommerz merchant account is live"],
  ["pay_play_enabled", "Google Play in-app purchase", "true once products exist in Play Console"],
  ["topup_order_minutes", "Minutes a user has to pay an agent", ""],
  ["privacy_url", "Privacy policy link", 'JSON text, e.g. "https://adda.app/privacy"'],
  ["terms_url", "Terms of service link", 'JSON text, e.g. "https://adda.app/terms"'],
  ["coins_per_usd", "Coins per US dollar", "Shown prices and agent sales use this. Default 500000."],
  ["usd_to_bdt", "Taka per dollar", "Used when you set BDT prices for packs."],
  ["welcome_bonus", "Welcome bonus (coins)", "Given to every new account."],
  ["diamond_rate", "Diamonds per coin gifted", "Hosts receive this many diamonds per coin. Keep diamond_rate × diamond_to_coins below 1."],
  ["diamond_to_coins", "Coins per diamond (exchange)", ""],
  ["diamonds_per_usd", "Diamonds per $1 payout", ""],
  ["min_payout_diamonds", "Minimum withdrawal (diamonds)", "625000 diamonds = $1 by default."],
  ["withdraw_enabled", "Withdrawals open", "true or false. false hides the button for everyone."],
  ["withdraw_require_verified", "Withdraw: ID check required", "true = people must pass identity verification first."],
  ["withdraw_require_phone", "Withdraw: phone number required", "true = people must sign in with a verified phone number."],
  ["withdraw_min_account_days", "Withdraw: minimum account age (days)", "Blocks brand-new accounts from cashing out."],
  ["withdraw_cooldown_hours", "Withdraw: hours between requests", "0 = no waiting time."],
  ["withdraw_daily_max_diamonds", "Withdraw: daily maximum (diamonds)", ""],
  ["withdraw_fee_pct", "Withdraw: fee (%)", "Taken from the payout, e.g. 5 = 5%."],
  ["withdraw_methods", "Withdraw: payment methods", 'JSON list from "bkash","nagad","rocket","bank","payoneer"'],
  ["coins_per_diamond", "Exchange: coins for 1 diamond", "Default 2500000. Also sets the price of custom diamond purchases."],
  ["coin_exchange_enabled", "Exchange: coins → diamonds on", "true or false"],
  ["diamond_to_coins", "Exchange: coins for 1 diamond when selling diamonds", "Diamonds → coins rate. Default 1."],
  ["transfer_enabled", "Transfers between users on", "true or false"],
  ["transfer_diamonds_enabled", "Users can send diamonds", "true or false"],
  ["transfer_min_coins", "Transfer: minimum coins", ""],
  ["transfer_daily_max_coins", "Transfer: daily max coins per person", ""],
  ["transfer_daily_max_diamonds", "Transfer: daily max diamonds per person", ""],
  ["transfer_fee_pct", "Transfer: fee on coins (%)", "0 = free"],
  ["custom_topup_enabled", "Custom amount purchases on", "true or false. Price uses the per-coin rate of the biggest package that fits."],
  ["custom_diamonds_enabled", "Users can buy diamonds", "true or false. Agents need diamond stock (Coin agents page)."],
  ["custom_min_coins", "Custom amount: minimum coins", ""],
  ["online_window_seconds", "Online status window (seconds)", "Someone shows Online if they were active within this time. Default 120."],
  ["checkin_base", "Daily reward: day 1 coins", "Default 10000."],
  ["checkin_growth", "Daily reward: daily increase", "0.2 = each day pays 20% more than the day before."],
  ["checkin_cycle", "Daily reward: days in a cycle", "After the last day it starts again at day 1. Default 7."],
  ["ai_avatar_enabled", "AI avatars on", "true or false. Needs CF_ACCOUNT_ID and CF_API_TOKEN secrets in Supabase."],
  ["ai_avatar_daily_limit", "AI avatars per person per day", "Cloudflare's free plan allows roughly a few hundred images a day in total."],
  ["creator_share", "Reel creator share", "0.8 = creator keeps 80% of donations."],
  ["min_bet", "Minimum game bet (coins)", ""],
  ["daily_game_loss_cap", "Daily game loss limit (coins)", ""],
  ["blocked_words", "Blocked chat words", 'JSON list, e.g. ["word1","word2"]. Matching words are masked with ***.'],
  ["support_contact", "Support contact", 'JSON text, e.g. "support@adda.app"'],
  ["maintenance", "Maintenance mode", "true shows a maintenance screen in the app."],
  ["min_app_version", "Minimum app version", 'Older apps are asked to update. JSON text, e.g. "1.0.0"'],
];

export default function Settings() {
  const run = useRun();
  const me = useMe();
  const [vals, setVals] = useState<Record<string, string>>({});
  const { loading, err, data } = useAsync(async () => {
    const { data, error } = await supabase.from("app_settings").select("key, value");
    if (error) throw error;
    const v: Record<string, string> = {};
    for (const r of data) v[r.key] = JSON.stringify(r.value);
    setVals(v);
    return v;
  });
  const save = (k: string) => run(async () => {
    let parsed: unknown;
    try { parsed = JSON.parse(vals[k]); } catch { throw new Error(`${k}: not valid JSON (text needs "quotes")`); }
    await rpc("admin_set_setting", { p_key: k, p_value: parsed });
  }, "Saved");
  if (loading || err || !data) return <Page title="Settings"><Loading err={err} /></Page>;
  const extra = Object.keys(vals).filter((k) => !KNOWN.some(([x]) => x === k) && k !== "home_layout");
  return (
    <Page title="Settings" sub={me?.role === "admin" ? "Changes apply to the app immediately." : "Only admins can change settings."}>
      <div className="grid g2">
        {[...KNOWN, ...extra.map((k) => [k, k, ""] as [string, string, string])].map(([k, label, hint]) => (
          <div key={k} className="card">
            <Field label={label} hint={hint}>
              <div className="row"><input value={vals[k] ?? ""} onChange={(e) => setVals({ ...vals, [k]: e.target.value })} style={{ flex: 1 }} />
                <button className="sm" disabled={me?.role !== "admin"} onClick={() => save(k)}>Save</button></div>
            </Field>
          </div>
        ))}
      </div>
    </Page>
  );
}
