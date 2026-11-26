"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import { supabase } from "@/lib/supabase";

type Me = { id: string; username: string; role: "admin" | "moderator" | "agent" };
const MeCtx = createContext<Me | null>(null);
export const useMe = () => useContext(MeCtx);

type Toast = { id: number; text: string; bad?: boolean };
const ToastCtx = createContext<(text: string, bad?: boolean) => void>(() => {});
export const useToast = () => useContext(ToastCtx);

const NAV: [string, string, string][] = [
  ["/", "Dashboard", "M3 13h8V3H3zm10 8h8V11h-8zM3 21h8v-6H3zm10-18v6h8V3z"],
  ["/rooms/", "Rooms & homepage", "M4 5h16v10H4zM8 19h8"],
  ["/homepage/", "Banners & layout", "M3 5h18v6H3zm0 9h8v5H3zm10 0h8v5h-8z"],
  ["/templates/", "Covers & themes", "M4 4h16v16H4zM4 15l5-5 4 4 3-3 4 4"],
  ["/users/", "Users", "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm-8 9a8 8 0 0 1 16 0"],
  ["/topups/", "Top-up orders", "M12 2v20M5 9l7-7 7 7M4 21h16"],
  ["/payments/", "Payments", "M3 6h18v12H3zM3 10h18"],
  ["/ledger/", "Coin ledger", "M5 4h14v16H5zM9 8h6M9 12h6M9 16h3"],
  ["/gifts/", "Gifts", "M4 10h16v10H4zM2 7h20v3H2zM12 7v13"],
  ["/packs/", "Coin packs", "M12 3l9 5-9 5-9-5zM3 13l9 5 9-5"],
  ["/agents/", "Coin agents", "M16 11a3 3 0 1 0 0-6M8 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm-6 9a6 6 0 0 1 12 0m4 0a6 6 0 0 0-3-5"],
  ["/reports/", "Reports", "M5 21V4h11l-1 4h5l-2 7H5"],
  ["/verifications/", "Verifications", "M12 2l8 4v6c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V6zM8 12l3 3 5-6"],
  ["/payouts/", "Withdrawals", "M12 3v18M17 7H9.5a3 3 0 0 0 0 6h5a3 3 0 0 1 0 6H6"],
  ["/transfers/", "Transfers", "M7 7h13l-3-3M17 17H4l3 3"],
  ["/reels/", "Reels", "M4 4h16v16H4zM10 9l5 3-5 3z"],
  ["/music/", "Music", "M9 18V5l11-2v13M9 18a3 3 0 1 1-6 0 3 3 0 0 1 6 0zm11-2a3 3 0 1 1-6 0 3 3 0 0 1 6 0z"],
  ["/broadcast/", "Broadcast", "M3 11l15-6v14L3 13zM7 13v5"],
  ["/settings/", "Settings", "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"],
  ["/audit/", "Audit log", "M12 8v4l3 2M21 12a9 9 0 1 1-9-9"],
];

const AGENT_PAGES = ["/topups/", "/agents/"];

export function Icon({ d, size = 18 }: { d: string; size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d={d} />
    </svg>
  );
}

export default function Shell({ children }: { children: ReactNode }) {
  const path = usePathname();
  const router = useRouter();
  const [me, setMe] = useState<Me | null | undefined>(undefined);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [open, setOpen] = useState(false);

  const toast = useCallback((text: string, bad = false) => {
    const id = Date.now() + Math.random();
    setToasts((t) => [...t, { id, text, bad }]);
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 4200);
  }, []);

  useEffect(() => {
    const check = async () => {
      const { data } = await supabase.auth.getUser();
      if (!data.user) return setMe(null);
      const { data: p } = await supabase.from("profiles").select("id, username, role").eq("id", data.user.id).single();
      setMe(p && ["admin", "moderator", "agent"].includes(p.role) ? (p as Me) : null);
    };
    check();
    const { data: sub } = supabase.auth.onAuthStateChange(() => check());
    return () => sub.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (me === null && path !== "/login/") router.replace("/login/");
  }, [me, path, router]);
  useEffect(() => setOpen(false), [path]);
  // agents only see their own top-up desk
  useEffect(() => {
    if (me?.role === "agent" && !AGENT_PAGES.includes(path)) router.replace("/topups/");
  }, [me, path, router]);

  const toastView = (
    <div className="toasts">{toasts.map((t) => <div key={t.id} className={"toast" + (t.bad ? " bad" : "")}>{t.text}</div>)}</div>
  );

  if (path === "/login/") return <ToastCtx.Provider value={toast}>{children}{toastView}</ToastCtx.Provider>;
  if (!me || (me.role === "agent" && !AGENT_PAGES.includes(path))) return <div className="center"><div className="spinner" /></div>;

  return (
    <MeCtx.Provider value={me}>
      <ToastCtx.Provider value={toast}>
        <div className="layout">
          <aside className={open ? "open" : ""}>
            <div className="brand">Adda<span>Console</span></div>
            <nav>
              {NAV.filter(([href]) => me.role !== "agent" || AGENT_PAGES.includes(href)).map(([href, label, d]) => (
                <Link key={href} href={href} className={path === href ? "on" : ""}><Icon d={d} />{label}</Link>
              ))}
            </nav>
            <div className="who">
              <div><b>{me.username}</b><small>{me.role}</small></div>
              <button className="ghost sm" onClick={() => supabase.auth.signOut()}>Sign out</button>
            </div>
          </aside>
          <div className="scrim" onClick={() => setOpen(false)} />
          <main>
            <button className="menu ghost" onClick={() => setOpen(true)} aria-label="Menu"><Icon d="M4 6h16M4 12h16M4 18h16" /></button>
            {children}
          </main>
        </div>
        {toastView}
      </ToastCtx.Provider>
    </MeCtx.Provider>
  );
}

/** Small helper so pages can run an action and show success / error toasts. */
export function useRun() {
  const toast = useToast();
  return useCallback(async (fn: () => Promise<unknown>, ok?: string) => {
    try {
      await fn();
      if (ok) toast(ok);
      return true;
    } catch (e) {
      toast((e as { message?: string })?.message || "Something went wrong", true);
      return false;
    }
  }, [toast]);
}
