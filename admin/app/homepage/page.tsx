"use client";
import { useEffect, useState } from "react";
import Catalog from "@/components/Catalog";
import { rpc, supabase } from "@/lib/supabase";
import { useMe, useRun } from "@/components/Shell";
import { Page } from "@/components/ui";

const SECTIONS: Record<string, string> = { banners: "Banner carousel", stories: "Following stories", events: "Upcoming events", rooms: "Room list" };

export default function Homepage() {
  const run = useRun();
  const me = useMe();
  const [layout, setLayout] = useState<string[] | null>(null);
  useEffect(() => {
    supabase.from("app_settings").select("value").eq("key", "home_layout").maybeSingle()
      .then(({ data }) => setLayout(Array.isArray(data?.value) ? data!.value : ["banners", "stories", "events", "rooms"]));
  }, []);
  const move = (i: number, d: number) => { if (!layout) return; const l = [...layout]; const j = i + d; if (j < 0 || j >= l.length) return; [l[i], l[j]] = [l[j], l[i]]; setLayout(l); };
  const hidden = Object.keys(SECTIONS).filter((k) => !layout?.includes(k));

  return (
    <Page title="Banners & layout" sub="The carousel at the top of the app and the order of the home screen sections.">
      <div className="card mb">
        <h3 className="mb">Home screen sections</h3>
        {layout && (
          <>
            <ul className="order mb">
              {layout.map((k, i) => (
                <li key={k}><span className="muted">{i + 1}</span><b>{SECTIONS[k] ?? k}</b>
                  <button className="sm ghost" onClick={() => move(i, -1)}>↑</button><button className="sm ghost" onClick={() => move(i, 1)}>↓</button>
                  {k !== "rooms" && <button className="sm ghost danger" onClick={() => setLayout(layout.filter((x) => x !== k))}>Hide</button>}</li>
              ))}
            </ul>
            <div className="row">
              {hidden.map((k) => <button key={k} className="sm" onClick={() => setLayout([...layout, k])}>+ {SECTIONS[k]}</button>)}
              <button className="gold sm" style={{ marginLeft: "auto" }} disabled={me?.role !== "admin"}
                onClick={() => run(() => rpc("admin_set_setting", { p_key: "home_layout", p_value: layout }), "Layout saved")}>Save layout</button>
            </div>
          </>
        )}
      </div>
      <h3 className="mb">Banners</h3>
      <Catalog table="banners" title="banner" autoId cols={[
        { key: "image_url", label: "Image (wide, about 1200×500)", type: "image", bucket: "banners" },
        { key: "title", label: "Title", required: true },
        { key: "subtitle", label: "Subtitle" },
        { key: "cta_label", label: "Button text" },
        { key: "action", label: "Opens", hint: "room:201 · events · invite · leaderboard · topup:first · vip · url:https://…" },
        { key: "color_from", label: "Gradient from", type: "color", list: false },
        { key: "color_to", label: "Gradient to", type: "color", list: false },
        { key: "starts_at", label: "Show from", type: "datetime", list: false },
        { key: "ends_at", label: "Show until", type: "datetime" },
        { key: "sort", label: "Order", type: "number" },
        { key: "active", label: "Active", type: "bool" },
      ]} />
    </Page>
  );
}
