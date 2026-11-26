"use client";
import Link from "next/link";
import { useState } from "react";
import { fmt, money, rpc, supabase, when } from "@/lib/supabase";
import { useMe, useRun } from "@/components/Shell";
import { Badge, Empty, Field, Loading, Modal, Page, useAsync } from "@/components/ui";

type U = {
  id: string; public_id: number; username: string; email: string | null; phone: string | null; role: string; coins: number; diamonds: number;
  lifetime_usd: number; wealth_level: number; verified: boolean; banned_until: string | null; deleted_at: string | null; created_at: string;
};
const ROLES = ["user", "host", "agent", "moderator", "admin"];

export default function Users() {
  const [q, setQ] = useState("");
  const [term, setTerm] = useState("");
  const [sel, setSel] = useState<U | null>(null);
  const { data, loading, err, reload } = useAsync(() => rpc<U[]>("admin_find_users", { p_q: term, p_limit: 100 }), [term]);

  return (
    <Page title="Users" sub="Search by username, email, phone or user ID. Click a name to see everything about that person.">
      <form className="row mb" onSubmit={(e) => { e.preventDefault(); setTerm(q.trim()); }}>
        <input placeholder="Search…" value={q} onChange={(e) => setQ(e.target.value)} style={{ maxWidth: 360 }} />
        <button>Search</button>
      </form>
      {loading || err ? <Loading err={err} /> : !data?.length ? <Empty>No users found</Empty> : (
        <div className="card tw">
          <table>
            <thead><tr><th>User</th><th>ID</th><th>Contact</th><th>Role</th><th>Coins</th><th>Diamonds</th><th>Spent</th><th>Status</th><th /></tr></thead>
            <tbody>
              {data.map((u) => (
                <tr key={u.id}>
                  <td><Link href={`/users/view/?id=${u.id}`}><b style={{ color: "var(--gold)" }}>{u.username}</b></Link><small className="muted">Lv {u.wealth_level} {u.verified && "· verified"}</small></td>
                  <td>{u.public_id}</td>
                  <td className="sm">{u.email}<br /><span className="muted">{u.phone}</span></td>
                  <td><Badge tone={u.role === "admin" ? "gold" : u.role === "user" ? "dim" : ""}>{u.role}</Badge></td>
                  <td>{fmt(u.coins)}</td><td>{fmt(u.diamonds)}</td><td>{money(u.lifetime_usd)}</td>
                  <td>{status(u)}</td>
                  <td className="act"><Link href={`/users/view/?id=${u.id}`}><button className="sm ghost">View all</button></Link> <button className="sm" onClick={() => setSel(u)}>Manage</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {sel && <UserModal u={sel} onClose={() => { setSel(null); reload(); }} />}
    </Page>
  );
}

function status(u: U) {
  if (u.deleted_at) return <Badge tone="dim">Deleted</Badge>;
  if (u.banned_until && new Date(u.banned_until) > new Date()) return <Badge tone="red">Banned</Badge>;
  return <Badge tone="green">Active</Badge>;
}

function UserModal({ u, onClose }: { u: U; onClose: () => void }) {
  const run = useRun();
  const me = useMe();
  const sup = me?.role === "admin";
  const [delta, setDelta] = useState("");
  const [reason, setReason] = useState("");
  const [days, setDays] = useState("7");
  const [banReason, setBanReason] = useState("");
  const [role, setRole] = useState(u.role);
  const tx = useAsync(async () => {
    const { data } = await supabase.from("transactions").select("id, kind, coins, diamonds, ref, created_at").eq("user_id", u.id).order("id", { ascending: false }).limit(30);
    return data ?? [];
  });

  return (
    <Modal title={`${u.username} · ${u.public_id}`} onClose={onClose} wide>
      <div className="row end mb"><Link href={`/users/view/?id=${u.id}`}><button className="sm ghost">Open full profile & activity →</button></Link></div>
      <div className="grid g2">
        <div className="form">
          <dl className="kv">
            <dt>Email</dt><dd>{u.email ?? "—"}</dd><dt>Phone</dt><dd>{u.phone ?? "—"}</dd>
            <dt>Coins</dt><dd>{fmt(u.coins)}</dd><dt>Diamonds</dt><dd>{fmt(u.diamonds)}</dd>
            <dt>Total recharged</dt><dd>{money(u.lifetime_usd)}</dd><dt>Joined</dt><dd>{when(u.created_at)}</dd>
            <dt>Banned until</dt><dd>{when(u.banned_until)}</dd><dt>Status</dt><dd>{status(u)}</dd>
          </dl>
          {sup && (
            <div className="card">
              <h3 className="mb">Adjust coins</h3>
              <div className="row">
                <input type="number" placeholder="+1000000 or -500000" value={delta} onChange={(e) => setDelta(e.target.value)} style={{ flex: 1 }} />
                <input placeholder="Reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} style={{ flex: 2 }} />
              </div>
              <div className="row end" style={{ marginTop: 8 }}>
                <button className="gold sm" onClick={() => run(async () => { await rpc("admin_adjust_coins", { p_user: u.id, p_delta: Number(delta), p_reason: reason }); onClose(); }, "Balance updated")}>Apply</button>
              </div>
            </div>
          )}
          <div className="card">
            <h3 className="mb">Ban</h3>
            <div className="row">
              <select value={days} onChange={(e) => setDays(e.target.value)} style={{ flex: 1 }}>
                <option value="1">1 day</option><option value="7">7 days</option><option value="30">30 days</option><option value="36500">Permanent</option>
              </select>
              <input placeholder="Reason" value={banReason} onChange={(e) => setBanReason(e.target.value)} style={{ flex: 2 }} />
            </div>
            <div className="row end" style={{ marginTop: 8 }}>
              <button className="ghost sm" onClick={() => run(async () => { await rpc("admin_ban", { p_user: u.id, p_days: 0, p_reason: "unban" }); onClose(); }, "Unbanned")}>Unban</button>
              <button className="red sm" onClick={() => run(async () => { await rpc("admin_ban", { p_user: u.id, p_days: Number(days), p_reason: banReason }); onClose(); }, "User banned")}>Ban</button>
            </div>
          </div>
          {sup && (
            <Field label="Role" hint="Agents can sell coins from their stock. Moderators can use this console except money and settings.">
              <div className="row">
                <select value={role} onChange={(e) => setRole(e.target.value)} style={{ flex: 1 }}>{ROLES.map((r) => <option key={r}>{r}</option>)}</select>
                <button className="sm" onClick={() => run(() => rpc("admin_set_role", { p_user: u.id, p_role: role }), "Role changed")}>Save role</button>
              </div>
            </Field>
          )}
        </div>
        <div>
          <h3 className="mb">Recent coin activity</h3>
          {tx.loading ? <Loading /> : !tx.data?.length ? <Empty /> : (
            <div className="card tw" style={{ maxHeight: 520 }}>
              <table>
                <thead><tr><th>When</th><th>Type</th><th>Coins</th><th>Diamonds</th></tr></thead>
                <tbody>{tx.data.map((t) => (
                  <tr key={t.id}><td className="sm">{when(t.created_at)}</td><td className="sm">{t.kind.replace("_", " ")}</td>
                    <td style={{ color: t.coins < 0 ? "#f08aa0" : t.coins > 0 ? "#6fd6b5" : undefined }}>{t.coins ? fmt(t.coins) : ""}</td><td>{t.diamonds ? fmt(t.diamonds) : ""}</td></tr>
                ))}</tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </Modal>
  );
}
