"use client";
import { useState } from "react";
import Link from "next/link";
import { fmt, rpc, supabase, when } from "@/lib/supabase";
import { useMe, useRun } from "@/components/Shell";
import { Badge, Empty, Loading, Page, useAsync } from "@/components/ui";

type T = {
  id: number; coins: number; diamonds: number; fee_coins: number; kind: string; note: string | null; created_at: string; from_id: string | null; to_id: string | null;
  from: { username: string; public_id: number } | null; to: { username: string; public_id: number } | null;
};
const KINDS: [string, string][] = [["all", "All"], ["admin", "From admin"], ["agent", "From agents"], ["user", "Between users"], ["stock", "Store refills"]];

export default function Transfers() {
  const me = useMe();
  const run = useRun();
  const [kind, setKind] = useState("all");
  const [to, setTo] = useState("");
  const [coins, setCoins] = useState("");
  const [dia, setDia] = useState("");
  const [note, setNote] = useState("");
  const { data, loading, err, reload } = useAsync(async () => {
    let q = supabase.from("coin_transfers").select("*, from:profiles!coin_transfers_from_id_fkey(username, public_id), to:profiles!coin_transfers_to_id_fkey(username, public_id)").order("id", { ascending: false }).limit(300);
    if (kind !== "all") q = q.eq("kind", kind);
    const { data, error } = await q;
    if (error) throw error;
    return data as unknown as T[];
  }, [kind]);
  const send = async () => {
    const u = await rpc<{ username: string } | null>("find_user", { p_public: Number(to) });
    if (!u) throw new Error("No user with that ID");
    if (!confirm(`Send ${fmt(Number(coins || 0))} coins and ${fmt(Number(dia || 0))} diamonds to ${u.username}?`)) return;
    await rpc("store_transfer", { p_to_public: Number(to), p_coins: Number(coins || 0), p_diamonds: Number(dia || 0), p_note: note });
    setCoins(""); setDia(""); setNote(""); reload();
  };
  const totals = (data ?? []).reduce((a, t) => ({ c: a.c + Number(t.coins), d: a.d + Number(t.diamonds) }), { c: 0, d: 0 });
  return (
    <Page title="Coin & diamond transfers" sub="Every coin and diamond that moved by hand: your grants, agent sends, store refills and gifts between users.">
      {me?.role === "admin" && (
        <div className="card mb">
          <h3 className="mb">Send from the admin store (unlimited)</h3>
          <div className="row" style={{ flexWrap: "wrap" }}>
            <input type="number" placeholder="User ID" value={to} onChange={(e) => setTo(e.target.value)} style={{ flex: 1, minWidth: 120 }} />
            <input type="number" placeholder="Coins" value={coins} onChange={(e) => setCoins(e.target.value)} style={{ flex: 1, minWidth: 120 }} />
            <input type="number" placeholder="Diamonds" value={dia} onChange={(e) => setDia(e.target.value)} style={{ flex: 1, minWidth: 120 }} />
            <input placeholder="Note (optional)" value={note} onChange={(e) => setNote(e.target.value)} style={{ flex: 2, minWidth: 160 }} />
            <button className="gold" onClick={() => run(send, "Sent")}>Send</button>
          </div>
        </div>
      )}
      <div className="tabs">{KINDS.map(([k, l]) => <button key={k} className={"sm" + (k === kind ? " on" : "")} onClick={() => setKind(k)}>{l}</button>)}</div>
      {data && data.length > 0 && <p className="muted mb">{data.length} transfers · {fmt(totals.c)} coins · {fmt(totals.d)} diamonds</p>}
      {loading || err ? <Loading err={err} /> : !data?.length ? <Empty /> : (
        <div className="card tw"><table>
          <thead><tr><th>When</th><th>Type</th><th>From</th><th>To</th><th>Coins</th><th>Diamonds</th><th>Note</th></tr></thead>
          <tbody>{data.map((t) => (
            <tr key={t.id}>
              <td className="sm">{when(t.created_at)}</td>
              <td><Badge tone={t.kind === "admin" ? "gold" : t.kind === "agent" ? "green" : t.kind === "stock" ? "dim" : ""}>{KINDS.find((k) => k[0] === t.kind)?.[1] ?? t.kind}</Badge></td>
              <td>{t.from_id ? <Link href={`/users/view/?id=${t.from_id}`}>{t.from?.username}</Link> : "—"} <span className="muted sm">{t.from?.public_id}</span></td>
              <td>{t.to_id ? <Link href={`/users/view/?id=${t.to_id}`}>{t.to?.username}</Link> : "—"} <span className="muted sm">{t.to?.public_id}</span></td>
              <td style={{ color: t.coins < 0 ? "#f08aa0" : undefined }}>{t.coins ? fmt(t.coins) : ""}{t.fee_coins ? <small className="muted">fee {fmt(t.fee_coins)}</small> : null}</td>
              <td>{t.diamonds ? fmt(t.diamonds) : ""}</td>
              <td className="sm muted">{t.note}</td>
            </tr>
          ))}</tbody>
        </table></div>
      )}
    </Page>
  );
}
