-- Adda: withdrawals switched off (coins and diamonds stay inside the app), room admin tools.

-- ---------------------------------------------------------------- no withdrawals
insert into public.app_settings(key, value) values ('withdraw_enabled', 'false')
on conflict (key) do update set value = 'false';

create or replace function public.request_withdrawal(p_diamonds bigint, p_method text, p_account text, p_name text default null)
returns public.payouts language plpgsql security definer set search_path = public as $$
begin
  raise exception 'withdrawals are not available. Coins and diamonds can be sent to other users.';
end $$;

-- ---------------------------------------------------------------- room admins
-- the room owner (and Adda admins) can make any member a room admin; room admins can
-- mute or unmute everyone or one person, take people off the mic, lock seats and block people.
create or replace function public.set_room_admin(p_room bigint, p_user uuid, p_admin boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from rooms where id = p_room and owner_id = auth.uid()) and not is_admin() then raise exception 'only the room owner can choose admins'; end if;
  if exists (select 1 from rooms where id = p_room and owner_id = p_user) then raise exception 'the owner is already in charge'; end if;
  insert into room_members(room_id, user_id, role) values (p_room, p_user, case when p_admin then 'admin' else 'member' end)
    on conflict (room_id, user_id) do update set role = case when p_admin then 'admin' else 'member' end;
  insert into room_messages(room_id, user_id, kind, body)
    values (p_room, p_user, 'system', case when p_admin then 'is now a room admin 🛡️' else 'is no longer a room admin' end);
end $$;

create or replace function public.kick_from_room(p_room bigint, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_room_admin(p_room) then raise exception 'room admins only'; end if;
  if exists (select 1 from rooms where id = p_room and owner_id = p_user) then raise exception 'cannot block the owner'; end if;
  if exists (select 1 from room_members where room_id = p_room and user_id = p_user and role = 'admin')
     and not exists (select 1 from rooms where id = p_room and owner_id = auth.uid()) and not is_admin() then
    raise exception 'only the owner can block a room admin';
  end if;
  insert into room_members(room_id, user_id, role) values (p_room, p_user, 'banned')
    on conflict (room_id, user_id) do update set role = 'banned';
  update room_seats set user_id = null where room_id = p_room and user_id = p_user;
  update room_presence set left_at = now() where room_id = p_room and user_id = p_user and left_at is null;
end $$;

create or replace function public.room_unblock(p_room bigint, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_room_admin(p_room) then raise exception 'room admins only'; end if;
  update room_members set role = 'member' where room_id = p_room and user_id = p_user and role = 'banned';
end $$;

create or replace function public.room_mute_all(p_room bigint, p_muted boolean)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_room_admin(p_room) then raise exception 'room admins only'; end if;
  update room_seats set muted = p_muted
   where room_id = p_room and seat <> 0 and user_id is not null and user_id <> auth.uid();
  get diagnostics n = row_count;
  insert into room_messages(room_id, user_id, kind, body) values (p_room, auth.uid(), 'system', case when p_muted then 'muted everyone on the mic 🔇' else 'unmuted everyone 🎙️' end);
  return n;
end $$;

create or replace function public.room_roles(p_room bigint)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'owner', (select owner_id from rooms where id = p_room),
    'admins', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'avatar_url', p.avatar_url, 'avatar_preset', p.avatar_preset, 'public_id', p.public_id))
                 from room_members m join profiles p on p.id = m.user_id where m.room_id = p_room and m.role = 'admin'
                   and m.user_id <> (select owner_id from rooms where id = p_room)), '[]'::jsonb),
    'blocked', case when is_room_admin(p_room) then coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'avatar_url', p.avatar_url, 'avatar_preset', p.avatar_preset, 'public_id', p.public_id))
                 from room_members m join profiles p on p.id = m.user_id where m.room_id = p_room and m.role = 'banned'), '[]'::jsonb) else '[]'::jsonb end)
$$;

revoke all on function public.room_unblock(bigint, uuid), public.room_mute_all(bigint, boolean), public.room_roles(bigint) from public, anon;
grant execute on function public.room_unblock(bigint, uuid), public.room_mute_all(bigint, boolean), public.room_roles(bigint) to authenticated;
