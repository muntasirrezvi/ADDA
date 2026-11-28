import type { Metadata } from "next";
import Legal from "@/components/Legal";

export const metadata: Metadata = { title: "Adda — Privacy Policy", robots: { index: true, follow: true } };

export default function Page() {
  return <Legal kind="privacy" />;
}
