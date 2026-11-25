"use client";
import { useState } from "react";
import { rpc, supabase, when } from "@/lib/supabase";
import { useRun } from "@/components/Shell";
import { Badge, Empty, Loading, Page, useAsync } from "@/components/ui";

type R = { id: number; reason: string; details: string | null; status: string; action: string | null; created_at: string; target_user: string | null; target_room: number | null; target_reel: string | null;
  reporter: { username: string } | null; target: { username: string; public_id: number } | null };

export default function Reports() {
  const run = useRun();
  const [status, setStatus] = useState("new");
  const { data, loading, err, reload } = useAsync(async () => {
    const { data, error } = await supabase.from("reports").select("*, reporter:profiles!reports_reporter_id_fkey(username), target:profiles!reports_target_user_fkey(username, public_id)").eq("status", status).order("id", { ascending: false }).limit(200);
    if (error) throw error;
    return data as unknown as R[];
  }, [status]);
  const act = (id: number, action: string, days = 0) => run(async () => { await rpc("admin_resolve_report", { p_report: id, p_action: action, p_ban_days: days }); reload(); }, "Done");
  return (
    <Page title="Reports" sub="What users reported. Take action or dismiss.">
      <div className="tabs">{["new", "actioned", "dismissed"].map((s) => <button key={s} className={"sm" + (s === status ? " on" : "")} onClick={() => setStatus(s)}>{s}</button>)}</div>
      {loading || err ? <Loading err={err} /> : !data?.length ? <Empty>No reports</Empty> : (
        <div className="grid g2">{data.map((r) => (
          <div key={r.id} className="card form">
            <div className="row" style={{ justifyContent: "space-between" }}><Badge tone="red">{r.reason}</Badge><span className="muted sm">{when(r.created_at)}</span></div>
            <div><b>{r.target ? `${r.target.username} (${r.target.public_id})` : r.target_room ? `Room #${r.target_room}` : r.target_reel ? "A reel" : "—"}</b>
              <small className="muted">reported by {r.reporter?.username ?? "deleted user"}</small></div>
            {r.details && <p style={{ margin: 0 }}>{r.details}</p>}
            {r.status === "new" ? (
              <div className="row">
                {r.target_user && <><button className="sm" onClick={() => act(r.id, "warn")}>Warn</button><button className="sm red" onClick={() => act(r.id, "ban", 7)}>Ban 7 days</button></>}
                {r.target_room && <button className="sm red" onClick={() => act(r.id, "suspend_room")}>Suspend room</button>}
                {r.target_reel && <button className="sm red" onClick={() => act(r.id, "remove_reel")}>Remove reel</button>}
                <button className="sm ghost" onClick={() => act(r.id, "dismiss")}>Dismiss</button>
              </div>
            ) : <span className="muted sm">Action: {r.action}</span>}
          </div>
        ))}</div>
      )}
    </Page>
  );
}
