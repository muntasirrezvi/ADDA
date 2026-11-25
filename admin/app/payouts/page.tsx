"use client";
import { useState } from "react";
import { fmt, money, rpc, supabase, when } from "@/lib/supabase";
import { useMe, useRun } from "@/components/Shell";
import { Badge, Empty, Loading, Page, useAsync } from "@/components/ui";

type P = { id: number; diamonds: number; amount_usd: number; method: string; account: string; status: string; created_at: string; user: { username: string; public_id: number } | null };

export default function Payouts() {
  const run = useRun();
  const me = useMe();
  const [status, setStatus] = useState("pending");
  const { data, loading, err, reload } = useAsync(async () => {
    const { data, error } = await supabase.from("payouts").select("*, user:profiles!payouts_user_id_fkey(username, public_id)").eq("status", status).order("id").limit(200);
    if (error) throw error;
    return data as unknown as P[];
  }, [status]);
  const set = (id: number, s: string) => run(async () => { await rpc("admin_process_payout", { p_id: id, p_status: s }); reload(); }, `Payout ${s}`);
  return (
    <Page title="Host payouts" sub="Send the money yourself (bKash, Nagad, bank, Payoneer), then mark it paid. Rejecting returns the diamonds to the host.">
      <div className="tabs">{["pending", "approved", "paid", "rejected"].map((s) => <button key={s} className={"sm" + (s === status ? " on" : "")} onClick={() => setStatus(s)}>{s}</button>)}</div>
      {loading || err ? <Loading err={err} /> : !data?.length ? <Empty /> : (
        <div className="card tw"><table>
          <thead><tr><th>Requested</th><th>Host</th><th>Diamonds</th><th>Amount</th><th>Send to</th><th>Status</th><th /></tr></thead>
          <tbody>{data.map((p) => (
            <tr key={p.id}><td className="sm">{when(p.created_at)}</td><td>{p.user?.username} <span className="muted sm">{p.user?.public_id}</span></td>
              <td>{fmt(p.diamonds)}</td><td><b>{money(p.amount_usd)}</b></td><td className="sm">{p.method}: {p.account}</td><td><Badge>{p.status}</Badge></td>
              <td className="act">{me?.role === "admin" && ["pending", "approved"].includes(p.status) && <>
                {p.status === "pending" && <button className="sm" onClick={() => set(p.id, "approved")}>Approve</button>}
                <button className="sm green" onClick={() => set(p.id, "paid")}>Mark paid</button>
                <button className="sm ghost danger" onClick={() => set(p.id, "rejected")}>Reject</button></>}</td></tr>
          ))}</tbody>
        </table></div>
      )}
    </Page>
  );
}
