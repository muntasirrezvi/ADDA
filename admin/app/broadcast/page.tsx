"use client";
import { useState } from "react";
import { rpc } from "@/lib/supabase";
import { useMe, useRun } from "@/components/Shell";
import { Field, Page } from "@/components/ui";

export default function Broadcast() {
  const run = useRun();
  const me = useMe();
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [action, setAction] = useState("");
  return (
    <Page title="Broadcast" sub="Send a notification to every user. It appears in the app's notification centre and as a phone notification once push is set up.">
      <form className="card form" style={{ maxWidth: 560 }} onSubmit={(e) => {
        e.preventDefault();
        if (!confirm("Send this to every user?")) return;
        run(async () => { const n = await rpc<number>("admin_broadcast", { p_title: title, p_body: body, p_data: action ? { type: "promo", action } : { type: "promo" } }); setTitle(""); setBody(""); alert(`Sent to ${n} users`); });
      }}>
        <Field label="Title"><input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={60} required /></Field>
        <Field label="Message"><textarea value={body} onChange={(e) => setBody(e.target.value)} maxLength={200} required /></Field>
        <Field label="Opens (optional)" hint="room:201 · events · topup:first · invite"><input value={action} onChange={(e) => setAction(e.target.value)} /></Field>
        <div className="row end"><button className="gold" disabled={me?.role !== "admin"}>Send to everyone</button></div>
      </form>
    </Page>
  );
}
