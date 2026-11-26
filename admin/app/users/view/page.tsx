"use client";
import Link from "next/link";
import { Suspense, useState } from "react";
import { useSearchParams } from "next/navigation";
import { fmt, money, rpc, when } from "@/lib/supabase";
import { Badge, Empty, Loading, Page, useAsync } from "@/components/ui";

type Row = Record<string, unknown>;
type Detail = {
  profile: Row | null; private: Row | null; auth: Row; wallet: Row | null; stats: Record<string, number>;
  devices: Row[]; verifications: Row[]; rooms: Row[]; joined: Row[]; transactions: Row[]; gifts_sent: Row[]; gifts_received: Row[];
  games: Row[]; party_games: Row[]; topups: Row[]; payments: Row[]; payouts: Row[]; checkins: Row[];
  reports_against: Row[]; reports_made: Row[]; avatars: Row[]; audit: Row[];
};

const TABS: [keyof Detail, string][] = [
  ["transactions", "Coin & diamond activity"], ["gifts_sent", "Gifts sent"], ["gifts_received", "Gifts received"],
  ["games", "Lucky games"], ["party_games", "Party games"], ["topups", "Top-ups"], ["payments", "Payments"],
  ["payouts", "Withdrawals"], ["checkins", "Daily rewards"], ["joined", "Rooms joined"], ["rooms", "Rooms owned"],
  ["reports_against", "Reports about them"], ["reports_made", "Reports they made"], ["verifications", "ID checks"],
  ["devices", "Devices"], ["audit", "Admin actions"],
];

export default function UserViewPage() {
  return <Suspense fallback={<Page title="User"><Loading /></Page>}><UserView /></Suspense>;
}

function UserView() {
  const id = useSearchParams().get("id") ?? "";
  const [tab, setTab] = useState<keyof Detail>("transactions");
  const { data, loading, err } = useAsync(() => rpc<Detail>("admin_user_detail", { p_user: id }), [id]);
  if (!id) return <Page title="User"><Empty>No user selected</Empty></Page>;
  if (loading || err || !data) return <Page title="User"><Loading err={err} /></Page>;
  const p = data.profile ?? {};
  const a = data.auth ?? {};
  const v = data.private ?? {};
  const w = data.wallet ?? {};
  const s = data.stats ?? {};
  const banned = p.banned_until && new Date(String(p.banned_until)) > new Date();
  const avatar = (p.avatar_url as string) || `https://api.dicebear.com/9.x/adventurer/svg?seed=${encodeURIComponent(String(p.username))}`;
  const rows = (data[tab] as Row[]) ?? [];

  return (
    <Page title={String(p.username ?? "User")} sub={`User ID ${p.public_id ?? ""} · joined ${when(p.created_at as string)}`}
      actions={<Link href="/users/"><button className="ghost sm">← All users</button></Link>}>
      <div className="grid g2 mb">
        <div className="card">
          <div className="row" style={{ gap: 14, alignItems: "center", marginBottom: 12 }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={avatar} alt="" width={84} height={84} style={{ borderRadius: "50%", objectFit: "cover", border: "2px solid var(--gold)" }} />
            <div>
              <h2 style={{ margin: 0 }}>{String(p.username)}</h2>
              <div className="row" style={{ gap: 6, marginTop: 6, flexWrap: "wrap" }}>
                <Badge tone={p.role === "admin" ? "gold" : p.role === "user" ? "dim" : ""}>{String(p.role)}</Badge>
                {p.verified ? <Badge tone="green">ID verified</Badge> : <Badge tone="dim">not verified</Badge>}
                {p.deleted_at ? <Badge tone="dim">deleted</Badge> : banned ? <Badge tone="red">banned</Badge> : <Badge tone="green">active</Badge>}
                <Badge>Lv {String(p.wealth_level)}</Badge>
              </div>
            </div>
          </div>
          {p.bio ? <p className="muted" style={{ marginTop: 0 }}>“{String(p.bio)}”</p> : null}
          <h3 className="mb">Profile & sign-in</h3>
          <dl className="kv">
            <dt>Email</dt><dd>{String(v.email ?? a.email ?? "—")} {a.email_confirmed_at ? <small className="muted">confirmed</small> : null}</dd>
            <dt>Phone</dt><dd>{String(v.phone ?? a.phone ?? "—")} {v.phone_verified ? <small className="muted">verified</small> : null}</dd>
            <dt>Signed up with</dt><dd>{Array.isArray(a.providers) ? (a.providers as string[]).join(", ") : "—"}</dd>
            <dt>Last sign-in</dt><dd>{when(a.last_sign_in_at as string)}</dd>
            <dt>Country</dt><dd>{String(p.country ?? "—")}</dd>
            <dt>Avatar</dt><dd>{p.avatar_url ? <a href={String(p.avatar_url)} target="_blank">uploaded picture</a> : `preset #${p.avatar_preset}`}</dd>
            <dt>Cover</dt><dd>{p.cover_url ? <a href={String(p.cover_url)} target="_blank">uploaded cover</a> : "default"}</dd>
            <dt>18+ games</dt><dd>{p.games_ok_at ? `accepted ${when(String(p.games_ok_at))}` : "not accepted"}</dd>
            <dt>VIP</dt><dd>{p.vip_tier ? `${p.vip_tier} until ${when(String(p.vip_until))}` : "—"}</dd>
            <dt>Banned until</dt><dd>{when(p.banned_until as string)}</dd>
            <dt>Internal ID</dt><dd className="sm muted">{id}</dd>
          </dl>
          {a.signup_data && Object.keys(a.signup_data as object).length ? (
            <details style={{ marginTop: 10 }}><summary className="muted">Sign-up form data</summary>
              <pre className="sm" style={{ whiteSpace: "pre-wrap" }}>{JSON.stringify(a.signup_data, null, 2)}</pre></details>
          ) : null}
        </div>
        <div className="grid" style={{ alignContent: "start" }}>
          <div className="grid g4">
            <Stat k="Coins" v={fmt(w.coins as number)} gold />
            <Stat k="Diamonds" v={fmt(w.diamonds as number)} />
            <Stat k="Recharged" v={money(p.lifetime_usd as number)} />
            <Stat k="Withdrawn" v={money(s.withdrawn_usd)} />
          </div>
          <div className="card">
            <h3 className="mb">Activity summary</h3>
            <dl className="kv">
              <dt>Followers</dt><dd>{fmt(s.followers)} · following {fmt(s.following)}</dd>
              <dt>Rooms</dt><dd>owns {fmt(s.rooms_owned)} · joined {fmt(s.rooms_joined)}</dd>
              <dt>Chat messages</dt><dd>{fmt(s.messages_sent)}</dd>
              <dt>Gifts</dt><dd>sent {fmt(s.gifts_sent_coins)} coins · received {fmt(s.gifts_received_coins)} coins</dd>
              <dt>Lucky games</dt><dd>bet {fmt(s.game_bets)} · won back {fmt(s.game_payouts)} · net <b style={{ color: s.game_payouts - s.game_bets < 0 ? "#f08aa0" : "#6fd6b5" }}>{fmt(s.game_payouts - s.game_bets)}</b></dd>
              <dt>Top-ups</dt><dd>{fmt(s.topups_coins)} coins via agents · {fmt(s.payments_paid)} paid checkouts</dd>
              <dt>Reels</dt><dd>{fmt(s.reels)}</dd>
              <dt>Reports</dt><dd>{s.reports_against ? <Badge tone="red">{s.reports_against} against them</Badge> : "none against them"}</dd>
            </dl>
          </div>
          {data.avatars.length > 0 && (
            <div className="card">
              <h3 className="mb">AI avatars they made</h3>
              <div className="row" style={{ gap: 8, flexWrap: "wrap" }}>
                {data.avatars.map((x) => (
                  // eslint-disable-next-line @next/next/no-img-element
                  <a key={String(x.id)} href={String(x.image_url)} target="_blank"><img src={String(x.image_url)} alt="" width={72} height={72} style={{ borderRadius: 12, objectFit: "cover" }} title={`${x.style} · ${when(String(x.created_at))}`} /></a>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      <div className="tabs">
        {TABS.map(([k, label]) => (
          <button key={k} className={"sm" + (k === tab ? " on" : "")} onClick={() => setTab(k)}>
            {label} <small className="muted">{(data[k] as Row[])?.length ?? 0}</small>
          </button>
        ))}
      </div>
      {rows.length === 0 ? <Empty /> : <Table rows={rows} />}
    </Page>
  );
}

function Stat({ k, v, gold }: { k: string; v: string; gold?: boolean }) {
  return <div className="card stat"><div className="k">{k}</div><div className={"v" + (gold ? " gold" : "")} style={{ fontSize: 22 }}>{v}</div></div>;
}

const HIDE = new Set(["user_id", "processed_by", "reviewed_by", "raw", "id_doc_path", "selfie_path"]);

function cell(k: string, v: unknown) {
  if (v === null || v === undefined || v === "") return <span className="muted">—</span>;
  if (typeof v === "boolean") return v ? "yes" : "no";
  if (/(_at|^day|created|joined)/.test(k) && typeof v === "string" && /^\d{4}-\d\d-\d\d/.test(v)) return <span className="sm">{when(v)}</span>;
  if (k === "status") return <Badge tone={["paid", "approved", "done"].includes(String(v)) ? "green" : ["rejected", "failed", "cancelled", "expired"].includes(String(v)) ? "red" : ""}>{String(v)}</Badge>;
  if (typeof v === "number") return <span style={{ color: v < 0 ? "#f08aa0" : undefined }}>{fmt(v)}</span>;
  if (typeof v === "object") return <span className="sm muted">{JSON.stringify(v)}</span>;
  return String(v);
}

function Table({ rows }: { rows: Row[] }) {
  const cols = Array.from(new Set(rows.flatMap((r) => Object.keys(r)))).filter((c) => !HIDE.has(c));
  return (
    <div className="card tw" style={{ maxHeight: 560 }}>
      <table>
        <thead><tr>{cols.map((c) => <th key={c}>{c.replace(/_/g, " ")}</th>)}</tr></thead>
        <tbody>{rows.map((r, i) => <tr key={i}>{cols.map((c) => <td key={c}>{cell(c, r[c])}</td>)}</tr>)}</tbody>
      </table>
    </div>
  );
}
