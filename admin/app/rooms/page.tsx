"use client";
// Rooms shown on the app's homepage: change cover image or template, pin to the top, reorder, suspend.
import { useState } from "react";
import { fmt, rpc, supabase } from "@/lib/supabase";
import { useRun } from "@/components/Shell";
import { Badge, Empty, Field, ImageInput, Loading, Modal, Page, Toggle, useAsync } from "@/components/ui";

type Room = {
  id: number; name: string; topic: string; language: string; region: string; cover_url: string | null; cover_template: string;
  theme: string; seats: number; locked: boolean; featured: boolean; home_order: number; status: string; listeners: number;
  score_today: number; created_at: string; owner: { username: string; public_id: number } | null;
};
type Tpl = { id: string; name: string; image_url: string | null };

export default function Rooms() {
  const run = useRun();
  const [tab, setTab] = useState<"open" | "featured" | "suspended" | "closed">("open");
  const [q, setQ] = useState("");
  const [edit, setEdit] = useState<Room | null>(null);
  const [ordering, setOrdering] = useState(false);

  const tpls = useAsync(async () => {
    const { data } = await supabase.from("room_cover_templates").select("id, name, image_url").order("sort");
    return (data ?? []) as Tpl[];
  });
  const themes = useAsync(async () => {
    const { data } = await supabase.from("room_themes").select("id, name").order("sort");
    return (data ?? []) as { id: string; name: string }[];
  });
  const { data, loading, err, reload } = useAsync(async () => {
    let query = supabase.from("rooms").select("id, name, topic, language, region, cover_url, cover_template, theme, seats, locked, featured, home_order, status, listeners, score_today, created_at, owner:profiles!rooms_owner_id_fkey(username, public_id)");
    if (tab === "featured") query = query.eq("featured", true).eq("status", "open").order("home_order");
    else query = query.eq("status", tab).order("featured", { ascending: false }).order("home_order").order("listeners", { ascending: false });
    if (q.trim()) query = /^\d+$/.test(q.trim()) ? query.eq("id", Number(q.trim())) : query.ilike("name", `%${q.trim()}%`);
    const { data, error } = await query.limit(200);
    if (error) throw error;
    return data as unknown as Room[];
  }, [tab, q]);

  const tplImg = (id: string) => tpls.data?.find((t) => t.id === id)?.image_url;

  const save = async (r: Room) => {
    await rpc("admin_update_room", { p_room: r.id, p_patch: {
      name: r.name, cover_url: r.cover_url ?? "", cover_template: r.cover_template, theme: r.theme,
      featured: r.featured, home_order: r.home_order, status: r.status,
    } });
    setEdit(null); reload();
  };

  return (
    <Page title="Rooms & homepage" sub="Control what shows on the app's home screen: cover image, template, pinned order and status."
      actions={<button onClick={() => setOrdering(true)}>Reorder pinned rooms</button>}>
      <div className="row mb">
        <div className="tabs" style={{ margin: 0 }}>
          {(["open", "featured", "suspended", "closed"] as const).map((t) => <button key={t} className={"sm" + (t === tab ? " on" : "")} onClick={() => setTab(t)}>{t === "featured" ? "Pinned" : t[0].toUpperCase() + t.slice(1)}</button>)}
        </div>
        <input placeholder="Search name or room ID" value={q} onChange={(e) => setQ(e.target.value)} style={{ maxWidth: 260, marginLeft: "auto" }} />
      </div>
      {loading || err ? <Loading err={err} /> : !data?.length ? <Empty>No rooms</Empty> : (
        <div className="rcards">
          {data.map((r) => {
            const img = r.cover_url || tplImg(r.cover_template);
            return (
              <div key={r.id} className={"rc" + (r.featured ? " pin" : "")}>
                <div className="cv">
                  {img ? <img src={img} alt="" /> : <span>{r.cover_template}</span>}
                  <span className="tag row">{r.featured && <Badge tone="gold">Pinned #{r.home_order}</Badge>}{r.locked && <Badge>Locked</Badge>}</span>
                </div>
                <div className="bd">
                  <b>{r.name}</b>
                  <span className="muted sm">#{r.id} · {r.owner?.username} ({r.owner?.public_id}) · {r.topic} · {r.language}</span>
                  <div className="row"><span className="sm">{fmt(r.listeners)} listening</span><span className="sm muted">{fmt(r.score_today)} coins today</span></div>
                  <div className="row">
                    <button className="sm gold" onClick={() => setEdit({ ...r })}>Edit cover & placement</button>
                    <button className="sm ghost" onClick={() => run(async () => { await rpc("admin_update_room", { p_room: r.id, p_patch: { featured: !r.featured } }); reload(); }, r.featured ? "Unpinned" : "Pinned to homepage")}>{r.featured ? "Unpin" : "Pin"}</button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {edit && (
        <Modal title={`Room #${edit.id}`} onClose={() => setEdit(null)} wide>
          <form className="form" onSubmit={(e) => { e.preventDefault(); run(() => save(edit), "Room updated"); }}>
            <div className="grid g2">
              <div className="form">
                <Field label="Room name"><input value={edit.name} maxLength={30} onChange={(e) => setEdit({ ...edit, name: e.target.value })} /></Field>
                <ImageInput label="Homepage cover image (overrides the template)" bucket="room-covers" value={edit.cover_url} onChange={(v) => setEdit({ ...edit, cover_url: v })} />
                <Field label="Theme inside the room">
                  <select value={edit.theme} onChange={(e) => setEdit({ ...edit, theme: e.target.value })}>
                    {themes.data?.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
                  </select>
                </Field>
                <div className="row">
                  <Field label="Pinned on homepage"><Toggle on={edit.featured} onChange={(v) => setEdit({ ...edit, featured: v })} /></Field>
                  <Field label="Pin position (1 = first)"><input type="number" min={0} value={edit.home_order} onChange={(e) => setEdit({ ...edit, home_order: Number(e.target.value) })} /></Field>
                </div>
                <Field label="Status" hint="Suspended rooms disappear from the app and nobody can join.">
                  <select value={edit.status} onChange={(e) => setEdit({ ...edit, status: e.target.value })}>
                    <option value="open">Open</option><option value="suspended">Suspended</option><option value="closed">Closed</option>
                  </select>
                </Field>
              </div>
              <div className="form">
                <span className="lbl">Cover template (used when there is no cover image)</span>
                <div className="rcards" style={{ gridTemplateColumns: "repeat(auto-fill,minmax(110px,1fr))", gap: 8 }}>
                  {tpls.data?.map((t) => (
                    <button type="button" key={t.id} className={"rc" + (edit.cover_template === t.id ? " pin" : "")} style={{ padding: 0 }} onClick={() => setEdit({ ...edit, cover_template: t.id })}>
                      <div className="cv" style={{ fontSize: 13 }}>{t.image_url ? <img src={t.image_url} alt="" /> : t.name}</div>
                      <div className="sm" style={{ padding: 6 }}>{t.name}</div>
                    </button>
                  ))}
                </div>
                <small className="muted">Add templates or change their images on the Covers & themes page.</small>
              </div>
            </div>
            <div className="row end"><button type="button" className="ghost" onClick={() => setEdit(null)}>Cancel</button><button className="gold">Save</button></div>
          </form>
        </Modal>
      )}
      {ordering && <Reorder onClose={() => { setOrdering(false); reload(); }} />}
    </Page>
  );
}

function Reorder({ onClose }: { onClose: () => void }) {
  const run = useRun();
  const [list, setList] = useState<{ id: number; name: string }[] | null>(null);
  const [add, setAdd] = useState("");
  useAsync(async () => {
    const { data } = await supabase.from("rooms").select("id, name").eq("featured", true).eq("status", "open").order("home_order");
    setList(data ?? []);
  });
  const move = (i: number, d: number) => { if (!list) return; const l = [...list]; const j = i + d; if (j < 0 || j >= l.length) return; [l[i], l[j]] = [l[j], l[i]]; setList(l); };
  return (
    <Modal title="Pinned rooms order" onClose={onClose}>
      {!list ? <Loading /> : (
        <div className="form">
          <p className="muted sm" style={{ margin: 0 }}>These appear first on the homepage, top to bottom.</p>
          <ul className="order">
            {list.map((r, i) => (
              <li key={r.id}><span className="muted">{i + 1}</span><b>{r.name} <span className="muted sm">#{r.id}</span></b>
                <button className="sm ghost" onClick={() => move(i, -1)}>↑</button><button className="sm ghost" onClick={() => move(i, 1)}>↓</button>
                <button className="sm ghost danger" onClick={() => setList(list.filter((x) => x.id !== r.id))}>Remove</button></li>
            ))}
            {!list.length && <Empty>No pinned rooms</Empty>}
          </ul>
          <div className="row">
            <input placeholder="Room ID to pin" value={add} onChange={(e) => setAdd(e.target.value)} style={{ flex: 1 }} />
            <button onClick={() => run(async () => {
              const { data, error } = await supabase.from("rooms").select("id, name").eq("id", Number(add)).single();
              if (error || !data) throw new Error("Room not found");
              if (!list.some((x) => x.id === data.id)) setList([...list, data]);
              setAdd("");
            })}>Add</button>
          </div>
          <div className="row end"><button className="gold" onClick={() => run(async () => { await rpc("admin_reorder_featured", { p_rooms: list.map((r) => r.id) }); onClose(); }, "Homepage order saved")}>Save order</button></div>
        </div>
      )}
    </Modal>
  );
}
