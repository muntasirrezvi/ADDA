"use client";
import Catalog from "@/components/Catalog";
import { Page } from "@/components/ui";

export default function Gifts() {
  return (
    <Page title="Gifts" sub="Prices are in coins (500,000 coins = $1). Event gifts can be limited to a date range.">
      <Catalog table="gifts" title="gift" cols={[
        { key: "icon_url", label: "Icon", type: "image", bucket: "gifts" },
        { key: "id", label: "ID", required: true, hint: "Short code, e.g. rose" },
        { key: "name", label: "Name", required: true },
        { key: "price", label: "Price (coins)", type: "number", required: true },
        { key: "tier", label: "Tier", type: "select", options: ["classic", "luxury", "exclusive", "event"] },
        { key: "animation_url", label: "Full-screen animation (Lottie JSON, WebP or MP4)", type: "file", bucket: "gifts", accept: ".json,.webp,.gif,.mp4,application/json,image/*,video/mp4", list: false },
        { key: "starts_at", label: "Available from", type: "datetime", list: false },
        { key: "ends_at", label: "Available until", type: "datetime" },
        { key: "sort", label: "Order", type: "number" },
        { key: "active", label: "Active", type: "bool" },
      ]} />
    </Page>
  );
}
