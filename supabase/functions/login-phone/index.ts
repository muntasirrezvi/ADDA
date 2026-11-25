// POST { phone: "+8801712345678", password: "..." }  ->  Supabase session
// Lets people sign in with phone + password without paying for SMS: accounts are created with
// email + password (phone saved on the profile), and this function finds the email for a phone.
import { createClient } from "npm:@supabase/supabase-js@2";
import { adminClient, env, HttpError, json, serve } from "../_shared/util.ts";

const normalize = (p: string) => p.replace(/[\s\-()]/g, "");

serve(async (req) => {
  const { phone, password } = await req.json().catch(() => ({}));
  if (!phone || !password) throw new HttpError(400, "Phone and password are required");
  const wrong = new HttpError(400, "Wrong phone number or password");

  const { data: row } = await adminClient().from("profile_private").select("email").eq("phone", normalize(String(phone))).maybeSingle();
  if (!row?.email) {
    await new Promise((r) => setTimeout(r, 400)); // same timing whether or not the phone exists
    throw wrong;
  }
  const anon = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), { auth: { persistSession: false } });
  const { data, error } = await anon.auth.signInWithPassword({ email: row.email, password: String(password) });
  if (error || !data.session) throw wrong;
  const s = data.session;
  return json({ access_token: s.access_token, refresh_token: s.refresh_token, expires_at: s.expires_at, user: { id: s.user.id } });
});
