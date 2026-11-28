import type { Metadata } from "next";
import Legal from "@/components/Legal";

export const metadata: Metadata = { title: "Adda — Terms of Service", robots: { index: true, follow: true } };

export default function Page() {
  return <Legal kind="terms" />;
}
