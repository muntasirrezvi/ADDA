-- Adda: agent top-ups.
-- The owner chooses a few agent accounts that receive payments (bKash, Nagad, Rocket, bank, USDT).
-- 1. A user picks a pack and a method; the app shows one agent's number and the exact amount.
-- 2. The user sends the money and enters the transaction ID (and optionally a screenshot).
-- 3. The agent (or the owner) checks their bKash/Nagad statement and approves:
--    the coins move from that agent's coin stock to the user. Everything is logged.

alter table public.agent_stock add column if not exists accepts_topups boolean not null default false;
alter table public.agent_stock add column if not exists display_name text;

create table public.agent_pay_accounts (
  id bigint generated always as identity primary key,
  agent_id uuid not null references public.profiles(id) on delete cascade,
  method text not null check (method in ('bkash','nagad','rocket','upay','bank','usdt')),
  currency text not null default 'BDT' check (currency in ('BDT','USD')),
  account_number text not null,
  account_name text,
  account_type text not null default 'personal' check (account_type in ('personal','agent','merchant','wallet')),
  instructions text,                 -- e.g. "Send Money only, not Cash Out"
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index agent_pay_accounts_method_idx on public.agent_pay_accounts(method) where active;

create table public.topup_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  pack_id text not null references public.coin_packs(id),
  coins bigint not null,
  amount numeric(12,2) not null,
  currency text not null,
  method text not null,
  pay_account_id bigint references public.agent_pay_accounts(id) on delete set null,
  pay_to text not null,              -- the number shown to the user (kept even if the account is later removed)
  agent_id uuid references public.profiles(id) on delete set null,
  status text not null default 'awaiting_payment'
    check (status in ('awaiting_payment','submitted','approved','rejected','expired','cancelled')),
  sender_number text,
  trx_id text,
  proof_path text,
  note text,
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  handled_at timestamptz,
  handled_by uuid references public.profiles(id)
);
create index topup_orders_user_idx on public.topup_orders(user_id, created_at desc);
create index topup_orders_agent_idx on public.topup_orders(agent_id, status, created_at);
create index topup_orders_status_idx on public.topup_orders(status, created_at);
-- the same bKash/Nagad transaction can never be claimed twice
create unique index topup_orders_trx_key on public.topup_orders(method, upper(trx_id)) where trx_id is not null and status <> 'rejected';

insert into public.app_settings(key, value) values
  ('pay_agent_enabled', 'true'),
  ('pay_sslcommerz_enabled', 'false'),
  ('pay_play_enabled', 'false'),
  ('topup_order_minutes', '30'),
  ('privacy_url', '""'),
  ('terms_url', '""')
on conflict (key) do nothing;

create or replace function public._expire_topups() returns void
language sql security definer set search_path = public as $$
  update topup_orders set status = 'expired'
   where status = 'awaiting_payment' and created_at < now() - make_interval(mins => setting_num('topup_order_minutes', 30)::int)
$$;

-- methods the app can offer right now (no numbers revealed until an order is made)
create or replace function public.topup_methods()
returns table (method text, currency text)
language sql stable security definer set search_path = public as $$
  select distinct a.method, a.currency
    from agent_pay_accounts a join agent_stock s on s.agent_id = a.agent_id
    join profiles p on p.id = a.agent_id
   where a.active and s.accepts_topups and p.role in ('agent','admin') and s.coins > 0
     and (setting('pay_agent_enabled') is null or setting('pay_agent_enabled') = 'true'::jsonb)
$$;

create or replace function public.create_topup_order(p_pack text, p_method text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pk coin_packs; d int; acc agent_pay_accounts; o topup_orders; amt numeric;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  perform _expire_topups();
  if (select count(*) from topup_orders where user_id = me and status = 'awaiting_payment') >= 3 then
    raise exception 'finish or cancel your open top-ups first';
  end if;
  select * into pk from coin_packs where id = p_pack and active;
  if not found then raise exception 'pack not found'; end if;

  -- pick the agent account with enough stock and the fewest open orders
  select a.* into acc
    from agent_pay_accounts a join agent_stock s on s.agent_id = a.agent_id join profiles p on p.id = a.agent_id
   where a.active and a.method = p_method and s.accepts_topups and p.role in ('agent','admin') and s.coins >= pk.coins
   order by (select count(*) from topup_orders t where t.agent_id = a.agent_id and t.status in ('awaiting_payment','submitted')), random()
   limit 1;
  if not found then raise exception 'this payment method is busy right now, try another one'; end if;

  d := discount_for(me, p_pack);
  amt := case when acc.currency = 'USD' then round(pk.usd * (100 - d) / 100.0, 2) else round(pk.bdt * (100 - d) / 100.0, 0) end;
  insert into topup_orders(user_id, pack_id, coins, amount, currency, method, pay_account_id, pay_to, agent_id)
  values (me, p_pack, pk.coins, amt, acc.currency, p_method, acc.id, acc.account_number, acc.agent_id)
  returning * into o;

  return jsonb_build_object('id', o.id, 'coins', o.coins, 'amount', o.amount, 'currency', o.currency, 'method', o.method,
    'pay_to', acc.account_number, 'account_name', acc.account_name, 'account_type', acc.account_type,
    'instructions', acc.instructions, 'discount_pct', d,
    'expires_at', o.created_at + make_interval(mins => setting_num('topup_order_minutes', 30)::int));
end $$;

create or replace function public.submit_topup_proof(p_order uuid, p_sender text, p_trx text, p_proof text default null)
returns public.topup_orders language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); o topup_orders; nm text;
begin
  perform _expire_topups();
  select * into o from topup_orders where id = p_order and user_id = me for update;
  if not found then raise exception 'order not found'; end if;
  if o.status <> 'awaiting_payment' then raise exception 'this order is %', replace(o.status, '_', ' '); end if;
  p_trx := upper(regexp_replace(coalesce(p_trx, ''), '\s', '', 'g'));
  if p_trx !~ '^[A-Z0-9]{6,30}$' then raise exception 'enter the transaction ID from your payment message'; end if;
  if coalesce(trim(p_sender), '') = '' then raise exception 'enter the number or account you paid from'; end if;
  if p_proof is not null and split_part(p_proof, '/', 1) <> me::text then raise exception 'upload the screenshot to your own folder'; end if;
  if exists (select 1 from topup_orders where method = o.method and upper(trx_id) = p_trx and status <> 'rejected') then
    raise exception 'this transaction ID was already used';
  end if;
  update topup_orders set status = 'submitted', sender_number = trim(p_sender), trx_id = p_trx, proof_path = p_proof, submitted_at = now()
   where id = p_order returning * into o;
  select username into nm from profiles where id = me;
  perform _notify(o.agent_id, 'New top-up to check', nm || ' paid ' || o.amount || ' ' || o.currency || ' by ' || o.method || ' · TrxID ' || p_trx,
    jsonb_build_object('type', 'topup_order', 'order', o.id));
  return o;
end $$;

create or replace function public.cancel_topup_order(p_order uuid)
returns void language sql security definer set search_path = public as $$
  update topup_orders set status = 'cancelled' where id = p_order and user_id = auth.uid() and status = 'awaiting_payment'
$$;

create or replace function public.can_handle_topup(o public.topup_orders) returns boolean
language sql stable security definer set search_path = public as $$
  select is_super_admin() or (o.agent_id = auth.uid() and exists (select 1 from profiles where id = auth.uid() and role = 'agent'))
$$;

-- approve: coins move from the assigned agent's stock to the user
create or replace function public.approve_topup(p_order uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o topup_orders; usd numeric; pid uuid;
begin
  select * into o from topup_orders where id = p_order for update;
  if not found then raise exception 'order not found'; end if;
  if not can_handle_topup(o) then raise exception 'this order is assigned to another agent'; end if;
  if o.status not in ('submitted','awaiting_payment','expired') then raise exception 'this order is already %', o.status; end if;
  if o.agent_id is null then raise exception 'assign an agent first'; end if;

  update agent_stock set coins = coins - o.coins where agent_id = o.agent_id and coins >= o.coins;
  if not found then raise exception 'the agent does not have enough coin stock'; end if;

  perform _wallet_add(o.user_id, o.coins, 0, 'topup', o.id::text, jsonb_build_object('provider', 'agent', 'method', o.method, 'agent', o.agent_id));
  select c.usd into usd from coin_packs c where c.id = o.pack_id;
  update profiles set lifetime_usd = lifetime_usd + coalesce(usd, 0) where id = o.user_id;
  insert into payments(user_id, provider, pack_id, amount, currency, coins, status, provider_ref, raw, paid_at)
  values (o.user_id, 'agent', o.pack_id, o.amount, o.currency, o.coins, 'paid', o.id::text,
          jsonb_build_object('method', o.method, 'trx_id', o.trx_id, 'sender', o.sender_number, 'agent', o.agent_id), now())
  returning id into pid;
  insert into agent_sales(agent_id, buyer_id, coins, method, amount_local) values (o.agent_id, o.user_id, o.coins, o.method, o.amount);
  update topup_orders set status = 'approved', handled_at = now(), handled_by = auth.uid() where id = p_order;
  perform _notify(o.user_id, 'Top-up successful', o.coins || ' coins were added to your wallet', jsonb_build_object('type', 'topup', 'order', o.id));
  if is_super_admin() and o.agent_id <> auth.uid() then perform _audit('approve_topup', o.id::text, jsonb_build_object('agent', o.agent_id)); end if;
  return jsonb_build_object('ok', true, 'payment', pid);
end $$;

create or replace function public.reject_topup(p_order uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare o topup_orders;
begin
  select * into o from topup_orders where id = p_order for update;
  if not found then raise exception 'order not found'; end if;
  if not can_handle_topup(o) then raise exception 'this order is assigned to another agent'; end if;
  if o.status not in ('submitted','awaiting_payment') then raise exception 'this order is already %', o.status; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'give the user a reason'; end if;
  update topup_orders set status = 'rejected', note = p_reason, handled_at = now(), handled_by = auth.uid() where id = p_order;
  perform _notify(o.user_id, 'Top-up not approved', p_reason, jsonb_build_object('type', 'topup', 'order', o.id));
  if is_super_admin() then perform _audit('reject_topup', o.id::text, jsonb_build_object('reason', p_reason)); end if;
end $$;

-- owner: move an order to another agent (e.g. the money went to a different number)
create or replace function public.admin_assign_topup(p_order uuid, p_agent uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_super_admin() then raise exception 'super admins only'; end if;
  if not exists (select 1 from agent_stock where agent_id = p_agent) then raise exception 'not an agent'; end if;
  update topup_orders set agent_id = p_agent where id = p_order and status in ('awaiting_payment','submitted','expired');
  if not found then raise exception 'order cannot be reassigned'; end if;
  perform _notify(p_agent, 'Top-up assigned to you', 'Please check order ' || left(p_order::text, 8), jsonb_build_object('type', 'topup_order', 'order', p_order));
  perform _audit('assign_topup', p_order::text, jsonb_build_object('agent', p_agent));
end $$;

create or replace function public.admin_set_topup_agent(p_agent uuid, p_accepts boolean, p_name text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_super_admin() then raise exception 'super admins only'; end if;
  update agent_stock set accepts_topups = p_accepts, display_name = coalesce(p_name, display_name) where agent_id = p_agent;
  if not found then raise exception 'make this user an agent first'; end if;
  perform _audit('topup_agent', p_agent::text, jsonb_build_object('accepts', p_accepts));
end $$;

-- per-agent summary for the console
create or replace function public.agent_overview()
returns table (agent_id uuid, username text, public_id bigint, display_name text, coins bigint, accepts_topups boolean,
               waiting bigint, approved_today bigint, coins_today bigint)
language sql stable security definer set search_path = public as $$
  select s.agent_id, p.username, p.public_id, s.display_name, s.coins, s.accepts_topups,
    (select count(*) from topup_orders t where t.agent_id = s.agent_id and t.status = 'submitted'),
    (select count(*) from topup_orders t where t.agent_id = s.agent_id and t.status = 'approved' and t.handled_at::date = current_date),
    (select coalesce(sum(t.coins), 0) from topup_orders t where t.agent_id = s.agent_id and t.status = 'approved' and t.handled_at::date = current_date)::bigint
  from agent_stock s join profiles p on p.id = s.agent_id
  where is_admin() or s.agent_id = auth.uid()
  order by s.accepts_topups desc, p.username
$$;

-- ---------- access rules ----------
alter table public.agent_pay_accounts enable row level security;
alter table public.topup_orders enable row level security;
revoke all on public.agent_pay_accounts, public.topup_orders from anon, authenticated;
grant all on public.agent_pay_accounts, public.topup_orders to service_role;

grant select on public.topup_orders to authenticated;
create policy topup_read on public.topup_orders for select to authenticated
  using (user_id = auth.uid() or agent_id = auth.uid() or public.is_admin());

grant select, insert, update, delete on public.agent_pay_accounts to authenticated;
create policy payacc_read on public.agent_pay_accounts for select to authenticated using (agent_id = auth.uid() or public.is_admin());
create policy payacc_admin on public.agent_pay_accounts for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());

-- payment screenshots: private; the user, the assigned agent and admins can see them
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-proofs', 'payment-proofs', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;
create policy "upload payment proof" on storage.objects for insert to authenticated
  with check (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "read payment proof" on storage.objects for select to authenticated
  using (bucket_id = 'payment-proofs' and (
    (storage.foldername(name))[1] = auth.uid()::text or public.is_admin()
    or exists (select 1 from public.topup_orders t where t.proof_path = storage.objects.name and t.agent_id = auth.uid())));

alter publication supabase_realtime add table public.topup_orders;

revoke execute on function public._expire_topups(), public.can_handle_topup(public.topup_orders) from public, anon, authenticated;
revoke execute on function public.topup_methods(), public.create_topup_order(text,text), public.submit_topup_proof(uuid,text,text,text),
  public.cancel_topup_order(uuid), public.approve_topup(uuid), public.reject_topup(uuid,text), public.admin_assign_topup(uuid,uuid),
  public.admin_set_topup_agent(uuid,boolean,text), public.agent_overview() from public, anon;
grant execute on function public.topup_methods(), public.create_topup_order(text,text), public.submit_topup_proof(uuid,text,text,text),
  public.cancel_topup_order(uuid), public.approve_topup(uuid), public.reject_topup(uuid,text), public.admin_assign_topup(uuid,uuid),
  public.admin_set_topup_agent(uuid,boolean,text), public.agent_overview() to authenticated, service_role;

-- ---------- rooms: owner can close their room; keep room rows out of realtime ----------
-- (realtime payloads would include every column, so rooms are refreshed by polling instead)
alter publication supabase_realtime drop table public.rooms;

create or replace function public.close_room(p_room bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  update rooms set status = 'closed', listeners = 0 where id = p_room and (owner_id = auth.uid() or is_admin()) and status = 'open';
  if not found then raise exception 'only the owner can close this room'; end if;
  update room_seats set user_id = null where room_id = p_room;
  insert into room_messages(room_id, user_id, kind, body) values (p_room, auth.uid(), 'system', 'The host closed the room');
end $$;
revoke execute on function public.close_room(bigint) from public, anon;
grant execute on function public.close_room(bigint) to authenticated, service_role;

-- reopening: create_room refuses a second open room, so let the owner reopen a closed one
create or replace function public.reopen_room(p_room bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from rooms where owner_id = auth.uid() and status = 'open') then raise exception 'you already have an open room'; end if;
  update rooms set status = 'open' where id = p_room and owner_id = auth.uid() and status = 'closed';
  if not found then raise exception 'room cannot be reopened'; end if;
  update room_seats set user_id = auth.uid() where room_id = p_room and seat = 0;
end $$;
revoke execute on function public.reopen_room(bigint) from public, anon;
grant execute on function public.reopen_room(bigint) to authenticated, service_role;
