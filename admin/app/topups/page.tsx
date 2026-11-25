"use client";
// The top-up desk. Agents see orders assigned to them; the owner sees every order and can reassign.
import { useEffect, useRef, useState } from "react";
import { fmt, rpc, supabase, when } from "@/lib/supabase";
import { useMe, useRun, useToast } from "@/components/Shell";
import { Badge, Empty, Loading, Modal, Page, useAsync } from "@/components/ui";

type O = {
  id: string; user_id: string; pack_id: string; coins: number; amount: number; currency: string; method: string; pay_to: string; agent_id: string | null;
  status: string; sender_number: string | null; trx_id: string | null; proof_path: string | null; note: string | null;
  created_at: string; submitted_at: string | null; handled_at: string | null;
  user: { username: string; public_id: number } | null; agent: { username: string } | null;
};
type Agent = { agent_id: string; username: string; display_name: string | null; coins: number; accepts_topups: boolean; waiting: number; approved_today: number; coins_today: number };

const TABS: [string, string][] = [["submitted", "To check"], ["awaiting_payment", "Waiting for payment"], ["approved", "Approved"], ["rejected", "Rejected"], ["expired", "Expired"]];
const TONE: Record<string, "gold" | "green" | "red" | "dim" | ""> = { submitted: "gold", approved: "green", rejected: "red", expired: "dim", cancelled: "dim", awaiting_payment: "" };
const METHOD: Record<string, string> = { bkash: "bKash", nagad: "Nagad", rocket: "Rocket", upay: "Upay", bank: "Bank", usdt: "USDT" };

export default function Topups() {
  const me = useMe();
  const run = useRun();
  const toast = useToast();
  const owner = me?.role === "admin";
  const [tab, setTab] = useState("submitted");
  const [sel, setSel] = useState<O | null>(null);
  const [agentFilter, setAgentFilter] = useState("all");
  const audio = useRef<AudioContext | null>(null);
  const ding = () => {
    try {
      const ctx = (audio.current ??= new AudioContext());
      [880, 1320].forEach((f, i) => {
        const o = ctx.createOscillator(); const g = ctx.createGain();
        o.frequency.value = f; o.connect(g); g.connect(ctx.destination);
        const t = ctx.currentTime + i * 0.16;
        g.gain.setValueAtTime(0.15, t); g.gain.exponentialRampToValueAtTime(0.001, t + 0.15);
        o.start(t); o.stop(t + 0.16);
      });
    } catch { /* sound is optional */ }
  };

  const agents = useAsync(() => rpc<Agent[]>("agent_overview"));
  const { data, loading, err, reload } = useAsync(async () => {
    let q = supabase.from("topup_orders")
      .select("*, user:profiles!topup_orders_user_id_fkey(username, public_id), agent:profiles!topup_orders_agent_id_fkey(username)")
      .eq("status", tab).order(tab === "submitted" ? "submitted_at" : "created_at", { ascending: tab === "submitted" }).limit(200);
    if (me?.role === "agent") q = q.eq("agent_id", me.id);
    else if (agentFilter !== "all") q = q.eq("agent_id", agentFilter);
    const { data, error } = await q;
    if (error) throw error;
    return data as unknown as O[];
  }, [tab, agentFilter, me?.id]);

  // live: new proofs arrive without refreshing, with a sound
  useEffect(() => {
    const ch = supabase.channel("topups")
      .on("postgres_changes", { event: "*", schema: "public", table: "topup_orders" }, (p) => {
        const row = p.new as Partial<O>;
        if (p.eventType === "UPDATE" && row.status === "submitted" && (owner || row.agent_id === me?.id)) {
          toast(`New payment to check: ${fmt(row.amount)} ${row.currency} by ${METHOD[row.method ?? ""] ?? row.method}`);
          ding();
        }
        reload(); agents.reload();
      }).subscribe();
    return () => { supabase.removeChannel(ch); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [me?.id, owner]);

  const mine = agents.data?.find((a) => a.agent_id === me?.id);

  return (
    <Page title="Top-up orders" sub={owner
      ? "Users pay an agent's bKash/Nagad number and enter the TrxID here. Check the statement, then approve: coins move from that agent's stock to the user."
      : "Check each payment in your bKash/Nagad statement, then approve. Coins come from your stock."}>
      <div className="grid g4 mb">
        {owner ? agents.data?.filter((a) => a.accepts_topups).map((a) => (
          <div key={a.agent_id} className="card stat">
            <div className="k">{a.display_name || a.username}</div><div className="v">{fmt(a.coins)}</div>
            <small className="muted">stock · {a.waiting} to check · {fmt(a.coins_today)} sent today</small>
          </div>
        )) : mine && (
          <>
            <div className="card stat"><div className="k">My coin stock</div><div className="v gold">{fmt(mine.coins)}</div></div>
            <div className="card stat"><div className="k">To check</div><div className="v">{fmt(mine.waiting)}</div></div>
            <div className="card stat"><div className="k">Approved today</div><div className="v">{fmt(mine.approved_today)}</div><small className="muted">{fmt(mine.coins_today)} coins</small></div>
          </>
        )}
      </div>
      <div className="row mb">
        <div className="tabs" style={{ margin: 0 }}>{TABS.map(([k, l]) => <button key={k} className={"sm" + (k === tab ? " on" : "")} onClick={() => setTab(k)}>{l}</button>)}</div>
        {owner && (
          <select value={agentFilter} onChange={(e) => setAgentFilter(e.target.value)} style={{ maxWidth: 200, marginLeft: "auto" }}>
            <option value="all">All agents</option>
            {agents.data?.map((a) => <option key={a.agent_id} value={a.agent_id}>{a.display_name || a.username}</option>)}
          </select>
        )}
      </div>
      {loading || err ? <Loading err={err} /> : !data?.length ? <Empty>No orders here</Empty> : (
        <div className="card tw"><table>
          <thead><tr><th>Time</th><th>User</th><th>Pack</th><th>Amount</th><th>Paid to</th><th>From · TrxID</th>{owner && <th>Agent</th>}<th>Status</th><th /></tr></thead>
          <tbody>{data.map((o) => (
            <tr key={o.id}>
              <td className="sm">{when(o.submitted_at ?? o.created_at)}</td>
              <td>{o.user?.username}<small className="muted">{o.user?.public_id}</small></td>
              <td>{fmt(o.coins)}</td>
              <td><b>{fmt(o.amount)} {o.currency}</b></td>
              <td className="sm">{METHOD[o.method] ?? o.method}<br /><span className="muted">{o.pay_to}</span></td>
              <td className="sm">{o.sender_number ?? "—"}<br /><b style={{ letterSpacing: 1 }}>{o.trx_id ?? ""}</b></td>
              {owner && <td className="sm">{o.agent?.username ?? "—"}</td>}
              <td><Badge tone={TONE[o.status]}>{o.status.replace("_", " ")}</Badge></td>
              <td className="act"><button className={"sm" + (o.status === "submitted" ? " gold" : "")} onClick={() => setSel(o)}>{o.status === "submitted" ? "Check" : "Open"}</button></td>
            </tr>
          ))}</tbody>
        </table></div>
      )}
      {sel && <OrderModal o={sel} owner={owner} agents={agents.data ?? []} onClose={() => setSel(null)} onDone={() => { setSel(null); reload(); agents.reload(); }} run={run} />}
    </Page>
  );
}

function OrderModal({ o, owner, agents, onClose, onDone, run }:
  { o: O; owner: boolean; agents: Agent[]; onClose: () => void; onDone: () => void; run: ReturnType<typeof useRun> }) {
  const [proof, setProof] = useState<string | null>(null);
  const [reason, setReason] = useState("");
  const [assign, setAssign] = useState(o.agent_id ?? "");
  useEffect(() => {
    if (!o.proof_path) return;
    supabase.storage.from("payment-proofs").createSignedUrl(o.proof_path, 600).then(({ data }) => setProof(data?.signedUrl ?? null));
  }, [o.proof_path]);
  const open = ["submitted", "awaiting_payment", "expired"].includes(o.status);

  return (
    <Modal title={`${fmt(o.amount)} ${o.currency} · ${METHOD[o.method] ?? o.method}`} onClose={onClose} wide>
      <div className="grid g2">
        <div className="form">
          <dl className="kv">
            <dt>User</dt><dd>{o.user?.username} ({o.user?.public_id})</dd>
            <dt>Coins to send</dt><dd><b>{fmt(o.coins)}</b></dd>
            <dt>Paid to</dt><dd>{o.pay_to}</dd>
            <dt>Paid from</dt><dd>{o.sender_number ?? "—"}</dd>
            <dt>Transaction ID</dt><dd><b style={{ fontSize: 16, letterSpacing: 1 }}>{o.trx_id ?? "—"}</b></dd>
            <dt>Ordered</dt><dd>{when(o.created_at)}</dd><dt>Submitted</dt><dd>{when(o.submitted_at)}</dd>
            {o.note && <><dt>Note</dt><dd>{o.note}</dd></>}
          </dl>
          {open && (
            <div className="card form">
              <p className="sm" style={{ margin: 0 }}>Approve only after you find <b>{fmt(o.amount)} {o.currency}</b> with TrxID <b>{o.trx_id ?? "?"}</b> in the {METHOD[o.method] ?? o.method} statement for {o.pay_to}.</p>
              <button className="green" onClick={() => { if (confirm(`Send ${fmt(o.coins)} coins to ${o.user?.username}?`)) run(async () => { await rpc("approve_topup", { p_order: o.id }); onDone(); }, "Approved, coins sent"); }}>
                Payment received, send {fmt(o.coins)} coins
              </button>
              <div className="row">
                <input placeholder="Reason, e.g. TrxID not found" value={reason} onChange={(e) => setReason(e.target.value)} style={{ flex: 1 }} />
                <button className="red" onClick={() => run(async () => { await rpc("reject_topup", { p_order: o.id, p_reason: reason }); onDone(); }, "Rejected")}>Reject</button>
              </div>
            </div>
          )}
          {owner && open && (
            <div className="row">
              <select value={assign} onChange={(e) => setAssign(e.target.value)} style={{ flex: 1 }}>
                {agents.map((a) => <option key={a.agent_id} value={a.agent_id}>{a.display_name || a.username} · {fmt(a.coins)} stock</option>)}
              </select>
              <button onClick={() => run(async () => { await rpc("admin_assign_topup", { p_order: o.id, p_agent: assign }); onDone(); }, "Reassigned")}>Move to this agent</button>
            </div>
          )}
        </div>
        <div>
          <span className="lbl">Screenshot from the user</span>
          {o.proof_path ? (proof ? <a href={proof} target="_blank" rel="noreferrer"><img src={proof} alt="Payment screenshot" style={{ width: "100%", borderRadius: 12, marginTop: 6 }} /></a> : <Loading />)
            : <Empty>No screenshot</Empty>}
        </div>
      </div>
    </Modal>
  );
}
