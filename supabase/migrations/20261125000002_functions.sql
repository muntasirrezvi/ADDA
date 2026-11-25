-- Adda: business logic. Every coin movement goes through these functions so the
-- app can never set balances or prices itself.

-- ---------- helpers ----------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role in ('admin','moderator'))
$$;

create or replace function public.is_super_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin')
$$;

create or replace function public.setting(k text) returns jsonb
language sql stable security definer set search_path = public as $$
  select value from app_settings where key = k
$$;

create or replace function public.setting_num(k text, fallback numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from app_settings where key = k), fallback)
$$;

-- level L needs 2M x (L-1) more XP than level L-1 (2M, 4M, 6M ...)
create or replace function public.level_for(xp bigint) returns int
language sql immutable as $$
  select greatest(1, floor((1 + sqrt(1 + 4.0 * xp / 1000000.0)) / 2)::int)
$$;

create or replace function public.active_user(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = p and deleted_at is null and (banned_until is null or banned_until < now()))
$$;

create or replace function public._audit(p_action text, p_target text, p_meta jsonb default '{}')
returns void language sql security definer set search_path = public as $$
  insert into audit_log(actor_id, action, target, meta) values (auth.uid(), p_action, p_target, p_meta)
$$;

-- the only place balances change
create or replace function public._wallet_add(p_user uuid, p_coins bigint, p_dia bigint, p_kind text, p_ref text, p_meta jsonb default '{}')
returns public.wallets language plpgsql security definer set search_path = public as $$
declare w wallets;
begin
  update wallets set coins = coins + p_coins, diamonds = diamonds + p_dia, updated_at = now()
   where user_id = p_user returning * into w;
  if not found then raise exception 'wallet not found'; end if;
  insert into transactions(user_id, kind, coins, diamonds, ref, meta) values (p_user, p_kind, p_coins, p_dia, p_ref, p_meta);
  return w;
end $$;

create or replace function public._notify(p_user uuid, p_title text, p_body text, p_data jsonb default '{}')
returns void language sql security definer set search_path = public as $$
  insert into notifications(user_id, title, body, data) values (p_user, p_title, p_body, p_data)
$$;

-- ---------- sign-up ----------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  uname text := left(coalesce(nullif(trim(new.raw_user_meta_data->>'username'), ''), 'user' || substr(replace(new.id::text, '-', ''), 1, 8)), 20);
  bonus bigint := setting_num('welcome_bonus', 0)::bigint;
begin
  if char_length(uname) < 3 then uname := uname || '_' || substr(replace(new.id::text, '-', ''), 1, 4); end if;
  insert into profiles(id, username, country) values (new.id, uname, new.raw_user_meta_data->>'country');
  insert into profile_private(user_id, email, phone) values (new.id, new.email, coalesce(nullif(new.phone, ''), new.raw_user_meta_data->>'phone'));
  insert into wallets(user_id, coins) values (new.id, bonus);
  if bonus > 0 then
    insert into transactions(user_id, kind, coins, ref) values (new.id, 'reward', bonus, 'welcome');
  end if;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- pricing ----------
-- recharge tier bonus (0-5%) + recent gifting bonus (0-3%), capped with the pack discount at 20%
create or replace function public.discount_for(p_user uuid, p_pack text) returns int
language plpgsql stable security definer set search_path = public as $$
declare usd numeric; spent bigint; tier int; act int; base int;
begin
  select lifetime_usd into usd from profiles where id = p_user;
  tier := case when usd >= 2000 then 5 when usd >= 500 then 4 when usd >= 100 then 3 when usd >= 20 then 2 when usd >= 5 then 1 else 0 end;
  select coalesce(-sum(coins), 0) into spent from transactions
   where user_id = p_user and kind = 'gift_sent' and created_at > now() - interval '30 days';
  act := case when spent >= 10000000 then 3 when spent >= 2000000 then 2 when spent >= 500000 then 1 else 0 end;
  select discount_pct into base from coin_packs where id = p_pack;
  return least(20, coalesce(base, 0) + tier + act);
end $$;

create or replace function public.my_coin_packs()
returns table (id text, usd numeric, bdt numeric, coins bigint, discount_pct int, pay_bdt numeric, play_product_id text)
language sql stable security definer set search_path = public as $$
  select p.id, p.usd, p.bdt, p.coins, discount_for(auth.uid(), p.id),
         round(p.bdt * (100 - discount_for(auth.uid(), p.id)) / 100.0, 2), p.play_product_id
    from coin_packs p where p.active order by p.sort
$$;

-- ---------- payments ----------
create or replace function public.create_payment(p_pack text, p_provider text default 'sslcommerz')
returns public.payments language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pk coin_packs; d int; p payments;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not active_user(me) then raise exception 'account restricted'; end if;
  if p_provider <> 'sslcommerz' then raise exception 'use the store purchase flow for %', p_provider; end if;
  select * into pk from coin_packs where id = p_pack and active;
  if not found then raise exception 'pack not found'; end if;
  d := discount_for(me, p_pack);
  insert into payments(user_id, provider, pack_id, amount, currency, coins)
  values (me, p_provider, p_pack, round(pk.bdt * (100 - d) / 100.0, 2), 'BDT', pk.coins)
  returning * into p;
  return p;
end $$;

-- called only by the payment Edge Functions (service role) after the gateway confirms
create or replace function public.complete_payment(p_id uuid, p_ref text, p_raw jsonb, p_amount numeric default null, p_currency text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p payments; usd numeric;
begin
  select * into p from payments where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'payment not found'); end if;
  if p.status = 'paid' then return jsonb_build_object('ok', true, 'already', true); end if;
  if p.status <> 'pending' then return jsonb_build_object('ok', false, 'error', 'payment not pending'); end if;
  if p_amount is not null and (round(p_amount, 2) <> p.amount or upper(p_currency) <> upper(p.currency)) then
    update payments set status = 'failed', raw = p_raw where id = p_id;
    return jsonb_build_object('ok', false, 'error', 'amount mismatch');
  end if;
  update payments set status = 'paid', provider_ref = coalesce(p_ref, provider_ref), raw = p_raw, paid_at = now() where id = p_id;
  perform _wallet_add(p.user_id, p.coins, 0, 'topup', p_id::text, jsonb_build_object('provider', p.provider));
  select c.usd into usd from coin_packs c where c.id = p.pack_id;
  update profiles set lifetime_usd = lifetime_usd + coalesce(usd, 0) where id = p.user_id;
  perform _notify(p.user_id, 'Top-up successful', p.coins || ' coins were added to your wallet', jsonb_build_object('type', 'topup'));
  return jsonb_build_object('ok', true, 'coins', p.coins);
end $$;

create or replace function public.fail_payment(p_id uuid, p_status text, p_raw jsonb)
returns void language sql security definer set search_path = public as $$
  update payments set status = case when p_status in ('cancelled','failed') then p_status else 'failed' end, raw = p_raw
   where id = p_id and status = 'pending'
$$;

-- Google Play: called by the verify function after Google confirms the purchase token
create or replace function public.record_store_purchase(p_user uuid, p_provider text, p_product text, p_token text, p_raw jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pk coin_packs; pid uuid; st text;
begin
  select * into pk from coin_packs where play_product_id = p_product and active;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown product'); end if;
  insert into payments(user_id, provider, pack_id, amount, currency, coins, provider_ref, raw)
  values (p_user, p_provider, pk.id, pk.usd, 'USD', pk.coins, p_token, p_raw)
  on conflict (provider, provider_ref) do nothing
  returning id into pid;
  if pid is null then
    select id, status into pid, st from payments where provider = p_provider and provider_ref = p_token;
    if st = 'paid' then return jsonb_build_object('ok', true, 'already', true); end if;
  end if;
  return complete_payment(pid, p_token, p_raw);
end $$;

-- ---------- coin agents ----------
create or replace function public.agent_sell(p_buyer_public bigint, p_coins bigint, p_method text, p_amount numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); buyer uuid; per_usd numeric := setting_num('coins_per_usd', 500000);
begin
  if not exists (select 1 from profiles where id = me and role in ('agent','admin')) then raise exception 'agents only'; end if;
  select id into buyer from profiles where public_id = p_buyer_public and deleted_at is null;
  if buyer is null then raise exception 'user not found'; end if;
  if p_coins < 100000 or p_coins > 5000000000 then raise exception 'amount out of range'; end if;
  update agent_stock set coins = coins - p_coins where agent_id = me and coins >= p_coins;
  if not found then raise exception 'not enough coin stock'; end if;
  perform _wallet_add(buyer, p_coins, 0, 'agent_buy', me::text, jsonb_build_object('method', p_method));
  update profiles set lifetime_usd = lifetime_usd + round(p_coins / per_usd, 2) where id = buyer;
  insert into agent_sales(agent_id, buyer_id, coins, method, amount_local) values (me, buyer, p_coins, p_method, p_amount);
  perform _notify(buyer, 'Coins received', p_coins || ' coins from a verified coin agent', jsonb_build_object('type', 'topup'));
  return jsonb_build_object('ok', true, 'stock_left', (select coins from agent_stock where agent_id = me));
end $$;

-- ---------- gifts ----------
create or replace function public.send_gift(p_room bigint, p_receivers uuid[], p_gift text, p_qty int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); g gifts; n int := coalesce(array_length(p_receivers, 1), 0);
  total bigint; per bigint; r uuid; w wallets; rate numeric := setting_num('diamond_rate', 0.5);
  old_lv int; new_lv int; sender_name text;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not active_user(me) then raise exception 'account restricted'; end if;
  select * into g from gifts where id = p_gift and active
     and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now());
  if not found then raise exception 'gift unavailable'; end if;
  if p_qty not in (1, 10, 99) or (g.tier = 'exclusive' and p_qty <> 1) then raise exception 'invalid quantity'; end if;
  if n < 1 or n > 17 then raise exception 'invalid receivers'; end if;
  if me = any(p_receivers) then raise exception 'you cannot gift yourself'; end if;
  per := g.price * p_qty; total := per * n;
  select * into w from wallets where user_id = me for update;
  if w.coins < total then raise exception 'insufficient coins'; end if;
  perform _wallet_add(me, -total, 0, 'gift_sent', p_gift, jsonb_build_object('room', p_room, 'qty', p_qty, 'receivers', p_receivers));
  select username into sender_name from profiles where id = me;
  foreach r in array p_receivers loop
    if exists (select 1 from blocks where blocker_id = r and blocked_id = me) then raise exception 'a receiver is unavailable'; end if;
    perform _wallet_add(r, 0, floor(per * rate)::bigint, 'gift_received', p_gift, jsonb_build_object('from', me, 'room', p_room, 'qty', p_qty));
    update profiles set charm_xp = charm_xp + per where id = r;
    insert into gift_events(room_id, sender_id, receiver_id, gift_id, qty, total) values (p_room, me, r, p_gift, p_qty, per);
    perform _notify(r, sender_name || ' sent you ' || g.name || ' x' || p_qty, 'You earned ' || floor(per * rate) || ' diamonds', jsonb_build_object('type', 'gift', 'room', p_room));
  end loop;
  select wealth_level into old_lv from profiles where id = me;
  update profiles set wealth_xp = wealth_xp + total, wealth_level = level_for(wealth_xp + total) where id = me
   returning wealth_level into new_lv;
  if p_room is not null then update rooms set score_today = score_today + total where id = p_room; end if;
  return jsonb_build_object('coins', w.coins - total, 'total', total, 'level', new_lv, 'level_up', new_lv > old_lv);
end $$;

-- ---------- rooms ----------
create or replace function public.create_room(p_name text, p_topic text, p_language text, p_seats int,
  p_cover_url text default null, p_cover_template text default 'lantern', p_theme text default 'majlis', p_password text default null)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r rooms; i int;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  if (select count(*) from rooms where owner_id = me and status = 'open') >= 1 then raise exception 'you already have an open room'; end if;
  if p_password is not null and p_password !~ '^\d{4,8}$' then raise exception 'password must be 4 to 8 digits'; end if;
  insert into rooms(owner_id, name, topic, language, seats, cover_url, cover_template, theme, locked, password_hash)
  values (me, p_name, coalesce(p_topic, 'Talk'), coalesce(p_language, 'English'), p_seats, p_cover_url, coalesce(p_cover_template, 'lantern'), coalesce(p_theme, 'majlis'),
          p_password is not null, case when p_password is null then null else extensions.crypt(p_password, extensions.gen_salt('bf')) end)
  returning * into r;
  insert into room_seats(room_id, seat, user_id) values (r.id, 0, me); -- seat 0 is the host seat
  for i in 1 .. p_seats loop insert into room_seats(room_id, seat) values (r.id, i); end loop;
  insert into room_members(room_id, user_id, role) values (r.id, me, 'admin');
  return r;
end $$;

create or replace function public.set_room_password(p_room bigint, p_password text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from rooms where id = p_room and owner_id = auth.uid()) then raise exception 'owner only'; end if;
  if p_password is not null and p_password !~ '^\d{4,8}$' then raise exception 'password must be 4 to 8 digits'; end if;
  update rooms set locked = p_password is not null,
    password_hash = case when p_password is null then null else extensions.crypt(p_password, extensions.gen_salt('bf')) end
   where id = p_room;
end $$;

create or replace function public.join_room(p_room bigint, p_password text default null)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r rooms; m room_members;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  select * into r from rooms where id = p_room;
  if not found or r.status <> 'open' then raise exception 'room is not available'; end if;
  select * into m from room_members where room_id = p_room and user_id = me;
  if found and m.role = 'banned' then raise exception 'you were removed from this room'; end if;
  if r.locked and r.owner_id <> me and not found then
    if p_password is null or extensions.crypt(p_password, r.password_hash) <> r.password_hash then raise exception 'wrong password'; end if;
  end if;
  insert into room_members(room_id, user_id) values (p_room, me) on conflict do nothing;
  update rooms set listeners = listeners + 1 where id = p_room returning * into r;
  r.password_hash := null;
  return r;
end $$;

create or replace function public.leave_room(p_room bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  update room_seats set user_id = null where room_id = p_room and user_id = auth.uid() and seat <> 0;
  update rooms set listeners = greatest(0, listeners - 1) where id = p_room;
end $$;

create or replace function public.take_seat(p_room bigint, p_seat int)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if not exists (select 1 from room_members where room_id = p_room and user_id = me and role <> 'banned') then raise exception 'join the room first'; end if;
  if p_seat = 0 and not exists (select 1 from rooms where id = p_room and owner_id = me) then raise exception 'host seat'; end if;
  update room_seats set user_id = null where room_id = p_room and user_id = me;
  update room_seats set user_id = me, muted = false where room_id = p_room and seat = p_seat and user_id is null and not locked;
  if not found then raise exception 'seat is taken or locked'; end if;
end $$;

create or replace function public.leave_seat(p_room bigint)
returns void language sql security definer set search_path = public as $$
  update room_seats set user_id = null where room_id = p_room and user_id = auth.uid() and seat <> 0
$$;

create or replace function public.is_room_admin(p_room bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from rooms where id = p_room and owner_id = auth.uid())
      or exists (select 1 from room_members where room_id = p_room and user_id = auth.uid() and role = 'admin')
      or is_admin()
$$;

-- host tools: lock / unlock / mute / unmute / remove a seat
create or replace function public.host_seat_action(p_room bigint, p_seat int, p_action text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_room_admin(p_room) then raise exception 'room admins only'; end if;
  if p_seat = 0 then raise exception 'not allowed on the host seat'; end if;
  update room_seats set
    locked = case p_action when 'lock' then true when 'unlock' then false else locked end,
    user_id = case when p_action in ('lock','remove') then null else user_id end,
    muted = case p_action when 'mute' then true when 'unmute' then false else muted end
  where room_id = p_room and seat = p_seat;
end $$;

create or replace function public.kick_from_room(p_room bigint, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_room_admin(p_room) then raise exception 'room admins only'; end if;
  if exists (select 1 from rooms where id = p_room and owner_id = p_user) then raise exception 'cannot kick the owner'; end if;
  insert into room_members(room_id, user_id, role) values (p_room, p_user, 'banned')
    on conflict (room_id, user_id) do update set role = 'banned';
  update room_seats set user_id = null where room_id = p_room and user_id = p_user;
end $$;

create or replace function public.set_room_admin(p_room bigint, p_user uuid, p_admin boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from rooms where id = p_room and owner_id = auth.uid()) and not is_admin() then raise exception 'owner only'; end if;
  insert into room_members(room_id, user_id, role) values (p_room, p_user, case when p_admin then 'admin' else 'member' end)
    on conflict (room_id, user_id) do update set role = case when p_admin then 'admin' else 'member' end;
end $$;

-- ---------- calls ----------
create or replace function public.start_call(p_callee uuid, p_type text)
returns public.calls language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); c calls; nm text;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  if p_type not in ('audio','video') then raise exception 'bad call type'; end if;
  if exists (select 1 from blocks where (blocker_id = p_callee and blocked_id = me) or (blocker_id = me and blocked_id = p_callee)) then raise exception 'user unavailable'; end if;
  update calls set status = 'missed', ended_at = now() where caller_id = me and status = 'ringing';
  insert into calls(caller_id, callee_id, type) values (me, p_callee, p_type) returning * into c;
  select username into nm from profiles where id = me;
  perform _notify(p_callee, 'Incoming ' || case when p_type = 'video' then 'video' else 'voice' end || ' call', nm || ' is calling you', jsonb_build_object('type', 'call', 'call_id', c.id));
  return c;
end $$;

create or replace function public.update_call(p_call uuid, p_status text)
returns public.calls language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); c calls; secs int; label text;
begin
  select * into c from calls where id = p_call and me in (caller_id, callee_id) for update;
  if not found then raise exception 'call not found'; end if;
  if p_status = 'active' and c.status = 'ringing' and me = c.callee_id then
    update calls set status = 'active', started_at = now() where id = p_call returning * into c;
  elsif p_status = 'declined' and c.status = 'ringing' and me = c.callee_id then
    update calls set status = 'declined', ended_at = now() where id = p_call returning * into c;
  elsif p_status in ('ended','missed') and c.status in ('ringing','active') then
    update calls set status = case when c.status = 'ringing' then 'missed' else 'ended' end, ended_at = now() where id = p_call returning * into c;
  else
    raise exception 'invalid call transition';
  end if;
  if c.status in ('ended','missed','declined') then
    label := case when c.type = 'video' then 'Video call' else 'Voice call' end;
    secs := coalesce(extract(epoch from (c.ended_at - c.started_at))::int, 0);
    insert into direct_messages(sender_id, receiver_id, kind, body, meta)
    values (c.caller_id, c.callee_id, 'call',
      case c.status when 'ended' then label || ' · ' || lpad((secs / 60)::text, 2, '0') || ':' || lpad((secs % 60)::text, 2, '0')
                    when 'declined' then label || ' declined' else 'Missed ' || lower(label) end,
      jsonb_build_object('call_id', c.id, 'seconds', secs));
  end if;
  return c;
end $$;

-- ---------- reels ----------
create or replace function public.toggle_reel_like(p_reel uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  delete from reel_likes where reel_id = p_reel and user_id = me;
  if found then update reels set likes = greatest(0, likes - 1) where id = p_reel; return false; end if;
  insert into reel_likes(reel_id, user_id) values (p_reel, me);
  update reels set likes = likes + 1 where id = p_reel;
  return true;
end $$;

create or replace function public.view_reel(p_reel uuid)
returns void language sql security definer set search_path = public as $$
  update reels set views = views + 1 where id = p_reel and status = 'active'
$$;

create or replace function public.donate_reel(p_reel uuid, p_coins bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); rl reels; w wallets; share numeric := setting_num('creator_share', 0.8); got bigint;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  if p_coins < 1000 then raise exception 'minimum donation is 1000 coins'; end if;
  select * into rl from reels where id = p_reel and status = 'active' and allow_donations;
  if not found then raise exception 'donations are off for this reel'; end if;
  if rl.user_id = me then raise exception 'you cannot donate to yourself'; end if;
  select * into w from wallets where user_id = me for update;
  if w.coins < p_coins then raise exception 'insufficient coins'; end if;
  got := floor(p_coins * share)::bigint;
  perform _wallet_add(me, -p_coins, 0, 'donation_sent', p_reel::text);
  perform _wallet_add(rl.user_id, got, 0, 'donation_received', p_reel::text, jsonb_build_object('from', me));
  update reels set coins_earned = coins_earned + got where id = p_reel;
  perform _notify(rl.user_id, 'Your reel got a donation', got || ' coins added to your wallet', jsonb_build_object('type', 'donation', 'reel', p_reel));
  return jsonb_build_object('coins', w.coins - p_coins);
end $$;

create or replace function public.reel_comment_count() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then update reels set comments = comments + 1 where id = new.reel_id;
  else update reels set comments = greatest(0, comments - 1) where id = old.reel_id; end if;
  return null;
end $$;
create trigger reel_comments_count after insert or delete on public.reel_comments
  for each row execute function public.reel_comment_count();

create or replace function public.track_use() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.track_id is not null then update music_tracks set uses = uses + 1 where id = new.track_id; end if;
  return new;
end $$;
create trigger reels_track_use after insert on public.reels for each row execute function public.track_use();

-- ---------- chat safety ----------
create or replace function public.clean_message() returns trigger
language plpgsql security definer set search_path = public as $$
declare w text;
begin
  if new.body is null then return new; end if;
  if new.body ~* '(https?://|www\.|\m[a-z0-9-]+\.(com|net|org|io|me|ly|link|xyz|app|gg|site|shop)\M)' then
    raise exception 'Links are not allowed in chat';
  end if;
  for w in select jsonb_array_elements_text(coalesce(setting('blocked_words'), '[]')) loop
    new.body := regexp_replace(new.body, '\m' || w || '\w*', repeat('*', char_length(w)), 'gi');
  end loop;
  return new;
end $$;
create trigger room_messages_clean before insert on public.room_messages for each row execute function public.clean_message();
create trigger direct_messages_clean before insert on public.direct_messages for each row when (new.kind = 'text') execute function public.clean_message();

-- ---------- daily rewards ----------
create or replace function public.daily_checkin()
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); streak int; reward bigint;
begin
  if me is null then raise exception 'not signed in'; end if;
  if exists (select 1 from daily_checkins where user_id = me and day = current_date) then
    return jsonb_build_object('ok', false, 'error', 'already claimed today');
  end if;
  select count(*) into streak from daily_checkins where user_id = me and day >= current_date - 6;
  reward := case when streak >= 6 then 200000 else (streak + 1) * 10000 end;
  insert into daily_checkins(user_id, reward) values (me, reward);
  perform _wallet_add(me, reward, 0, 'reward', 'checkin');
  return jsonb_build_object('ok', true, 'reward', reward, 'day', streak + 1);
end $$;

-- ---------- diamonds, hosts, payouts ----------
create or replace function public.exchange_diamonds(p_diamonds bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); w wallets; rate numeric := setting_num('diamond_to_coins', 1);
begin
  if p_diamonds < 1000 then raise exception 'minimum is 1000 diamonds'; end if;
  select * into w from wallets where user_id = me for update;
  if w.diamonds < p_diamonds then raise exception 'not enough diamonds'; end if;
  perform _wallet_add(me, floor(p_diamonds * rate)::bigint, -p_diamonds, 'exchange', 'diamonds');
  return jsonb_build_object('coins', w.coins + floor(p_diamonds * rate), 'diamonds', w.diamonds - p_diamonds);
end $$;

create or replace function public.request_verification(p_id_doc text, p_selfie text)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if split_part(p_id_doc, '/', 1) <> me::text or split_part(p_selfie, '/', 1) <> me::text then raise exception 'upload to your own folder'; end if;
  if exists (select 1 from verifications where user_id = me and status = 'pending') then raise exception 'already under review'; end if;
  insert into verifications(user_id, id_doc_path, selfie_path) values (me, p_id_doc, p_selfie);
end $$;

create or replace function public.request_payout(p_diamonds bigint, p_method text, p_account text)
returns public.payouts language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); w wallets; per_usd numeric := setting_num('diamonds_per_usd', 625000); p payouts;
begin
  if not exists (select 1 from profiles where id = me and verified) then raise exception 'verify your identity first'; end if;
  if p_diamonds < setting_num('min_payout_diamonds', 6250000) then raise exception 'below the minimum payout'; end if;
  if p_method not in ('bkash','nagad','bank','payoneer') then raise exception 'unsupported method'; end if;
  select * into w from wallets where user_id = me for update;
  if w.diamonds < p_diamonds then raise exception 'not enough diamonds'; end if;
  perform _wallet_add(me, 0, -p_diamonds, 'payout', 'hold');
  insert into payouts(user_id, diamonds, amount_usd, method, account) values (me, p_diamonds, round(p_diamonds / per_usd, 2), p_method, p_account) returning * into p;
  return p;
end $$;

create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
begin
  update profiles set deleted_at = now() where id = auth.uid();
  update rooms set status = 'closed' where owner_id = auth.uid();
  delete from devices where user_id = auth.uid();
end $$;

-- ---------- admin ----------
create or replace function public.admin_stats(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare since timestamptz := now() - make_interval(days => p_days);
begin
  if not is_admin() then raise exception 'admins only'; end if;
  return jsonb_build_object(
    'revenue_usd', (select coalesce(sum(c.usd), 0) from payments p join coin_packs c on c.id = p.pack_id where p.status = 'paid' and p.paid_at > since),
    'payments', (select count(*) from payments where status = 'paid' and paid_at > since),
    'paying_users', (select count(distinct user_id) from payments where status = 'paid' and paid_at > since),
    'new_users', (select count(*) from profiles where created_at > since),
    'total_users', (select count(*) from profiles where deleted_at is null),
    'active_rooms', (select count(*) from rooms where status = 'open'),
    'gift_coins', (select coalesce(-sum(coins), 0) from transactions where kind = 'gift_sent' and created_at > since),
    'open_reports', (select count(*) from reports where status = 'new'),
    'pending_payouts', (select count(*) from payouts where status in ('pending','approved')),
    'pending_verifications', (select count(*) from verifications where status = 'pending'),
    'daily', (select coalesce(jsonb_agg(d order by d.day), '[]') from (
        select gs::date as day,
          (select coalesce(sum(c.usd), 0) from payments p join coin_packs c on c.id = p.pack_id where p.status = 'paid' and p.paid_at::date = gs::date) as revenue,
          (select count(*) from profiles where created_at::date = gs::date) as signups
        from generate_series(current_date - (p_days - 1), current_date, interval '1 day') gs) d)
  );
end $$;

create or replace function public.admin_find_users(p_q text default '', p_limit int default 50)
returns table (id uuid, public_id bigint, username text, email text, phone text, role public.user_role, coins bigint, diamonds bigint,
               lifetime_usd numeric, wealth_level int, verified boolean, banned_until timestamptz, deleted_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admins only'; end if;
  return query
  select p.id, p.public_id, p.username, pp.email, pp.phone, p.role, w.coins, w.diamonds, p.lifetime_usd, p.wealth_level, p.verified, p.banned_until, p.deleted_at, p.created_at
    from profiles p left join profile_private pp on pp.user_id = p.id left join wallets w on w.user_id = p.id
   where p_q = '' or p.username ilike '%' || p_q || '%' or pp.email ilike '%' || p_q || '%' or pp.phone ilike '%' || p_q || '%' or p.public_id::text = p_q
   order by p.created_at desc limit least(p_limit, 200);
end $$;

create or replace function public.admin_adjust_coins(p_user uuid, p_delta bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w wallets;
begin
  if not is_super_admin() then raise exception 'super admins only'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required'; end if;
  select * into w from wallets where user_id = p_user for update;
  if w.coins + p_delta < 0 then raise exception 'balance would go below zero'; end if;
  w := _wallet_add(p_user, p_delta, 0, 'admin_adjust', p_reason, jsonb_build_object('by', auth.uid()));
  perform _audit('adjust_coins', p_user::text, jsonb_build_object('delta', p_delta, 'reason', p_reason));
  return jsonb_build_object('coins', w.coins);
end $$;

create or replace function public.admin_set_role(p_user uuid, p_role public.user_role)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_super_admin() then raise exception 'super admins only'; end if;
  update profiles set role = p_role where id = p_user;
  if p_role = 'agent' then insert into agent_stock(agent_id) values (p_user) on conflict do nothing; end if;
  if p_role = 'host' then insert into hosts(user_id) values (p_user) on conflict do nothing; end if;
  perform _audit('set_role', p_user::text, jsonb_build_object('role', p_role));
end $$;

create or replace function public.admin_ban(p_user uuid, p_days int, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admins only'; end if;
  update profiles set banned_until = case when p_days <= 0 then null else now() + make_interval(days => p_days) end where id = p_user;
  if p_days > 0 then update room_seats set user_id = null where user_id = p_user; end if;
  perform _audit(case when p_days <= 0 then 'unban' else 'ban' end, p_user::text, jsonb_build_object('days', p_days, 'reason', p_reason));
end $$;

create or replace function public.admin_resolve_report(p_report bigint, p_action text, p_ban_days int default 0)
returns void language plpgsql security definer set search_path = public as $$
declare rp reports;
begin
  if not is_admin() then raise exception 'admins only'; end if;
  select * into rp from reports where id = p_report;
  if p_action = 'ban' and rp.target_user is not null then perform admin_ban(rp.target_user, greatest(p_ban_days, 1), 'report ' || p_report); end if;
  if p_action = 'warn' and rp.target_user is not null then perform _notify(rp.target_user, 'Community warning', 'A report about your behaviour was upheld. Repeated issues lead to a ban.', '{}'); end if;
  if p_action = 'remove_reel' and rp.target_reel is not null then update reels set status = 'removed' where id = rp.target_reel; end if;
  if p_action = 'suspend_room' and rp.target_room is not null then update rooms set status = 'suspended' where id = rp.target_room; end if;
  update reports set status = case when p_action = 'dismiss' then 'dismissed' else 'actioned' end, action = p_action, handled_by = auth.uid(), handled_at = now() where id = p_report;
  perform _audit('resolve_report', p_report::text, jsonb_build_object('action', p_action));
end $$;

create or replace function public.admin_review_verification(p_id bigint, p_approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v verifications;
begin
  if not is_admin() then raise exception 'admins only'; end if;
  update verifications set status = case when p_approve then 'approved' else 'rejected' end, note = p_note, reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_id and status = 'pending' returning * into v;
  if not found then raise exception 'not pending'; end if;
  if p_approve then update profiles set verified = true where id = v.user_id; end if;
  perform _notify(v.user_id, case when p_approve then 'You are verified' else 'Verification not approved' end,
    case when p_approve then 'You can now withdraw host earnings.' else coalesce(p_note, 'Please upload clearer photos and try again.') end, '{}');
  perform _audit('review_verification', p_id::text, jsonb_build_object('approve', p_approve));
end $$;

create or replace function public.admin_process_payout(p_id bigint, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare p payouts;
begin
  if not is_super_admin() then raise exception 'super admins only'; end if;
  if p_status not in ('approved','paid','rejected') then raise exception 'bad status'; end if;
  select * into p from payouts where id = p_id for update;
  if p.status in ('paid','rejected') then raise exception 'already closed'; end if;
  update payouts set status = p_status, processed_at = now(), processed_by = auth.uid() where id = p_id;
  if p_status = 'rejected' then perform _wallet_add(p.user_id, 0, p.diamonds, 'payout', 'refund'); end if;
  perform _notify(p.user_id, 'Payout ' || p_status, '$' || p.amount_usd || ' via ' || p.method, '{}');
  perform _audit('payout_' || p_status, p_id::text, '{}');
end $$;

create or replace function public.admin_add_agent_stock(p_agent uuid, p_coins bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_super_admin() then raise exception 'super admins only'; end if;
  insert into agent_stock(agent_id, coins) values (p_agent, p_coins)
    on conflict (agent_id) do update set coins = agent_stock.coins + p_coins;
  perform _audit('agent_stock', p_agent::text, jsonb_build_object('coins', p_coins));
end $$;

-- homepage control: cover image, template, featured pin, order, status
create or replace function public.admin_update_room(p_room bigint, p_patch jsonb)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare r rooms;
begin
  if not is_admin() then raise exception 'admins only'; end if;
  update rooms set
    name = coalesce(p_patch->>'name', name),
    cover_url = case when p_patch ? 'cover_url' then nullif(p_patch->>'cover_url', '') else cover_url end,
    cover_template = coalesce(p_patch->>'cover_template', cover_template),
    theme = coalesce(p_patch->>'theme', theme),
    featured = coalesce((p_patch->>'featured')::boolean, featured),
    home_order = coalesce((p_patch->>'home_order')::int, home_order),
    status = coalesce(p_patch->>'status', status)
  where id = p_room returning * into r;
  perform _audit('update_room', p_room::text, p_patch);
  r.password_hash := null;
  return r;
end $$;

create or replace function public.admin_set_setting(p_key text, p_value jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_super_admin() then raise exception 'super admins only'; end if;
  insert into app_settings(key, value, updated_at) values (p_key, p_value, now())
    on conflict (key) do update set value = excluded.value, updated_at = now();
  perform _audit('setting', p_key, jsonb_build_object('value', p_value));
end $$;

create or replace function public.admin_broadcast(p_title text, p_body text, p_data jsonb default '{}')
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_super_admin() then raise exception 'super admins only'; end if;
  insert into notifications(user_id, title, body, data)
    select id, p_title, p_body, p_data from profiles where deleted_at is null;
  get diagnostics n = row_count;
  perform _audit('broadcast', null, jsonb_build_object('title', p_title, 'count', n));
  return n;
end $$;

-- ---------- privileges on functions ----------
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;
revoke execute on function public._wallet_add(uuid,bigint,bigint,text,text,jsonb) from authenticated;
revoke execute on function public._notify(uuid,text,text,jsonb) from authenticated;
revoke execute on function public._audit(text,text,jsonb) from authenticated;
revoke execute on function public.complete_payment(uuid,text,jsonb,numeric,text) from authenticated;
revoke execute on function public.fail_payment(uuid,text,jsonb) from authenticated;
revoke execute on function public.record_store_purchase(uuid,text,text,text,jsonb) from authenticated;
revoke execute on function public.handle_new_user() from authenticated;
grant execute on function public.level_for(bigint), public.is_admin(), public.is_super_admin() to anon;
