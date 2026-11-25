"use client";
import { useState } from "react";
import { fmt, supabase, when } from "@/lib/supabase";
import { Empty, Loading, Page, useAsync } from "@/components/ui";

const KINDS = ["all", "topup", "agent_buy", "gift_sent", "gift_received", "donation_sent", "donation_received", "reward", "exchange", "payout", "theme", "admin_adjust", "refund"];

export default function Ledger() {
  const [kind, setKind] = useState("all");
  const { data, loading, err } = useAsync(async () => {
    let q = supabase.from("transactions").select("id, kind, coins, diamonds, ref, created_at, user:profiles!transactions_user_id_fkey(username, public_id)").order("id", { ascending: false }).limit(300);
    if (kind !== "all") q = q.eq("kind", kind);
    const { data, error } = await q;
    if (error) throw error;
    return data as unknown as { id: number; kind: string; coins: number; diamonds: number; ref: string; created_at: string; user: { username: string; public_id: number } | null }[];
  }, [kind]);
  return (
    <Page title="Coin ledger" sub="Every coin and diamond movement, newest first. Balances can only change through these entries.">
      <select className="mb" value={kind} onChange={(e) => setKind(e.target.value)} style={{ maxWidth: 220 }}>{KINDS.map((k) => <option key={k}>{k}</option>)}</select>
      {loading || err ? <Loading err={err} /> : !data?.length ? <Empty /> : (
        <div className="card tw"><table>
          <thead><tr><th>#</th><th>When</th><th>User</th><th>Type</th><th>Coins</th><th>Diamonds</th><th>Ref</th></tr></thead>
          <tbody>{data.map((t) => (
            <tr key={t.id}><td className="muted">{t.id}</td><td className="sm">{when(t.created_at)}</td><td>{t.user?.username} <span className="muted sm">{t.user?.public_id}</span></td>
              <td className="sm">{t.kind.replace(/_/g, " ")}</td>
              <td style={{ color: t.coins < 0 ? "#f08aa0" : t.coins > 0 ? "#6fd6b5" : undefined }}>{t.coins ? fmt(t.coins) : ""}</td>
              <td>{t.diamonds ? fmt(t.diamonds) : ""}</td><td className="sm muted">{t.ref}</td></tr>
          ))}</tbody>
        </table></div>
      )}
    </Page>
  );
}
