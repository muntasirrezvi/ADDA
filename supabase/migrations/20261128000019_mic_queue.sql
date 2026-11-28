-- Yari-style mic rules:
--  * each room has a mic mode: 'free' (anyone taps an empty seat) or 'apply' (listeners apply, host/admins approve)
--  * host/admins can invite a listener to the mic; the listener gets a popup + notification and accepts or declines
--  * approving / accepting puts the person straight on a free seat
--  * a seat muted by an admin stays muted until an admin unmutes it

alter table public.rooms add column if not exists mic_mode text not null default 'free';
do $$ begin
  alter table public.rooms add constraint rooms_mic_mode_check check (mic_mode in ('free','apply'));
exception when duplicate_object then null; end $$;

create table if not exists public.mic_requests (
  id bigint generated always as identity primary key,
  room_id bigint not null references public.rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('apply','invite')),
  seat int,
  by_user uuid references public.profiles(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  answered_at timestamptz
);
create unique index if not exists mic_requests_one_pending on public.mic_requests(room_id, user_id, kind) where status = 'pending';
create index if not exists mic_requests_room_idx on public.mic_requests(room_id, status, id);

alter table public.mic_requests enable row level security;
do $$ begin
  create policy mic_requests_read on public.mic_requests for select to authenticated
    using (user_id = auth.uid() or public.is_room_admin(room_id));
exception when duplicate_object then null; end $$;
-- writes only through the functions below
revoke all on public.mic_requests from anon, authenticated;
grant select on public.mic_requests to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.mic_requests;
exception when duplicate_object then null; end $$;

-- lowest free, unlocked guest seat (or the wanted one when it is free)
create or replace function public._free_seat(p_room bigint, p_want int default null)
returns int language sql stable security definer set search_path = public as $$
  select seat from room_seats
   where room_id = p_room and seat between 1 and (select seats from rooms where id = p_room)
     and user_id is null and not locked
   order by (seat = p_want) desc nulls last, seat
   limit 1
$$;

create or replace function public._put_on_mic(p_room bigint, p_user uuid, p_want int default null)
returns int language plpgsql security definer set search_path = public as $$
declare s int;
begin
  if exists (select 1 from room_seats where room_id = p_room and user_id = p_user) then
    return (select seat from room_seats where room_id = p_room and user_id = p_user);
  end if;
  s := _free_seat(p_room, p_want);
  if s is null then raise exception 'No free seat on the mic right now'; end if;
  update room_seats set user_id = p_user, muted = false where room_id = p_room and seat = s and user_id is null;
  if not found then raise exception 'No free seat on the mic right now'; end if;
  return s;
end $$;

create or replace function public.set_mic_mode(p_room bigint, p_mode text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_room_admin(p_room) then raise exception 'room admins only'; end if;
  if p_mode not in ('free','apply') then raise exception 'bad mic mode'; end if;
  update rooms set mic_mode = p_mode where id = p_room;
  insert into room_messages(room_id, user_id, kind, body) values (p_room, auth.uid(), 'system',
    case when p_mode = 'apply' then 'set the mic to apply mode — request the mic to speak' else 'opened the mic — tap any free seat to speak' end);
end $$;

-- free mode: same as before. apply mode: only the host and room admins can sit down directly.
create or replace function public.take_seat(p_room bigint, p_seat int)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if not exists (select 1 from room_members where room_id = p_room and user_id = me and role <> 'banned') then raise exception 'join the room first'; end if;
  if p_seat = 0 and not exists (select 1 from rooms where id = p_room and owner_id = me) then raise exception 'host seat'; end if;
  if (select mic_mode from rooms where id = p_room) = 'apply' and not is_room_admin(p_room)
     and not exists (select 1 from room_seats where room_id = p_room and user_id = me) then
    raise exception 'This room uses mic requests. Tap "Apply for mic" and wait for the host.';
  end if;
  update room_seats set user_id = null where room_id = p_room and user_id = me;
  update room_seats set user_id = me, muted = false where room_id = p_room and seat = p_seat and user_id is null and not locked;
  if not found then raise exception 'seat is taken or locked'; end if;
end $$;

create or replace function public.mic_apply(p_room bigint)
returns bigint language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); rid bigint;
begin
  if not exists (select 1 from room_members where room_id = p_room and user_id = me and role <> 'banned') then raise exception 'join the room first'; end if;
  if exists (select 1 from room_seats where room_id = p_room and user_id = me) then raise exception 'You are already on the mic'; end if;
  select id into rid from mic_requests where room_id = p_room and user_id = me and kind = 'apply' and status = 'pending';
  if rid is not null then return rid; end if;
  insert into mic_requests(room_id, user_id, kind) values (p_room, me, 'apply') returning id into rid;
  return rid;
end $$;

create or replace function public.mic_cancel(p_room bigint)
returns void language sql security definer set search_path = public as $$
  update mic_requests set status = 'cancelled', answered_at = now()
   where room_id = p_room and user_id = auth.uid() and kind = 'apply' and status = 'pending'
$$;

-- host/admin: the waiting list
create or replace function public.mic_queue(p_room bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_room_admin(p_room) then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'user_id', q.user_id, 'created_at', q.created_at,
            'username', p.username, 'avatar_url', p.avatar_url, 'avatar_preset', p.avatar_preset,
            'wealth_level', p.wealth_level, 'public_id', p.public_id) order by q.id)
     from mic_requests q join profiles p on p.id = q.user_id
    where q.room_id = p_room and q.kind = 'apply' and q.status = 'pending'
      and exists (select 1 from room_presence rp where rp.room_id = p_room and rp.user_id = q.user_id and rp.left_at is null)), '[]'::jsonb);
end $$;

-- host/admin: approve (puts them on a free seat) or decline a request
create or replace function public.mic_answer(p_req bigint, p_accept boolean)
returns int language plpgsql security definer set search_path = public as $$
declare q mic_requests; s int;
begin
  select * into q from mic_requests where id = p_req for update;
  if not found or q.kind <> 'apply' then raise exception 'request not found'; end if;
  if not is_room_admin(q.room_id) then raise exception 'room admins only'; end if;
  if q.status <> 'pending' then raise exception 'This request was already handled'; end if;
  if p_accept then
    s := _put_on_mic(q.room_id, q.user_id, null);
    update mic_requests set status = 'accepted', answered_at = now(), by_user = auth.uid(), seat = s where id = p_req;
    insert into room_messages(room_id, user_id, kind, body) values (q.room_id, q.user_id, 'system', 'is on mic No.' || s || ' 🎙️');
    return s;
  end if;
  update mic_requests set status = 'declined', answered_at = now(), by_user = auth.uid() where id = p_req;
  return null;
end $$;

-- host/admin: invite someone in the room to the mic (optionally to a given seat)
create or replace function public.mic_invite(p_room bigint, p_user uuid, p_seat int default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare rid bigint; host text; rname text;
begin
  if not is_room_admin(p_room) then raise exception 'room admins only'; end if;
  if exists (select 1 from room_seats where room_id = p_room and user_id = p_user) then raise exception 'They are already on the mic'; end if;
  if exists (select 1 from room_members where room_id = p_room and user_id = p_user and role = 'banned') then raise exception 'They are blocked from this room'; end if;
  if _free_seat(p_room, p_seat) is null then raise exception 'No free seat on the mic right now'; end if;
  update mic_requests set status = 'cancelled', answered_at = now()
   where room_id = p_room and user_id = p_user and kind = 'invite' and status = 'pending';
  insert into mic_requests(room_id, user_id, kind, seat, by_user) values (p_room, p_user, 'invite', p_seat, auth.uid()) returning id into rid;
  select username into host from profiles where id = auth.uid();
  select name into rname from rooms where id = p_room;
  perform _notify(p_user, 'Mic invitation', host || ' invited you to speak in ' || rname,
    jsonb_build_object('type', 'mic_invite', 'room', p_room, 'request', rid));
  return rid;
end $$;

-- the invited person accepts (goes on a free seat) or declines
create or replace function public.mic_invite_answer(p_req bigint, p_accept boolean)
returns int language plpgsql security definer set search_path = public as $$
declare q mic_requests; s int;
begin
  select * into q from mic_requests where id = p_req for update;
  if not found or q.kind <> 'invite' or q.user_id <> auth.uid() then raise exception 'invitation not found'; end if;
  if q.status <> 'pending' then raise exception 'This invitation has expired'; end if;
  if q.created_at < now() - interval '10 minutes' then
    update mic_requests set status = 'cancelled', answered_at = now() where id = p_req;
    raise exception 'This invitation has expired';
  end if;
  if p_accept then
    if not exists (select 1 from room_members where room_id = q.room_id and user_id = q.user_id and role <> 'banned') then raise exception 'join the room first'; end if;
    s := _put_on_mic(q.room_id, q.user_id, q.seat);
    update mic_requests set status = 'accepted', answered_at = now(), seat = s where id = p_req;
    update mic_requests set status = 'cancelled', answered_at = now()
     where room_id = q.room_id and user_id = q.user_id and kind = 'apply' and status = 'pending';
    insert into room_messages(room_id, user_id, kind, body) values (q.room_id, q.user_id, 'system', 'accepted the invite and is on mic No.' || s || ' 🎙️');
    return s;
  end if;
  update mic_requests set status = 'declined', answered_at = now() where id = p_req;
  return null;
end $$;

-- my pending invitation in this room (shown when I open the room from a notification)
create or replace function public.mic_my_invite(p_room bigint)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('id', q.id, 'seat', q.seat, 'by', p.username)
     from mic_requests q left join profiles p on p.id = q.by_user
    where q.room_id = p_room and q.user_id = auth.uid() and q.kind = 'invite' and q.status = 'pending'
      and q.created_at > now() - interval '10 minutes'
    order by q.id desc limit 1), 'null'::jsonb)
$$;

-- leaving the room also withdraws any waiting request
create or replace function public.leave_room(p_room bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  update room_seats set user_id = null where room_id = p_room and user_id = auth.uid() and seat <> 0;
  update room_presence set left_at = now() where room_id = p_room and user_id = auth.uid() and left_at is null;
  update rooms set listeners = _room_count(p_room) where id = p_room;
  update mic_requests set status = 'cancelled', answered_at = now()
   where room_id = p_room and user_id = auth.uid() and status = 'pending';
end $$;

revoke all on function public._free_seat(bigint, int), public._put_on_mic(bigint, uuid, int) from public, anon, authenticated;
revoke all on function public.set_mic_mode(bigint, text), public.mic_apply(bigint), public.mic_cancel(bigint), public.mic_queue(bigint),
  public.mic_answer(bigint, boolean), public.mic_invite(bigint, uuid, int), public.mic_invite_answer(bigint, boolean),
  public.mic_my_invite(bigint) from public, anon;
grant execute on function public.set_mic_mode(bigint, text), public.mic_apply(bigint), public.mic_cancel(bigint), public.mic_queue(bigint),
  public.mic_answer(bigint, boolean), public.mic_invite(bigint, uuid, int), public.mic_invite_answer(bigint, boolean),
  public.mic_my_invite(bigint) to authenticated;

-- public legal pages (served with the console on GitHub Pages)
update public.app_settings set value = '"https://muntasirrezvi.github.io/ADDA/privacy/"' where key = 'privacy_url';
update public.app_settings set value = '"https://muntasirrezvi.github.io/ADDA/terms/"' where key = 'terms_url';
