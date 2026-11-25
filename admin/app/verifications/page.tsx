"use client";
import { useState } from "react";
import { rpc, supabase, when } from "@/lib/supabase";
import { useRun } from "@/components/Shell";
import { Empty, Loading, Page, useAsync } from "@/components/ui";

type V = { id: number; user_id: string; id_doc_path: string; selfie_path: string; created_at: string; user: { username: string; public_id: number } | null; doc?: string; selfie?: string };

export default function Verifications() {
  const run = useRun();
  const [note, setNote] = useState<Record<number, string>>({});
  const { data, loading, err, reload } = useAsync(async () => {
    const { data, error } = await supabase.from("verifications").select("*, user:profiles!verifications_user_id_fkey(username, public_id)").eq("status", "pending").order("id");
    if (error) throw error;
    const rows = data as unknown as V[];
    // identity photos are private: show them through short-lived signed links
    for (const v of rows) {
      const { data: s } = await supabase.storage.from("verification").createSignedUrls([v.id_doc_path, v.selfie_path], 600);
      v.doc = s?.[0]?.signedUrl ?? undefined; v.selfie = s?.[1]?.signedUrl ?? undefined;
    }
    return rows;
  });
  const review = (id: number, ok: boolean) => run(async () => { await rpc("admin_review_verification", { p_id: id, p_approve: ok, p_note: note[id] || null }); reload(); }, ok ? "Verified" : "Rejected");
  return (
    <Page title="Identity verification" sub="Hosts must be verified before they can withdraw earnings. Photos links expire after 10 minutes.">
      {loading || err ? <Loading err={err} /> : !data?.length ? <Empty>Nothing waiting</Empty> : (
        <div className="grid g2">{data.map((v) => (
          <div key={v.id} className="card form">
            <div><b>{v.user?.username}</b> <span className="muted">{v.user?.public_id}</span><small className="muted">{when(v.created_at)}</small></div>
            <div className="row" style={{ alignItems: "stretch" }}>
              {[v.doc, v.selfie].map((u, i) => <a key={i} href={u} target="_blank" rel="noreferrer" style={{ flex: 1 }}><img src={u} alt={i ? "Selfie" : "ID document"} style={{ width: "100%", aspectRatio: "4/3", objectFit: "cover", borderRadius: 10 }} /></a>)}
            </div>
            <input placeholder="Note to the user (shown if rejected)" value={note[v.id] ?? ""} onChange={(e) => setNote({ ...note, [v.id]: e.target.value })} />
            <div className="row end"><button className="sm red" onClick={() => review(v.id, false)}>Reject</button><button className="sm green" onClick={() => review(v.id, true)}>Approve</button></div>
          </div>
        ))}</div>
      )}
    </Page>
  );
}
