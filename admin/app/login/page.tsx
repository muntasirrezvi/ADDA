"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { supabase } from "@/lib/supabase";
import { useToast } from "@/components/Shell";

export default function Login() {
  const [id, setId] = useState("");
  const [pw, setPw] = useState("");
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const router = useRouter();

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    let userId: string;
    if (id.includes("@")) {
      const { data, error } = await supabase.auth.signInWithPassword({ email: id.trim(), password: pw });
      if (error) { setBusy(false); return toast(error.message, true); }
      userId = data.user.id;
    } else {
      // phone sign-in goes through the login-phone function, which finds the account's email
      const { data, error } = await supabase.functions.invoke("login-phone", { body: { phone: id.trim(), password: pw } });
      if (error || !data?.access_token) { setBusy(false); return toast("Wrong phone number or password", true); }
      const { error: e2 } = await supabase.auth.setSession({ access_token: data.access_token, refresh_token: data.refresh_token });
      if (e2) { setBusy(false); return toast(e2.message, true); }
      userId = data.user.id;
    }
    const { data: p } = await supabase.from("profiles").select("role").eq("id", userId).single();
    if (!p || !["admin", "moderator", "agent"].includes(p.role)) {
      await supabase.auth.signOut();
      setBusy(false);
      return toast("This account is not an admin, moderator or coin agent", true);
    }
    router.replace("/");
  };

  return (
    <div className="login">
      <form className="card form" onSubmit={submit}>
        <div className="brand" style={{ padding: 0 }}>Adda<span>Owner console</span></div>
        <label className="field"><span className="lbl">Email or phone</span><input value={id} onChange={(e) => setId(e.target.value)} autoComplete="username" required /></label>
        <label className="field"><span className="lbl">Password</span><input type="password" value={pw} onChange={(e) => setPw(e.target.value)} autoComplete="current-password" required /></label>
        <button className="gold" disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button>
        <p className="muted sm" style={{ margin: 0 }}>For the owner, moderators and coin agents.</p>
      </form>
    </div>
  );
}
