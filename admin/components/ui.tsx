"use client";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { uploadPublic } from "@/lib/supabase";
import { useRun } from "./Shell";

export function Page({ title, sub, actions, children }: { title: string; sub?: string; actions?: ReactNode; children: ReactNode }) {
  return (
    <div className="page">
      <header className="ph">
        <div><h1>{title}</h1>{sub && <p className="muted">{sub}</p>}</div>
        {actions && <div className="row">{actions}</div>}
      </header>
      {children}
    </div>
  );
}

export function Modal({ title, onClose, children, wide }: { title: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  useEffect(() => {
    const k = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, [onClose]);
  return (
    <div className="modal" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className={"card mbox" + (wide ? " wide" : "")}>
        <div className="mh"><h3>{title}</h3><button className="ghost sm" onClick={onClose}>Close</button></div>
        {children}
      </div>
    </div>
  );
}

export function Badge({ children, tone = "" }: { children: ReactNode; tone?: "" | "gold" | "green" | "red" | "dim" }) {
  return <span className={"badge " + tone}>{children}</span>;
}

export function Empty({ children = "Nothing here yet" }: { children?: ReactNode }) {
  return <div className="empty">{children}</div>;
}

/** Image picker that uploads straight to storage and returns the public URL. */
export function ImageInput({ value, onChange, bucket, accept = "image/*", label = "Image" }:
  { value?: string | null; onChange: (url: string | null) => void; bucket: string; accept?: string; label?: string }) {
  const ref = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const run = useRun();
  const isImg = !value || /\.(png|jpe?g|webp|gif|svg)(\?|$)/i.test(value);
  return (
    <div className="imgin">
      <div className="thumb">
        {value ? (isImg ? <img src={value} alt="" /> : <span className="muted sm">file</span>) : <span className="muted sm">none</span>}
      </div>
      <div className="col">
        <span className="lbl">{label}</span>
        <div className="row">
          <button type="button" className="sm" disabled={busy} onClick={() => ref.current?.click()}>{busy ? "Uploading…" : value ? "Replace" : "Upload"}</button>
          {value && <button type="button" className="ghost sm" onClick={() => onChange(null)}>Remove</button>}
        </div>
      </div>
      <input ref={ref} type="file" accept={accept} hidden onChange={async (e) => {
        const f = e.target.files?.[0]; e.target.value = "";
        if (!f) return;
        setBusy(true);
        await run(async () => onChange(await uploadPublic(bucket, f)));
        setBusy(false);
      }} />
    </div>
  );
}

export function Field({ label, children, hint }: { label: string; children: ReactNode; hint?: string }) {
  return <label className="field"><span className="lbl">{label}</span>{children}{hint && <small className="muted">{hint}</small>}</label>;
}

export function Toggle({ on, onChange, label }: { on: boolean; onChange: (v: boolean) => void; label?: string }) {
  return (
    <button type="button" className={"toggle" + (on ? " on" : "")} onClick={() => onChange(!on)} aria-pressed={on}>
      <i />{label && <span>{label}</span>}
    </button>
  );
}

export function useAsync<T>(fn: () => Promise<T>, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [n, setN] = useState(0);
  useEffect(() => {
    let alive = true;
    setLoading(true);
    fn().then((d) => alive && (setData(d), setErr(null))).catch((e) => alive && setErr(e?.message || String(e))).finally(() => alive && setLoading(false));
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, n]);
  return { data, loading, err, reload: () => setN((x) => x + 1) };
}

export function Loading({ err }: { err?: string | null }) {
  return err ? <div className="empty bad">{err}</div> : <div className="empty"><div className="spinner" /></div>;
}
