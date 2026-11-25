"use client";
import { useState } from "react";
import { fmt, supabase, when } from "@/lib/supabase";
import { useRun } from "@/components/Shell";
import { Badge, Empty, Loading, Page, useAsync } from "@/components/ui";

type R = { id: string; video_url: string; cover_url: string | null; caption: string; views: number; likes: number; coins_earned: number; status: string; created_at: string; user: { username: string; public_id: number } | null };

export default function Reels() {
  const run = useRun();
  const [status, setStatus] = useState("active");
  const { data, loading, err, reload } = useAsync(async () => {
    const { data, error } = await supabase.from("reels").select("*, user:profiles!reels_user_id_fkey(username, public_id)").eq("status", status).order("created_at", { ascending: false }).limit(60);
    if (error) throw error;
    return data as unknown as R[];
  }, [status]);
  const set = (id: string, s: string) => run(async () => { const { error } = await supabase.from("reels").update({ status: s }).eq("id", id); if (error) throw error; reload(); }, s === "removed" ? "Reel removed" : "Reel restored");
  return (
    <Page title="Reels" sub="Review and remove reels that break the rules.">
      <div className="tabs">{["active", "hidden", "removed"].map((s) => <button key={s} className={"sm" + (s === status ? " on" : "")} onClick={() => setStatus(s)}>{s}</button>)}</div>
      {loading || err ? <Loading err={err} /> : !data?.length ? <Empty /> : (
        <div className="rcards">{data.map((r) => (
          <div key={r.id} className="rc">
            <video src={r.video_url} poster={r.cover_url ?? undefined} controls preload="none" style={{ width: "100%", aspectRatio: "9/14", background: "#000", objectFit: "cover" }} />
            <div className="bd">
              <b className="sm">{r.user?.username} <span className="muted">{r.user?.public_id}</span></b>
              <span className="sm">{r.caption || <span className="muted">No caption</span>}</span>
              <span className="muted sm">{fmt(r.views)} views · {fmt(r.likes)} likes · {fmt(r.coins_earned)} coins · {when(r.created_at)}</span>
              <div className="row"><Badge>{r.status}</Badge>
                {r.status !== "removed" ? <button className="sm red" onClick={() => set(r.id, "removed")}>Remove</button> : <button className="sm" onClick={() => set(r.id, "active")}>Restore</button>}</div>
            </div>
          </div>
        ))}</div>
      )}
    </Page>
  );
}
