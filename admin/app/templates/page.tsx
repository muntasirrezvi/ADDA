"use client";
import { useState } from "react";
import Catalog from "@/components/Catalog";
import { Page } from "@/components/ui";

export default function Templates() {
  const [tab, setTab] = useState<"covers" | "themes">("covers");
  return (
    <Page title="Covers & themes" sub="Cover templates are what creators pick when they make a room. Themes are the backgrounds inside a room; give one a price to make it premium.">
      <div className="tabs">
        <button className={tab === "covers" ? "on" : ""} onClick={() => setTab("covers")}>Room cover templates</button>
        <button className={tab === "themes" ? "on" : ""} onClick={() => setTab("themes")}>Room themes</button>
      </div>
      {tab === "covers" ? (
        <Catalog key="covers" table="room_cover_templates" title="cover template" cols={[
          { key: "image_url", label: "Image", type: "image", bucket: "room-covers", hint: "Leave empty to use the app's built-in illustration" },
          { key: "id", label: "ID", required: true, hint: "Short code, e.g. lantern. Cannot be changed later." },
          { key: "name", label: "Name", required: true },
          { key: "price", label: "Price (coins)", type: "number", hint: "0 = free for everyone" },
          { key: "sort", label: "Order", type: "number" },
          { key: "active", label: "Active", type: "bool" },
        ]} />
      ) : (
        <Catalog key="themes" table="room_themes" title="theme" cols={[
          { key: "image_url", label: "Background", type: "image", bucket: "room-covers" },
          { key: "id", label: "ID", required: true },
          { key: "name", label: "Name", required: true },
          { key: "price", label: "Price (coins)", type: "number", hint: "0 = free. Paid themes are bought once and kept." },
          { key: "sort", label: "Order", type: "number" },
          { key: "active", label: "Active", type: "bool" },
        ]} />
      )}
    </Page>
  );
}
