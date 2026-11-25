"use client";
import Link from "next/link";
import { useState } from "react";
import { fmt, money, rpc } from "@/lib/supabase";
import { Loading, Page, useAsync } from "@/components/ui";

type Stats = {
  revenue_usd: number; payments: number; paying_users: number; new_users: number; total_users: number; active_rooms: number;
  gift_coins: number; open_reports: number; pending_payouts: number; pending_verifications: number;
  daily: { day: string; revenue: number; signups: number }[];
};

export default function Dashboard() {
  const [days, setDays] = useState(30);
  const { data: s, loading, err } = useAsync(() => rpc<Stats>("admin_stats", { p_days: days }), [days]);

  return (
    <Page title="Dashboard" sub="How Adda is doing" actions={
      <div className="tabs" style={{ margin: 0 }}>{[7, 30, 90].map((d) => <button key={d} className={"sm" + (d === days ? " on" : "")} onClick={() => setDays(d)}>{d} days</button>)}</div>
    }>
      {loading || err || !s ? <Loading err={err} /> : (
        <>
          <div className="grid g4 mb">
            <Stat k="Revenue" v={money(s.revenue_usd)} gold />
            <Stat k="Payments" v={fmt(s.payments)} sub={`${fmt(s.paying_users)} paying users`} />
            <Stat k="New users" v={fmt(s.new_users)} sub={`${fmt(s.total_users)} total`} />
            <Stat k="Live rooms" v={fmt(s.active_rooms)} />
            <Stat k="Coins gifted" v={fmt(s.gift_coins)} sub={money(s.gift_coins / 500000) + " value"} />
          </div>
          <div className="grid g2 mb">
            <div className="card"><h3>Revenue per day</h3><Bars rows={s.daily.map((d) => [d.day, Number(d.revenue), money(d.revenue)])} /></div>
            <div className="card"><h3>Sign-ups per day</h3><Bars rows={s.daily.map((d) => [d.day, Number(d.signups), fmt(d.signups) + " sign-ups"])} /></div>
          </div>
          <div className="grid g4">
            <Todo href="/reports/" n={s.open_reports} label="Reports to review" />
            <Todo href="/verifications/" n={s.pending_verifications} label="Identity checks waiting" />
            <Todo href="/payouts/" n={s.pending_payouts} label="Host payouts to process" />
          </div>
        </>
      )}
    </Page>
  );
}

function Stat({ k, v, sub, gold }: { k: string; v: string; sub?: string; gold?: boolean }) {
  return <div className="card stat"><div className="k">{k}</div><div className={"v" + (gold ? " gold" : "")}>{v}</div>{sub && <small className="muted">{sub}</small>}</div>;
}

function Bars({ rows }: { rows: [string, number, string][] }) {
  const max = Math.max(1, ...rows.map((r) => r[1]));
  return <div className="chart">{rows.map(([d, v, t]) => <div key={d} style={{ height: `${(v / max) * 100}%` }} data-t={`${d}: ${t}`} />)}</div>;
}

function Todo({ href, n, label }: { href: string; n: number; label: string }) {
  return (
    <Link href={href} className="card stat" style={{ textDecoration: "none", color: "inherit" }}>
      <div className="k">{label}</div><div className={"v" + (n ? " gold" : "")}>{fmt(n)}</div><small className="muted">Open →</small>
    </Link>
  );
}
