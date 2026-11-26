"use client";
import { useState } from "react";
import Link from "next/link";
import { fmt, money, rpc, supabase, when } from "@/lib/supabase";
import { useMe, useRun } from "@/components/Shell";
import { Badge, Empty, Field, Loading, Modal, Page, useAsync } from "@/components/ui";

type P = {
  id: number; user_id: string; diamonds: number; amount_usd: number; amount_bdt: number | null; fee_usd: number; method: string; account: string;
  holder_name: string | null; note: string | null; paid_ref: string | null; status: string; created_at: string; processed_at: string | null;
  user: { username: string; public_id: number; verified: boolean } | null;
};
const METHOD: Record<string, string> = { bkash: "bKash", nagad: "Nagad", rocket: "Rocket", bank: "Bank", payoneer: "Payoneer" };

export default function Payouts() {
  const me = useMe();
  const [status, setStatus] = useState("pending");
  const [act, setAct] = useState<{ p: P; to: string } | null>(null);
  const { data, loading, err, reload } = useAsync(async () => {
    const { data, error } = await supabase.from("payouts").select("*, user:profiles!payouts_user_id_fkey(username, public_id, verified)").eq("status", status).order("id", { ascending: status === "pending" }).limit(200);
    if (error) throw error;
    return data as unknown as P[];
  }, [status]);
  const total = (data ?? []).reduce((a, p) => a + Number(p.amount_bdt ?? 0), 0);
  return (
    <Page title="Withdrawals" sub="People cash out diamonds they earned from gifts. Send the money yourself (bKash, Nagad, Rocket, bank), then mark it paid with the transaction ID. Rejecting returns the diamonds. Rules are under Settings → withdraw_*.">
      <div className="tabs">{["pending", "approved", "paid", "rejected"].map((s) => <button key={s} className={"sm" + (s === status ? " on" : "")} onClick={() => setStatus(s)}>{s}</button>)}</div>
      {data && data.length > 0 && <p className="muted mb">{data.length} requests · ৳{fmt(Math.round(total))} total</p>}
      {loading || err ? <Loading err={err} /> : !data?.length ? <Empty /> : (
        <div className="card tw"><table>
          <thead><tr><th>Requested</th><th>Person</th><th>Diamonds</th><th>Pay</th><th>Send to</th><th>Status</th><th /></tr></thead>
          <tbody>{data.map((p) => (
            <tr key={p.id}>
              <td className="sm">{when(p.created_at)}</td>
              <td><Link href={`/users/view/?id=${p.user_id}`}><b style={{ color: "var(--gold)" }}>{p.user?.username}</b></Link> <span className="muted sm">{p.user?.public_id}</span>{p.user?.verified && <small className="muted">ID verified</small>}</td>
              <td>{fmt(p.diamonds)}</td>
              <td><b>{p.amount_bdt != null ? `৳${fmt(Math.round(p.amount_bdt))}` : ""}</b><small className="muted">{money(p.amount_usd)}{p.fee_usd > 0 ? ` · fee ${money(p.fee_usd)}` : ""}</small></td>
              <td className="sm"><b>{METHOD[p.method] ?? p.method}</b> {p.account}{p.holder_name && <small className="muted">{p.holder_name}</small>}</td>
              <td><Badge tone={p.status === "paid" ? "green" : p.status === "rejected" ? "red" : ""}>{p.status}</Badge>{p.paid_ref && <small className="muted">ref {p.paid_ref}</small>}{p.note && <small className="muted">{p.note}</small>}</td>
              <td className="act">{me?.role === "admin" && ["pending", "approved"].includes(p.status) && <>
                {p.status === "pending" && <button className="sm" onClick={() => setAct({ p, to: "approved" })}>Approve</button>}
                <button className="sm green" onClick={() => setAct({ p, to: "paid" })}>Mark paid</button>
                <button className="sm ghost danger" onClick={() => setAct({ p, to: "rejected" })}>Reject</button></>}</td>
            </tr>
          ))}</tbody>
        </table></div>
      )}
      {act && <ActModal p={act.p} to={act.to} onClose={() => { setAct(null); reload(); }} />}
    </Page>
  );
}

function ActModal({ p, to, onClose }: { p: P; to: string; onClose: () => void }) {
  const run = useRun();
  const [ref, setRef] = useState("");
  const [note, setNote] = useState("");
  const label = to === "paid" ? "Mark as paid" : to === "rejected" ? "Reject and return diamonds" : "Approve";
  return (
    <Modal title={`${label} · ${p.user?.username}`} onClose={onClose}>
      <div className="form">
        <p>{fmt(p.diamonds)} diamonds → <b>{p.amount_bdt != null ? `৳${fmt(Math.round(p.amount_bdt))}` : money(p.amount_usd)}</b> to {METHOD[p.method] ?? p.method} <b>{p.account}</b>{p.holder_name ? ` (${p.holder_name})` : ""}</p>
        {to === "paid" && <Field label="Transaction ID" hint="The bKash/Nagad/bank reference. The person sees it in their history."><input value={ref} onChange={(e) => setRef(e.target.value)} /></Field>}
        <Field label={to === "rejected" ? "Reason (shown to the person)" : "Note (optional)"}><input value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        <div className="row end">
          <button className="ghost" onClick={onClose}>Cancel</button>
          <button className={to === "rejected" ? "red" : "gold"} onClick={() => run(async () => { await rpc("admin_update_payout", { p_id: p.id, p_status: to, p_note: note, p_ref: ref }); onClose(); }, "Saved")}>{label}</button>
        </div>
      </div>
    </Modal>
  );
}
