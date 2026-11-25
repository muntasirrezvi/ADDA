"use client";
import { useState } from "react";
import { fmt, rpc, supabase, when } from "@/lib/supabase";
import { useMe, useRun } from "@/components/Shell";
import { Badge, Empty, Loading, Modal, Page, useAsync } from "@/components/ui";

type P = {
  id: string; provider: string; pack_id: string; amount: number; currency: string; coins: number; status: string; provider_ref: string | null;
  raw: Record<string, unknown> | null; created_at: string; paid_at: string | null; user: { username: string; public_id: number } | null;
};
const TONE: Record<string, "green" | "red" | "dim" | "gold" | ""> = { paid: "green", failed: "red", cancelled: "dim", pending: "gold", refunded: "" };

export default function Payments() {
  const run = useRun();
  const me = useMe();
  const [status, setStatus] = useState("all");
  const [provider, setProvider] = useState("all");
  const [sel, setSel] = useState<P | null>(null);
  const { data, loading, err, reload } = useAsync(async () => {
    let q = supabase.from("payments").select("*, user:profiles!payments_user_id_fkey(username, public_id)").order("created_at", { ascending: false }).limit(200);
    if (status !== "all") q = q.eq("status", status);
    if (provider !== "all") q = q.eq("provider", provider);
    const { data, error } = await q;
    if (error) throw error;
    return data as unknown as P[];
  }, [status, provider]);

  return (
    <Page title="Payments" sub="Every top-up through SSLCommerz (bKash, Nagad, cards) and Google Play. Coins are only added after the gateway confirms.">
      <div className="row mb">
        <select value={status} onChange={(e) => setStatus(e.target.value)} style={{ maxWidth: 180 }}>
          {["all", "paid", "pending", "failed", "cancelled", "refunded"].map((s) => <option key={s}>{s}</option>)}
        </select>
        <select value={provider} onChange={(e) => setProvider(e.target.value)} style={{ maxWidth: 180 }}>
          {["all", "sslcommerz", "google_play"].map((s) => <option key={s}>{s}</option>)}
        </select>
      </div>
      {loading || err ? <Loading err={err} /> : !data?.length ? <Empty>No payments yet</Empty> : (
        <div className="card tw">
          <table>
            <thead><tr><th>When</th><th>User</th><th>Method</th><th>Amount</th><th>Coins</th><th>Status</th><th /></tr></thead>
            <tbody>{data.map((p) => (
              <tr key={p.id}>
                <td className="sm">{when(p.created_at)}</td>
                <td>{p.user?.username}<small className="muted">{p.user?.public_id}</small></td>
                <td className="sm">{p.provider === "sslcommerz" ? String(p.raw?.card_issuer || p.raw?.card_type || "SSLCommerz") : "Google Play"}</td>
                <td>{fmt(p.amount)} {p.currency}</td><td>{fmt(p.coins)}</td>
                <td><Badge tone={TONE[p.status]}>{p.status}</Badge>{p.raw?.review === "high_risk" && p.status === "pending" && <Badge tone="red">review</Badge>}</td>
                <td className="act"><button className="sm" onClick={() => setSel(p)}>Details</button></td>
              </tr>
            ))}</tbody>
          </table>
        </div>
      )}
      {sel && (
        <Modal title="Payment" onClose={() => setSel(null)} wide>
          <dl className="kv mb">
            <dt>ID</dt><dd>{sel.id}</dd><dt>Gateway ref</dt><dd>{sel.provider_ref ?? "—"}</dd>
            <dt>Created</dt><dd>{when(sel.created_at)}</dd><dt>Paid</dt><dd>{when(sel.paid_at)}</dd>
          </dl>
          <pre className="card sm" style={{ overflow: "auto", maxHeight: 300, margin: 0 }}>{JSON.stringify(sel.raw, null, 2)}</pre>
          {me?.role === "admin" && (
            <div className="row end" style={{ marginTop: 14 }}>
              {sel.status === "pending" && sel.raw?.review === "high_risk" && (
                <button className="green" onClick={() => run(async () => { await rpc("admin_approve_payment", { p_id: sel.id }); setSel(null); reload(); }, "Approved, coins added")}>Approve and add coins</button>
              )}
              {sel.status === "paid" && (
                <button className="red" onClick={() => { const r = prompt("Reason for refund (coins will be taken back)"); if (r) run(async () => { await rpc("admin_refund_payment", { p_id: sel.id, p_reason: r }); setSel(null); reload(); }, "Marked refunded"); }}>Mark refunded</button>
              )}
            </div>
          )}
        </Modal>
      )}
    </Page>
  );
}
