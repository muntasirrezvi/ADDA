"use client";
import { useState } from "react";
import { fmt, rpc, supabase, when } from "@/lib/supabase";
import { useMe, useRun } from "@/components/Shell";
import { Badge, Empty, Field, Loading, Modal, Page, Toggle, useAsync } from "@/components/ui";

type Agent = { agent_id: string; username: string; public_id: number; display_name: string | null; coins: number; accepts_topups: boolean; waiting: number; approved_today: number; coins_today: number };
type Acc = { id?: number; agent_id: string; method: string; currency: string; account_number: string; account_name: string | null; account_type: string; instructions: string | null; active: boolean };
const METHODS = ["bkash", "nagad", "rocket", "upay", "bank", "usdt"];
const METHOD: Record<string, string> = { bkash: "bKash", nagad: "Nagad", rocket: "Rocket", upay: "Upay", bank: "Bank", usdt: "USDT" };

export default function Agents() {
  const me = useMe();
  const owner = me?.role === "admin";
  const run = useRun();
  const [amt, setAmt] = useState<Record<string, string>>({});
  const [edit, setEdit] = useState<Acc | null>(null);
  const agents = useAsync(() => rpc<Agent[]>("agent_overview"));
  const accs = useAsync(async () => {
    const { data, error } = await supabase.from("agent_pay_accounts").select("*").order("method");
    if (error) throw error;
    return data as Acc[];
  });
  const sales = useAsync(async () => {
    const { data } = await supabase.from("agent_sales").select("id, coins, method, amount_local, created_at, agent:profiles!agent_sales_agent_id_fkey(username), buyer:profiles!agent_sales_buyer_id_fkey(username, public_id)").order("id", { ascending: false }).limit(100);
    return (data ?? []) as unknown as { id: number; coins: number; method: string; amount_local: number; created_at: string; agent: { username: string }; buyer: { username: string; public_id: number } }[];
  });

  const saveAcc = async (a: Acc) => {
    if (!a.account_number.trim()) throw new Error("Account number is required");
    const row = { ...a, currency: a.method === "usdt" ? "USD" : "BDT" };
    const { error } = a.id ? await supabase.from("agent_pay_accounts").update(row).eq("id", a.id) : await supabase.from("agent_pay_accounts").insert(row);
    if (error) throw error;
    setEdit(null); accs.reload();
  };

  return (
    <Page title={owner ? "Coin agents" : "My agent account"} sub={owner
      ? "Pick which agents receive payments, add their bKash/Nagad/Rocket numbers, and give them coin stock. New orders go to the agent with enough stock and the fewest waiting orders. To make someone an agent, open them in Users and set the role to agent."
      : "Your coin stock and the numbers users pay you on. Ask the owner to change a number."}>
      {agents.loading || agents.err ? <Loading err={agents.err} /> : !agents.data?.length ? <Empty>No agents yet. Set a user's role to agent in Users.</Empty> : (
        <div className="grid g2 mb">{agents.data.map((a) => {
          const mine = accs.data?.filter((x) => x.agent_id === a.agent_id) ?? [];
          return (
            <div key={a.agent_id} className="card form">
              <div className="row" style={{ justifyContent: "space-between" }}>
                <div><b>{a.display_name || a.username}</b><small className="muted">{a.username} · {a.public_id}</small></div>
                {owner ? <Toggle label="Receives top-ups" on={a.accepts_topups} onChange={(v) => run(async () => { await rpc("admin_set_topup_agent", { p_agent: a.agent_id, p_accepts: v }); agents.reload(); }, v ? "Now receiving top-ups" : "Stopped receiving top-ups")} />
                  : <Badge tone={a.accepts_topups ? "green" : "dim"}>{a.accepts_topups ? "Receiving top-ups" : "Not receiving"}</Badge>}
              </div>
              <div className="row" style={{ gap: 18 }}>
                <div><span className="lbl">Coin stock</span><div style={{ fontSize: 22, fontFamily: "Bodoni Moda, serif", color: "var(--gold)" }}>{fmt(a.coins)}</div></div>
                <div><span className="lbl">To check</span><div style={{ fontSize: 22 }}>{a.waiting}</div></div>
                <div><span className="lbl">Sent today</span><div style={{ fontSize: 22 }}>{fmt(a.coins_today)}</div></div>
              </div>
              {owner && (
                <div className="row">
                  <input type="number" placeholder="Coins to add to stock" value={amt[a.agent_id] ?? ""} onChange={(e) => setAmt({ ...amt, [a.agent_id]: e.target.value })} style={{ flex: 1 }} />
                  <button className="sm gold" onClick={() => run(async () => { await rpc("admin_add_agent_stock", { p_agent: a.agent_id, p_coins: Number(amt[a.agent_id]) }); setAmt({ ...amt, [a.agent_id]: "" }); agents.reload(); }, "Stock added")}>Add stock</button>
                  <button className="sm ghost" onClick={() => { const n = prompt("Name shown in the console", a.display_name ?? a.username); if (n !== null) run(async () => { await rpc("admin_set_topup_agent", { p_agent: a.agent_id, p_accepts: a.accepts_topups, p_name: n }); agents.reload(); }); }}>Rename</button>
                </div>
              )}
              <span className="lbl">Payment numbers</span>
              {!mine.length ? <span className="muted sm">No numbers yet</span> : mine.map((x) => (
                <div key={x.id} className="row" style={{ justifyContent: "space-between", background: "#100d0b", border: "1px solid var(--line)", borderRadius: 10, padding: "8px 10px" }}>
                  <span><b>{METHOD[x.method]}</b> {x.account_number} <span className="muted sm">{x.account_type}{x.account_name ? ` · ${x.account_name}` : ""}</span></span>
                  <span className="row">{!x.active && <Badge tone="dim">off</Badge>}{owner && <button className="sm ghost" onClick={() => setEdit({ ...x })}>Edit</button>}</span>
                </div>
              ))}
              {owner && <button className="sm" onClick={() => setEdit({ agent_id: a.agent_id, method: "bkash", currency: "BDT", account_number: "", account_name: a.display_name || a.username, account_type: "personal", instructions: "Use Send Money. Do not Cash Out.", active: true })}>+ Add number</button>}
            </div>
          );
        })}</div>
      )}
      <h3 className="mb">Recent agent sales</h3>
      {sales.loading ? <Loading /> : !sales.data?.length ? <Empty /> : (
        <div className="card tw"><table>
          <thead><tr><th>When</th><th>Agent</th><th>Buyer</th><th>Coins</th><th>Paid</th></tr></thead>
          <tbody>{sales.data.map((s) => <tr key={s.id}><td className="sm">{when(s.created_at)}</td><td>{s.agent?.username}</td><td>{s.buyer?.username} <span className="muted sm">{s.buyer?.public_id}</span></td><td>{fmt(s.coins)}</td><td className="sm">{fmt(s.amount_local)} via {METHOD[s.method] ?? s.method}</td></tr>)}</tbody>
        </table></div>
      )}
      {edit && (
        <Modal title={edit.id ? "Edit payment number" : "Add payment number"} onClose={() => setEdit(null)}>
          <form className="form" onSubmit={(e) => { e.preventDefault(); run(() => saveAcc(edit), "Saved"); }}>
            <Field label="Method"><select value={edit.method} onChange={(e) => setEdit({ ...edit, method: e.target.value })}>{METHODS.map((m) => <option key={m} value={m}>{METHOD[m]}</option>)}</select></Field>
            <Field label={edit.method === "usdt" ? "Wallet address (TRC20)" : edit.method === "bank" ? "Bank account (bank, branch, account number)" : "Number"}><input value={edit.account_number} onChange={(e) => setEdit({ ...edit, account_number: e.target.value })} required /></Field>
            <Field label="Account name"><input value={edit.account_name ?? ""} onChange={(e) => setEdit({ ...edit, account_name: e.target.value })} /></Field>
            <Field label="Type"><select value={edit.account_type} onChange={(e) => setEdit({ ...edit, account_type: e.target.value })}>{["personal", "agent", "merchant", "wallet"].map((t) => <option key={t}>{t}</option>)}</select></Field>
            <Field label="Instructions shown to the user"><input value={edit.instructions ?? ""} onChange={(e) => setEdit({ ...edit, instructions: e.target.value })} /></Field>
            <Field label="Active"><Toggle on={edit.active} onChange={(v) => setEdit({ ...edit, active: v })} /></Field>
            <div className="row end">
              {edit.id && <button type="button" className="ghost danger" onClick={() => run(async () => { const { error } = await supabase.from("agent_pay_accounts").delete().eq("id", edit.id!); if (error) throw error; setEdit(null); accs.reload(); }, "Removed")}>Delete</button>}
              <button className="gold">Save</button>
            </div>
          </form>
        </Modal>
      )}
    </Page>
  );
}
