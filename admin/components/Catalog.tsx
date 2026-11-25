"use client";
// One editor for every simple catalogue table: gifts, coin packs, music, cover templates, themes, banners.
import { useState } from "react";
import { supabase, fmt } from "@/lib/supabase";
import { useRun } from "./Shell";
import { Badge, Empty, Field, ImageInput, Loading, Modal, Toggle, useAsync } from "./ui";

export type Col = {
  key: string;
  label: string;
  type?: "text" | "number" | "bool" | "image" | "file" | "select" | "datetime" | "color" | "textarea";
  bucket?: string;
  accept?: string;
  options?: string[];
  list?: boolean;      // show in the table
  required?: boolean;
  hint?: string;
  readOnlyOnEdit?: boolean;
  def?: unknown;
};

type Row = Record<string, unknown>;

export default function Catalog({ table, cols, pk = "id", order = "sort", autoId = false, title }:
  { table: string; cols: Col[]; pk?: string; order?: string; autoId?: boolean; title: string }) {
  const run = useRun();
  const { data, loading, err, reload } = useAsync(async () => {
    const { data, error } = await supabase.from(table).select("*").order(order, { ascending: true });
    if (error) throw error;
    return data as Row[];
  }, [table]);
  const [edit, setEdit] = useState<{ row: Row; isNew: boolean } | null>(null);

  const blank = () => Object.fromEntries(cols.map((c) => [c.key, c.def ?? (c.type === "bool" ? true : c.type === "number" ? 0 : c.type === "select" ? c.options?.[0] : null)]));

  const save = async () => {
    if (!edit) return;
    const row = { ...edit.row };
    for (const c of cols) {
      if (c.required && (row[c.key] === null || row[c.key] === "" || row[c.key] === undefined)) throw new Error(`${c.label} is required`);
      if (c.type === "number" && row[c.key] !== null && row[c.key] !== "") row[c.key] = Number(row[c.key]);
      if ((c.type === "text" || c.type === "datetime" || c.type === "textarea") && row[c.key] === "") row[c.key] = null;
    }
    if (autoId && edit.isNew) delete row[pk];
    const q = edit.isNew ? supabase.from(table).insert(row) : supabase.from(table).update(row).eq(pk, edit.row[pk] as string);
    const { error } = await q;
    if (error) throw error;
    setEdit(null);
    reload();
  };

  const remove = async (r: Row) => {
    if (!confirm(`Delete "${r.name ?? r.title ?? r[pk]}"? Hiding it (turning Active off) is usually safer.`)) return;
    const { error } = await supabase.from(table).delete().eq(pk, r[pk] as string);
    if (error) throw error;
    reload();
  };

  const listCols = cols.filter((c) => c.list !== false);
  const cell = (c: Col, v: unknown) => {
    if (c.type === "bool") return v ? <Badge tone="green">Yes</Badge> : <Badge tone="dim">No</Badge>;
    if (c.type === "image") return v ? <img className="mini" src={String(v)} alt="" /> : <span className="muted">built-in</span>;
    if (c.type === "file") return v ? <a href={String(v)} target="_blank" rel="noreferrer">open</a> : "—";
    if (c.type === "number") return fmt(v as number);
    if (c.type === "color") return <span className="swatch" style={{ background: String(v || "#000") }} />;
    if (c.type === "datetime") return v ? new Date(String(v)).toLocaleString() : "—";
    return v === null || v === undefined || v === "" ? "—" : String(v);
  };

  return (
    <>
      <div className="row end mb"><button className="gold" onClick={() => setEdit({ row: blank(), isNew: true })}>+ Add</button></div>
      {loading || err ? <Loading err={err} /> : !data?.length ? <Empty /> : (
        <div className="card tw">
          <table>
            <thead><tr>{listCols.map((c) => <th key={c.key}>{c.label}</th>)}<th /></tr></thead>
            <tbody>
              {data.map((r) => (
                <tr key={String(r[pk])}>
                  {listCols.map((c) => <td key={c.key}>{cell(c, r[c.key])}</td>)}
                  <td className="act">
                    <button className="sm" onClick={() => setEdit({ row: { ...r }, isNew: false })}>Edit</button>
                    <button className="ghost sm danger" onClick={() => run(() => remove(r), "Deleted")}>Delete</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {edit && (
        <Modal title={(edit.isNew ? "New " : "Edit ") + title} onClose={() => setEdit(null)}>
          <form className="form" onSubmit={(e) => { e.preventDefault(); run(save, "Saved"); }}>
            {cols.map((c) => {
              const v = edit.row[c.key];
              const set = (nv: unknown) => setEdit({ ...edit, row: { ...edit.row, [c.key]: nv } });
              if (autoId && c.key === pk) return null;
              if (c.type === "image" || c.type === "file")
                return <ImageInput key={c.key} label={c.label} bucket={c.bucket!} accept={c.accept} value={v as string} onChange={set} />;
              if (c.type === "bool") return <Field key={c.key} label={c.label} hint={c.hint}><Toggle on={!!v} onChange={set} /></Field>;
              if (c.type === "select")
                return <Field key={c.key} label={c.label} hint={c.hint}><select value={String(v ?? "")} onChange={(e) => set(e.target.value)}>{c.options!.map((o) => <option key={o}>{o}</option>)}</select></Field>;
              if (c.type === "textarea")
                return <Field key={c.key} label={c.label} hint={c.hint}><textarea value={String(v ?? "")} onChange={(e) => set(e.target.value)} /></Field>;
              const disabled = !edit.isNew && (c.readOnlyOnEdit || c.key === pk);
              const type = c.type === "number" ? "number" : c.type === "color" ? "color" : c.type === "datetime" ? "datetime-local" : "text";
              const shown = c.type === "datetime" && v ? new Date(String(v)).toISOString().slice(0, 16) : String(v ?? "");
              return (
                <Field key={c.key} label={c.label} hint={c.hint}>
                  <input type={type} value={shown} disabled={disabled} required={c.required} step="any"
                    onChange={(e) => set(c.type === "datetime" ? (e.target.value ? new Date(e.target.value).toISOString() : null) : e.target.value)} />
                </Field>
              );
            })}
            <div className="row end"><button type="button" className="ghost" onClick={() => setEdit(null)}>Cancel</button><button className="gold">Save</button></div>
          </form>
        </Modal>
      )}
    </>
  );
}
