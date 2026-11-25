"use client";
import Catalog from "@/components/Catalog";
import { Page } from "@/components/ui";

export default function Packs() {
  return (
    <Page title="Coin packs" sub="BDT price is charged through SSLCommerz (bKash, Nagad, cards). The Google Play price is set on the product in Play Console; the product ID must match. Users also get up to 5% for their recharge tier and up to 3% for recent gifting, capped at 20% in total.">
      <Catalog table="coin_packs" title="coin pack" cols={[
        { key: "id", label: "ID", required: true },
        { key: "coins", label: "Coins", type: "number", required: true },
        { key: "usd", label: "USD", type: "number", required: true },
        { key: "bdt", label: "BDT (before discount)", type: "number", required: true },
        { key: "discount_pct", label: "Pack discount %", type: "number", hint: "0 to 20" },
        { key: "play_product_id", label: "Google Play product ID" },
        { key: "sort", label: "Order", type: "number" },
        { key: "active", label: "Active", type: "bool" },
      ]} />
    </Page>
  );
}
