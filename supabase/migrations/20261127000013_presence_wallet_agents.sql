-- Adda: online status and last seen (with privacy), who is in a room and who left,
-- admin coin/diamond grants, agent coin & diamond stores, user-to-user transfers,
-- coins → diamond exchange, and custom-amount top-ups priced from the packages.

insert into public.app_settings(key, value) values
  ('online_window_seconds', '120'),
  ('transfer_enabled', 'true'),
  ('transfer_diamonds_enabled', 'true'),
  ('transfer_min_coins', '1000'),
  ('transfer_daily_max_coins', '1000000000'),
  ('transfer_daily_max_diamonds', '100000000'),
  ('transfer_fee_pct', '0'),
  ('coins_per_diamond', '2500000'),
  ('coin_exchange_enabled', 'true'),
  ('custom_topup_enabled', 'true'),
  ('custom_min_coins', '10000'),
  ('custom_diamonds_enabled', 'true')
on conflict (key) do nothing;

-- ---------------------------------------------------------------- online status
alter table public.profile_private add column if not exists last_seen_at timestamptz;
alter table public.profile_private add column if not exists hide_last_seen boolean not null default false;

create or replace function public.touch_presence()
returns void language sql security definer set search_path = public as $$
  update profile_private set last_seen_at = now() where user_id = auth.uid()
$$;

-- online = seen in the last couple of minutes. Someone who hides their last seen shows
-- "online" while they are here and plain "offline" (no time) otherwise.
create or replace function public.user_presence(p_ids uuid[])
returns table (user_id uuid, online boolean, last_seen timestamptz, hidden boolean)
language sql stable security definer set search_path = public as $$
  select v.user_id,
         coalesce(v.last_seen_at > now() - make_interval(secs => setting_num('online_window_seconds', 120)), false),
         case when v.hide_last_seen and v.user_id <> auth.uid() then null else v.last_seen_at end,
         v.hide_last_seen
    from profile_private v where v.user_id = any(p_ids)
$$;

create or replace function public.set_presence_privacy(p_hide boolean)
returns void language sql security definer set search_path = public as $$
  update profile_private set hide_last_seen = p_hide where user_id = auth.uid()
$$;

-- ---------------------------------------------------------------- who is in the room
create table if not exists public.room_presence (
  room_id bigint not null references public.rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_ping timestamptz not null default now(),
  left_at timestamptz,
  primary key (room_id, user_id)
);
create index if not exists room_presence_room_idx on public.room_presence(room_id, last_ping desc);
alter table public.room_presence enable row level security;
revoke all on public.room_presence from anon, authenticated;
grant all on public.room_presence to service_role;

create or replace function public._room_count(p_room bigint) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from room_presence where room_id = p_room and left_at is null and last_ping > now() - interval '90 seconds'
$$;

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
  insert into room_presence(room_id, user_id) values (p_room, me)
    on conflict (room_id, user_id) do update
      set joined_at = case when room_presence.left_at is not null or room_presence.last_ping < now() - interval '90 seconds'
                           then now() else room_presence.joined_at end,
          last_ping = now(), left_at = null;
  update rooms set listeners = _room_count(p_room) where id = p_room returning * into r;
  update profile_private set last_seen_at = now() where user_id = me;
  if not exists (select 1 from room_messages where room_id = p_room and user_id = me and kind = 'system'
                   and body = 'joined the room' and created_at > now() - interval '3 minutes') then
    insert into room_messages(room_id, user_id, kind, body) values (p_room, me, 'system', 'joined the room');
  end if;
  r.password_hash := null;
  return r;
end $$;

create or replace function public.leave_room(p_room bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  update room_seats set user_id = null where room_id = p_room and user_id = auth.uid() and seat <> 0;
  update room_presence set left_at = now() where room_id = p_room and user_id = auth.uid() and left_at is null;
  update rooms set listeners = _room_count(p_room) where id = p_room;
end $$;

-- the app calls this every 30 seconds while someone is in a room
create or replace function public.room_ping(p_room bigint)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update room_presence set last_ping = now() where room_id = p_room and user_id = auth.uid() and left_at is null;
  update profile_private set last_seen_at = now() where user_id = auth.uid();
  n := _room_count(p_room);
  update rooms set listeners = n where id = p_room and listeners <> n;
  return n;
end $$;

create or replace function public.room_people(p_room bigint)
returns jsonb language sql stable security definer set search_path = public as $$
  with x as (
    select rp.*, (rp.left_at is null and rp.last_ping > now() - interval '90 seconds') as here,
           coalesce(rp.left_at, rp.last_ping) as gone_at
      from room_presence rp where rp.room_id = p_room
  ), info as (
    select x.*, p.username, p.avatar_url, p.avatar_preset, p.wealth_level, p.public_id, p.role, p.verified,
           (select s.seat from room_seats s where s.room_id = p_room and s.user_id = x.user_id) as seat,
           (select r.owner_id = x.user_id from rooms r where r.id = p_room) as owner
      from x join profiles p on p.id = x.user_id
  )
  select jsonb_build_object(
    'active', coalesce((select jsonb_agg(jsonb_build_object('id', user_id, 'username', username, 'avatar_url', avatar_url,
                 'avatar_preset', avatar_preset, 'wealth_level', wealth_level, 'public_id', public_id, 'role', role,
                 'verified', verified, 'seat', seat, 'owner', owner, 'joined_at', joined_at)
               order by owner desc, seat nulls last, joined_at) from info where here), '[]'),
    'left', coalesce((select jsonb_agg(y order by y.left_at desc) from (
                 select user_id as id, username, avatar_url, avatar_preset, wealth_level, public_id, role, verified, owner,
                        joined_at, gone_at as left_at
                   from info where not here and gone_at > now() - interval '24 hours'
                   order by gone_at desc limit 100) y), '[]'))
$$;

-- ---------------------------------------------------------------- coin & diamond transfers
alter table public.agent_stock add column if not exists diamonds bigint not null default 0 check (diamonds >= 0);

create table if not exists public.coin_transfers (
  id bigint generated always as identity primary key,
  from_id uuid references public.profiles(id) on delete set null,
  to_id uuid references public.profiles(id) on delete set null,
  coins bigint not null default 0,
  diamonds bigint not null default 0,
  fee_coins bigint not null default 0,
  kind text not null check (kind in ('admin','agent','user','stock')),
  note text,
  created_at timestamptz not null default now()
);
create index if not exists coin_transfers_from_idx on public.coin_transfers(from_id, id desc);
create index if not exists coin_transfers_to_idx on public.coin_transfers(to_id, id desc);
alter table public.coin_transfers enable row level security;
revoke all on public.coin_transfers from anon, authenticated;
grant select on public.coin_transfers to authenticated;
grant all on public.coin_transfers to service_role;
create policy transfers_read on public.coin_transfers for select to authenticated using (from_id = auth.uid() or to_id = auth.uid() or is_admin());

create or replace function public.find_user(p_public bigint)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', id, 'username', username, 'public_id', public_id, 'avatar_url', avatar_url,
                            'avatar_preset', avatar_preset, 'wealth_level', wealth_level, 'role', role, 'verified', verified)
    from profiles where public_id = p_public and deleted_at is null
$$;

create or replace function public._public_to_id(p_public bigint) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare u uuid;
begin
  select id into u from profiles where public_id = p_public and deleted_at is null;
  if u is null then raise exception 'no user with ID %', p_public; end if;
  return u;
end $$;

-- admin: give (or take back) any amount of coins and diamonds, no limit
create or replace function public.admin_grant(p_user uuid, p_coins bigint, p_diamonds bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w wallets;
begin
  if not is_super_admin() then raise exception 'super admins only'; end if;
  if coalesce(p_coins, 0) = 0 and coalesce(p_diamonds, 0) = 0 then raise exception 'enter an amount'; end if;
  select * into w from wallets where user_id = p_user for update;
  if not found then raise exception 'user not found'; end if;
  if w.coins + coalesce(p_coins, 0) < 0 or w.diamonds + coalesce(p_diamonds, 0) < 0 then raise exception 'balance would go below zero'; end if;
  w := _wallet_add(p_user, coalesce(p_coins, 0), coalesce(p_diamonds, 0), 'admin_grant', nullif(p_reason, ''), jsonb_build_object('by', auth.uid()));
  insert into coin_transfers(from_id, to_id, coins, diamonds, kind, note) values (auth.uid(), p_user, coalesce(p_coins, 0), coalesce(p_diamonds, 0), 'admin', p_reason);
  if coalesce(p_coins, 0) > 0 or coalesce(p_diamonds, 0) > 0 then
    perform _notify(p_user, 'Gift from Adda 🎁',
      concat_ws(' and ', case when p_coins > 0 then p_coins || ' coins' end, case when p_diamonds > 0 then p_diamonds || ' diamonds' end) || ' added to your wallet',
      jsonb_build_object('type', 'wallet'));
  end if;
  perform _audit('grant', p_user::text, jsonb_build_object('coins', p_coins, 'diamonds', p_diamonds, 'reason', p_reason));
  return jsonb_build_object('coins', w.coins, 'diamonds', w.diamonds);
end $$;

-- admin: fill (or reduce) an agent's store
create or replace function public.admin_stock(p_agent uuid, p_coins bigint, p_diamonds bigint, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s agent_stock;
begin
  if not is_super_admin() then raise exception 'super admins only'; end if;
  if not exists (select 1 from profiles where id = p_agent and role in ('agent','admin')) then raise exception 'make this person an agent first'; end if;
  insert into agent_stock(agent_id) values (p_agent) on conflict do nothing;
  select * into s from agent_stock where agent_id = p_agent for update;
  if s.coins + coalesce(p_coins, 0) < 0 or s.diamonds + coalesce(p_diamonds, 0) < 0 then raise exception 'store would go below zero'; end if;
  update agent_stock set coins = coins + coalesce(p_coins, 0), diamonds = diamonds + coalesce(p_diamonds, 0) where agent_id = p_agent returning * into s;
  insert into coin_transfers(from_id, to_id, coins, diamonds, kind, note) values (auth.uid(), p_agent, coalesce(p_coins, 0), coalesce(p_diamonds, 0), 'stock', p_note);
  perform _audit('agent_stock', p_agent::text, jsonb_build_object('coins', p_coins, 'diamonds', p_diamonds));
  return jsonb_build_object('coins', s.coins, 'diamonds', s.diamonds);
end $$;

-- agents send from their store; admins send from an unlimited store
create or replace function public.store_transfer(p_to_public bigint, p_coins bigint, p_diamonds bigint, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); role_ user_role; to_id uuid; c bigint := greatest(coalesce(p_coins, 0), 0); d bigint := greatest(coalesce(p_diamonds, 0), 0); s agent_stock;
begin
  select role into role_ from profiles where id = me;
  if role_ not in ('agent','admin') then raise exception 'only agents can send from a store'; end if;
  if c = 0 and d = 0 then raise exception 'enter an amount'; end if;
  to_id := _public_to_id(p_to_public);
  if role_ = 'agent' then
    update agent_stock set coins = coins - c, diamonds = diamonds - d where agent_id = me and coins >= c and diamonds >= d returning * into s;
    if not found then raise exception 'not enough in your store'; end if;
  end if;
  perform _wallet_add(to_id, c, d, 'store_transfer', me::text, jsonb_build_object('from', me, 'role', role_));
  insert into coin_transfers(from_id, to_id, coins, diamonds, kind, note) values (me, to_id, c, d, case when role_ = 'admin' then 'admin' else 'agent' end, p_note);
  perform _notify(to_id, 'You received ' || concat_ws(' + ', case when c > 0 then c || ' coins' end, case when d > 0 then d || ' diamonds' end),
                  'From ' || (select username from profiles where id = me) || case when role_ = 'agent' then ' (coin agent)' else ' (Adda team)' end,
                  jsonb_build_object('type', 'wallet'));
  return jsonb_build_object('ok', true, 'store_coins', s.coins, 'store_diamonds', s.diamonds);
end $$;

create or replace function public.my_store()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'role', p.role,
    'unlimited', p.role = 'admin',
    'coins', coalesce(s.coins, 0),
    'diamonds', coalesce(s.diamonds, 0),
    'recent', coalesce((select jsonb_agg(t order by t.id desc) from (
        select ct.id, ct.coins, ct.diamonds, ct.kind, ct.note, ct.created_at, ct.from_id = auth.uid() as sent,
               pf.username as from_name, pt.username as to_name, pt.public_id as to_public
          from coin_transfers ct left join profiles pf on pf.id = ct.from_id left join profiles pt on pt.id = ct.to_id
         where (ct.from_id = auth.uid() and ct.kind in ('agent','admin')) or (ct.to_id = auth.uid() and ct.kind = 'stock')
         order by ct.id desc limit 40) t), '[]'))
  from profiles p left join agent_stock s on s.agent_id = p.id
  where p.id = auth.uid()
$$;

-- users send coins or diamonds to each other
create or replace function public.user_transfer(p_to_public bigint, p_coins bigint, p_diamonds bigint, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); to_id uuid; w wallets;
  c bigint := greatest(coalesce(p_coins, 0), 0); d bigint := greatest(coalesce(p_diamonds, 0), 0);
  fee bigint; sent_c bigint; sent_d bigint;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  if coalesce(setting('transfer_enabled'), 'true'::jsonb) <> 'true'::jsonb then raise exception 'transfers are switched off right now'; end if;
  if d > 0 and coalesce(setting('transfer_diamonds_enabled'), 'true'::jsonb) <> 'true'::jsonb then raise exception 'diamond transfers are switched off right now'; end if;
  if c = 0 and d = 0 then raise exception 'enter an amount'; end if;
  if c > 0 and c < setting_num('transfer_min_coins', 1000) then raise exception 'minimum is % coins', setting_num('transfer_min_coins', 1000); end if;
  to_id := _public_to_id(p_to_public);
  if to_id = me then raise exception 'you cannot send to yourself'; end if;
  if exists (select 1 from blocks where (blocker_id = to_id and blocked_id = me) or (blocker_id = me and blocked_id = to_id)) then raise exception 'you cannot send to this person'; end if;
  select coalesce(sum(coins), 0), coalesce(sum(diamonds), 0) into sent_c, sent_d from coin_transfers
   where from_id = me and kind = 'user' and created_at >= date_trunc('day', now());
  if sent_c + c > setting_num('transfer_daily_max_coins', 1000000000) then raise exception 'daily limit reached for coins'; end if;
  if sent_d + d > setting_num('transfer_daily_max_diamonds', 100000000) then raise exception 'daily limit reached for diamonds'; end if;
  fee := ceil(c * setting_num('transfer_fee_pct', 0) / 100.0)::bigint;
  select * into w from wallets where user_id = me for update;
  if w.coins < c + fee or w.diamonds < d then raise exception 'not enough balance'; end if;
  perform _wallet_add(me, -(c + fee), -d, 'transfer_out', to_id::text, jsonb_build_object('fee', fee));
  perform _wallet_add(to_id, c, d, 'transfer_in', me::text, '{}');
  insert into coin_transfers(from_id, to_id, coins, diamonds, fee_coins, kind, note) values (me, to_id, c, d, fee, 'user', left(p_note, 120));
  perform _notify(to_id, 'You received ' || concat_ws(' + ', case when c > 0 then c || ' coins' end, case when d > 0 then d || ' diamonds' end),
                  'From ' || (select username from profiles where id = me) || coalesce(': ' || nullif(left(p_note, 80), ''), ''),
                  jsonb_build_object('type', 'wallet'));
  return jsonb_build_object('ok', true, 'coins', w.coins - c - fee, 'diamonds', w.diamonds - d, 'fee', fee);
end $$;

create or replace function public.wallet_info()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'transfer_enabled', coalesce(setting('transfer_enabled'), 'true'::jsonb) = 'true'::jsonb,
    'transfer_diamonds_enabled', coalesce(setting('transfer_diamonds_enabled'), 'true'::jsonb) = 'true'::jsonb,
    'transfer_min_coins', setting_num('transfer_min_coins', 1000),
    'transfer_fee_pct', setting_num('transfer_fee_pct', 0),
    'coins_per_diamond', setting_num('coins_per_diamond', 2500000),
    'coin_exchange_enabled', coalesce(setting('coin_exchange_enabled'), 'true'::jsonb) = 'true'::jsonb,
    'diamond_to_coins', setting_num('diamond_to_coins', 1),
    'custom_topup_enabled', coalesce(setting('custom_topup_enabled'), 'true'::jsonb) = 'true'::jsonb,
    'custom_diamonds_enabled', coalesce(setting('custom_diamonds_enabled'), 'true'::jsonb) = 'true'::jsonb,
    'custom_min_coins', setting_num('custom_min_coins', 10000),
    'recent', coalesce((select jsonb_agg(t order by t.id desc) from (
        select ct.id, ct.coins, ct.diamonds, ct.fee_coins, ct.kind, ct.note, ct.created_at, ct.from_id = auth.uid() as sent,
               pf.username as from_name, pt.username as to_name
          from coin_transfers ct left join profiles pf on pf.id = ct.from_id left join profiles pt on pt.id = ct.to_id
         where (ct.from_id = auth.uid() or ct.to_id = auth.uid()) and ct.kind <> 'stock'
         order by ct.id desc limit 40) t), '[]'))
$$;

-- coins → diamonds (default 2,500,000 coins for 1 diamond)
create or replace function public.exchange_coins(p_diamonds bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); w wallets; rate bigint := setting_num('coins_per_diamond', 2500000)::bigint; cost bigint;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  if coalesce(setting('coin_exchange_enabled'), 'true'::jsonb) <> 'true'::jsonb then raise exception 'exchange is switched off right now'; end if;
  if p_diamonds < 1 then raise exception 'enter how many diamonds you want'; end if;
  cost := p_diamonds * rate;
  select * into w from wallets where user_id = me for update;
  if w.coins < cost then raise exception 'you need % coins for % diamonds', cost, p_diamonds; end if;
  perform _wallet_add(me, -cost, p_diamonds, 'exchange', 'coins', jsonb_build_object('rate', rate));
  return jsonb_build_object('coins', w.coins - cost, 'diamonds', w.diamonds + p_diamonds);
end $$;

-- ---------------------------------------------------------------- custom-amount top-ups
insert into public.coin_packs(id, usd, bdt, coins, active, sort) values ('custom', 0, 0, 1, false, 999) on conflict (id) do nothing;
alter table public.topup_orders add column if not exists kind text not null default 'coins';
alter table public.topup_orders add column if not exists diamonds bigint not null default 0;
alter table public.topup_orders add column if not exists usd numeric(12,2);

-- price for any number of coins: the per-coin rate of the biggest package that fits
-- (smaller than every package → the smallest package's rate)
create or replace function public.custom_price(p_coins bigint, out bdt numeric, out usd numeric)
language plpgsql stable security definer set search_path = public as $$
declare pk coin_packs;
begin
  select * into pk from coin_packs where active and id <> 'custom' and coins <= p_coins order by coins desc limit 1;
  if not found then select * into pk from coin_packs where active and id <> 'custom' order by coins limit 1; end if;
  if not found then raise exception 'no packages are set up'; end if;
  bdt := ceil(p_coins * pk.bdt / pk.coins);
  usd := round(ceil(p_coins * pk.usd / pk.coins * 100) / 100.0, 2);
end $$;

create or replace function public.custom_topup_quote(p_kind text, p_amount bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare equiv numeric; pr record;
begin
  if p_kind not in ('coins','diamonds') then raise exception 'choose coins or diamonds'; end if;
  if p_amount < 1 then raise exception 'enter an amount'; end if;
  equiv := case when p_kind = 'coins' then p_amount else p_amount * setting_num('coins_per_diamond', 2500000) end;
  if equiv < setting_num('custom_min_coins', 10000) then raise exception 'minimum is % coins', setting_num('custom_min_coins', 10000); end if;
  if equiv > 100000000000 then raise exception 'that is too large for one order'; end if;
  select * into pr from custom_price(equiv::bigint);
  return jsonb_build_object('kind', p_kind, 'amount', p_amount, 'coins_equiv', equiv, 'bdt', pr.bdt, 'usd', pr.usd);
end $$;

create or replace function public.create_custom_topup(p_kind text, p_amount bigint, p_method text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); q jsonb; acc agent_pay_accounts; o topup_orders; amt numeric;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  if coalesce(setting('custom_topup_enabled'), 'true'::jsonb) <> 'true'::jsonb then raise exception 'custom amounts are switched off right now'; end if;
  if p_kind = 'diamonds' and coalesce(setting('custom_diamonds_enabled'), 'true'::jsonb) <> 'true'::jsonb then raise exception 'buying diamonds is switched off right now'; end if;
  perform _expire_topups();
  if (select count(*) from topup_orders where user_id = me and status = 'awaiting_payment') >= 3 then
    raise exception 'finish or cancel your open top-ups first';
  end if;
  q := custom_topup_quote(p_kind, p_amount);
  select a.* into acc
    from agent_pay_accounts a join agent_stock s on s.agent_id = a.agent_id join profiles p on p.id = a.agent_id
   where a.active and a.method = p_method and s.accepts_topups and p.role in ('agent','admin')
     and (case when p_kind = 'coins' then s.coins >= p_amount else s.diamonds >= p_amount end)
   order by (select count(*) from topup_orders t where t.agent_id = a.agent_id and t.status in ('awaiting_payment','submitted')), random()
   limit 1;
  if not found then raise exception 'no agent can fill this amount on % right now, try a smaller amount or another method', p_method; end if;
  amt := case when acc.currency = 'USD' then (q->>'usd')::numeric else (q->>'bdt')::numeric end;
  insert into topup_orders(user_id, pack_id, coins, diamonds, kind, amount, usd, currency, method, pay_account_id, pay_to, agent_id)
  values (me, 'custom', case when p_kind = 'coins' then p_amount else 0 end, case when p_kind = 'diamonds' then p_amount else 0 end,
          p_kind, amt, (q->>'usd')::numeric, acc.currency, p_method, acc.id, acc.account_number, acc.agent_id)
  returning * into o;
  return jsonb_build_object('id', o.id, 'coins', o.coins, 'diamonds', o.diamonds, 'kind', o.kind, 'amount', o.amount, 'currency', o.currency,
    'method', o.method, 'pay_to', acc.account_number, 'account_name', acc.account_name, 'account_type', acc.account_type,
    'instructions', acc.instructions, 'discount_pct', 0,
    'expires_at', o.created_at + make_interval(mins => setting_num('topup_order_minutes', 30)::int));
end $$;

-- approving now handles diamond orders and custom amounts too
create or replace function public.approve_topup(p_order uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o topup_orders; usd numeric; pid uuid;
begin
  select * into o from topup_orders where id = p_order for update;
  if not found then raise exception 'order not found'; end if;
  if not can_handle_topup(o) then raise exception 'this order is assigned to another agent'; end if;
  if o.status not in ('submitted','awaiting_payment','expired') then raise exception 'this order is already %', o.status; end if;
  if o.agent_id is null then raise exception 'assign an agent first'; end if;

  if o.kind = 'diamonds' then
    update agent_stock set diamonds = diamonds - o.diamonds where agent_id = o.agent_id and diamonds >= o.diamonds;
  else
    update agent_stock set coins = coins - o.coins where agent_id = o.agent_id and coins >= o.coins;
  end if;
  if not found then raise exception 'the agent does not have enough % in stock', o.kind; end if;

  perform _wallet_add(o.user_id, o.coins, o.diamonds, 'topup', o.id::text, jsonb_build_object('provider', 'agent', 'method', o.method, 'agent', o.agent_id, 'kind', o.kind));
  usd := coalesce(o.usd, (select c.usd from coin_packs c where c.id = o.pack_id));
  update profiles set lifetime_usd = lifetime_usd + coalesce(usd, 0) where id = o.user_id;
  insert into payments(user_id, provider, pack_id, amount, currency, coins, status, provider_ref, raw, paid_at)
  values (o.user_id, 'agent', o.pack_id, o.amount, o.currency, o.coins, 'paid', o.id::text,
          jsonb_build_object('method', o.method, 'trx_id', o.trx_id, 'sender', o.sender_number, 'agent', o.agent_id, 'kind', o.kind, 'diamonds', o.diamonds), now())
  returning id into pid;
  if o.coins > 0 then
    insert into agent_sales(agent_id, buyer_id, coins, method, amount_local) values (o.agent_id, o.user_id, o.coins, o.method, o.amount);
  end if;
  update topup_orders set status = 'approved', handled_at = now(), handled_by = auth.uid() where id = p_order;
  perform _notify(o.user_id, 'Top-up successful',
    case when o.kind = 'diamonds' then o.diamonds || ' diamonds were added to your wallet' else o.coins || ' coins were added to your wallet' end,
    jsonb_build_object('type', 'topup', 'order', o.id));
  if is_super_admin() and o.agent_id <> auth.uid() then perform _audit('approve_topup', o.id::text, jsonb_build_object('agent', o.agent_id)); end if;
  return jsonb_build_object('ok', true, 'payment', pid);
end $$;

-- admin list of stores (coins and diamonds) for the console
create or replace function public.agent_stores()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('agent_id', p.id, 'username', p.username, 'public_id', p.public_id, 'role', p.role,
           'coins', coalesce(s.coins, 0), 'diamonds', coalesce(s.diamonds, 0), 'accepts_topups', coalesce(s.accepts_topups, false),
           'sent_today', (select coalesce(sum(t.coins), 0) from coin_transfers t where t.from_id = p.id and t.kind = 'agent' and t.created_at >= date_trunc('day', now())))
         order by p.role, p.username), '[]')
  from profiles p left join agent_stock s on s.agent_id = p.id
  where p.role in ('agent','admin') and is_admin()
$$;

revoke execute on function public._room_count(bigint), public._public_to_id(bigint) from public, anon, authenticated;
revoke execute on function public.touch_presence(), public.user_presence(uuid[]), public.set_presence_privacy(boolean), public.room_ping(bigint),
  public.room_people(bigint), public.find_user(bigint), public.admin_grant(uuid,bigint,bigint,text), public.admin_stock(uuid,bigint,bigint,text),
  public.store_transfer(bigint,bigint,bigint,text), public.my_store(), public.user_transfer(bigint,bigint,bigint,text), public.wallet_info(),
  public.exchange_coins(bigint), public.custom_price(bigint), public.custom_topup_quote(text,bigint), public.create_custom_topup(text,bigint,text),
  public.agent_stores() from public, anon;
grant execute on function public.touch_presence(), public.user_presence(uuid[]), public.set_presence_privacy(boolean), public.room_ping(bigint),
  public.room_people(bigint), public.find_user(bigint), public.admin_grant(uuid,bigint,bigint,text), public.admin_stock(uuid,bigint,bigint,text),
  public.store_transfer(bigint,bigint,bigint,text), public.my_store(), public.user_transfer(bigint,bigint,bigint,text), public.wallet_info(),
  public.exchange_coins(bigint), public.custom_price(bigint), public.custom_topup_quote(text,bigint), public.create_custom_topup(text,bigint,text),
  public.agent_stores() to authenticated, service_role;
