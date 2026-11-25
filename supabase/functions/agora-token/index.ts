// POST { kind: "room", id: 201 }  or  { kind: "call", id: "<call uuid>" }
// Returns an Agora RTC token for the signed-in user.
// Rooms: users on a seat get a speaker token, everyone else a listener token.
//        The app asks again after taking or leaving a seat and calls renewToken().
// Calls: only the caller and callee, while the call is ringing or active.
import agora from "npm:agora-token@2.0.7";
import { adminClient, env, HttpError, json, requireUser, serve } from "../_shared/util.ts";

const { RtcTokenBuilder, RtcRole } = agora;
const TTL = 3600; // seconds

serve(async (req) => {
  const user = await requireUser(req);
  const { kind, id } = await req.json().catch(() => ({}));
  const db = adminClient();

  const { data: me } = await db.from("profiles").select("public_id, banned_until, deleted_at").eq("id", user.id).single();
  if (!me || me.deleted_at || (me.banned_until && new Date(me.banned_until) > new Date())) throw new HttpError(403, "Account restricted");

  let channel: string;
  let role = RtcRole.SUBSCRIBER;

  if (kind === "room") {
    const roomId = Number(id);
    const { data: room } = await db.from("rooms").select("id, status, owner_id").eq("id", roomId).single();
    if (!room || room.status !== "open") throw new HttpError(404, "Room is not available");
    const { data: member } = await db.from("room_members").select("role").eq("room_id", roomId).eq("user_id", user.id).maybeSingle();
    if (!member || member.role === "banned") throw new HttpError(403, "Join the room first");
    const { data: seat } = await db.from("room_seats").select("seat, muted").eq("room_id", roomId).eq("user_id", user.id).maybeSingle();
    if (seat && !seat.muted) role = RtcRole.PUBLISHER;
    channel = `room_${roomId}`;
  } else if (kind === "call") {
    const { data: call } = await db.from("calls").select("channel, status, caller_id, callee_id").eq("id", String(id)).single();
    if (!call || ![call.caller_id, call.callee_id].includes(user.id)) throw new HttpError(404, "Call not found");
    if (!["ringing", "active"].includes(call.status)) throw new HttpError(410, "Call has ended");
    channel = call.channel;
    role = RtcRole.PUBLISHER;
  } else {
    throw new HttpError(400, "kind must be room or call");
  }

  const uid = Number(me.public_id);
  const token = RtcTokenBuilder.buildTokenWithUid(env("AGORA_APP_ID"), env("AGORA_APP_CERTIFICATE"), channel, uid, role, TTL, TTL);
  return json({
    appId: env("AGORA_APP_ID"),
    channel,
    uid,
    token,
    role: role === RtcRole.PUBLISHER ? "speaker" : "listener",
    expiresAt: Math.floor(Date.now() / 1000) + TTL,
  });
});
