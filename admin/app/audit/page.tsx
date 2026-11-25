"use client";
import { supabase, when } from "@/lib/supabase";
import { Empty, Loading, Page, useAsync } from "@/components/ui";

export default function Audit() {
  const { data, loading, err } = useAsync(async () => {
    const { data, error } = await supabase.from("audit_log").select("*").order("id", { ascending: false }).limit(300);
    if (error) throw error;
    const ids = [...new Set(data.map((r) => r.actor_id).filter(Boolean))];
    const { data: names } = ids.length ? await supabase.from("profiles").select("id, username").in("id", ids) : { data: [] };
    const nm = Object.fromEntries((names ?? []).map((n) => [n.id, n.username]));
    return data.map((r) => ({ ...r, actor: nm[r.actor_id] ?? "system" }));
  });
  return (
    <Page title="Audit log" sub="Every admin action that touched money, users, rooms or settings.">
      {loading || err ? <Loading err={err} /> : !data?.length ? <Empty /> : (
        <div className="card tw"><table>
          <thead><tr><th>When</th><th>Admin</th><th>Action</th><th>Target</th><th>Details</th></tr></thead>
          <tbody>{data.map((r) => <tr key={r.id}><td className="sm">{when(r.created_at)}</td><td>{r.actor}</td><td>{r.action.replace(/_/g, " ")}</td><td className="sm muted">{r.target}</td><td className="sm muted" style={{ maxWidth: 380, wordBreak: "break-all" }}>{JSON.stringify(r.meta)}</td></tr>)}</tbody>
        </table></div>
      )}
    </Page>
  );
}
