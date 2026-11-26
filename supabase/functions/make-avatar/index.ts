// POST { image: "<base64 jpeg/png, max 512x512>", style: "3d" | "anime" | "comic" | "royal" }
// Turns the user's photo into a stylised avatar with FLUX.2 [klein] on Cloudflare Workers AI
// (free daily allowance), stores it in the avatars bucket and returns its public URL.
// Secrets: CF_ACCOUNT_ID, CF_API_TOKEN (Cloudflare → Workers AI → API token with "Workers AI: Read/Edit").
import { adminClient, env, HttpError, json, requireUser, serve } from "../_shared/util.ts";

const MODEL = "@cf/black-forest-labs/flux-2-klein-4b";

const KEEP = "Keep the same person: same face shape, eyes, nose, hairstyle, hair colour, skin tone, facial hair, glasses and expression.";
const STYLES: Record<string, string> = {
  "3d": `Turn the person in image 0 into a fancy 3D animated movie character portrait. ${KEEP} Glossy realistic 3D render with a playful cartoon vibe, big expressive eyes, soft subsurface skin, detailed hair strands, cinematic rim lighting, smooth colourful gradient background, head and shoulders, centered, high detail.`,
  anime: `Turn the person in image 0 into a beautiful modern anime character portrait. ${KEEP} Clean line art, rich cel shading, sparkling eyes, vibrant colours, soft glowing background, head and shoulders, centered, high detail.`,
  comic: `Turn the person in image 0 into a bold comic book hero portrait. ${KEEP} Realistic proportions with a cartoon vibe, strong ink outlines, halftone shading, punchy colours, dynamic light, head and shoulders, centered.`,
  royal: `Turn the person in image 0 into a regal fantasy portrait with a cartoon vibe. ${KEEP} Elegant gold-trimmed outfit, warm candle lighting, painterly yet realistic 3D style, luxurious dark background with golden bokeh, head and shoulders, centered.`,
};

function b64ToBytes(b64: string): Uint8Array {
  const clean = b64.replace(/^data:[^;]+;base64,/, "");
  const bin = atob(clean);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

serve(async (req) => {
  const user = await requireUser(req);
  const { image, style = "3d" } = await req.json().catch(() => ({}));
  if (typeof image !== "string" || image.length < 100) throw new HttpError(400, "Choose a photo first");
  if (image.length > 1_500_000) throw new HttpError(413, "Photo is too large");
  const prompt = STYLES[style];
  if (!prompt) throw new HttpError(400, "Unknown style");

  const db = adminClient();
  const { data: me } = await db.from("profiles").select("banned_until, deleted_at").eq("id", user.id).single();
  if (!me || me.deleted_at || (me.banned_until && new Date(me.banned_until) > new Date())) throw new HttpError(403, "Account restricted");

  const { data: settings } = await db.from("app_settings").select("key, value").in("key", ["ai_avatar_enabled", "ai_avatar_daily_limit"]);
  const s = Object.fromEntries((settings ?? []).map((r) => [r.key, r.value]));
  if (s.ai_avatar_enabled === false) throw new HttpError(403, "AI avatars are switched off right now");
  const limit = Number(s.ai_avatar_daily_limit ?? 3);
  const since = new Date();
  since.setUTCHours(0, 0, 0, 0);
  const { count } = await db.from("ai_avatars").select("id", { count: "exact", head: true }).eq("user_id", user.id).gte("created_at", since.toISOString());
  if ((count ?? 0) >= limit) throw new HttpError(429, `You can make ${limit} avatars a day. Try again tomorrow.`);

  const account = env("CF_ACCOUNT_ID", false);
  const token = env("CF_API_TOKEN", false);
  if (!account || !token) throw new HttpError(503, "AI avatars are not set up yet");

  const photo = b64ToBytes(image);
  const form = new FormData();
  form.append("prompt", prompt);
  form.append("input_image_0", new Blob([photo], { type: "image/jpeg" }), "photo.jpg");
  form.append("width", "768");
  form.append("height", "768");
  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}/ai/run/${MODEL}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: form,
  });
  const body = await res.json().catch(() => null) as { success?: boolean; result?: { image?: string }; errors?: { message?: string }[] } | null;
  const out = body?.result?.image;
  if (!res.ok || !out) {
    console.error("cloudflare", res.status, JSON.stringify(body?.errors ?? body));
    if (res.status === 429) throw new HttpError(429, "The avatar studio is busy today. Please try again later.");
    throw new HttpError(502, "Could not create the avatar. Try a clearer, front-facing photo.");
  }

  const bytes = b64ToBytes(out);
  const isPng = bytes[0] === 0x89 && bytes[1] === 0x50;
  const path = `${user.id}/ai-${Date.now()}.${isPng ? "png" : "jpg"}`;
  const up = await db.storage.from("avatars").upload(path, bytes, { contentType: isPng ? "image/png" : "image/jpeg", upsert: false });
  if (up.error) throw new Error(up.error.message);
  const url = db.storage.from("avatars").getPublicUrl(path).data.publicUrl;
  await db.from("ai_avatars").insert({ user_id: user.id, image_url: url, style });
  return json({ url, left: Math.max(0, limit - (count ?? 0) - 1) });
});
