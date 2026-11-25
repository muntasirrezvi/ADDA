// Sends a phone notification through Firebase Cloud Messaging (free) whenever a row is
// added to public.notifications. Hook it up with a Database Webhook:
//   table notifications, event INSERT, type Supabase Edge Function -> push,
//   add header  x-webhook-secret: <PUSH_WEBHOOK_SECRET>
import { adminClient, env, googleAccessToken, json, serve } from "../_shared/util.ts";

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== env("PUSH_WEBHOOK_SECRET")) return json({ error: "forbidden" }, 403);
  const { record } = await req.json();
  if (!record?.user_id) return json({ skipped: true });

  const db = adminClient();
  const { data: devices } = await db.from("devices").select("token").eq("user_id", record.user_id);
  if (!devices?.length) return json({ sent: 0 });

  const sa = env("FIREBASE_SERVICE_ACCOUNT_JSON");
  const projectId = JSON.parse(sa).project_id;
  const access = await googleAccessToken(sa, SCOPE);
  const data: Record<string, string> = {};
  for (const [k, v] of Object.entries(record.data ?? {})) data[k] = String(v);

  let sent = 0;
  for (const { token } of devices) {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: record.title, body: record.body ?? "" },
          data,
          android: { priority: data.type === "call" ? "HIGH" : "NORMAL", notification: { channel_id: data.type === "call" ? "calls" : "default" } },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    });
    if (res.ok) sent++;
    else if (res.status === 404 || res.status === 400) await db.from("devices").delete().eq("token", token); // app uninstalled
  }
  return json({ sent });
});
