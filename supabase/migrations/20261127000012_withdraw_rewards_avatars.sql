-- Adda: diamond withdrawals with admin-set rules, 7-day growing daily reward,
-- AI avatars made from a photo, and a full user profile for the admin console.

insert into public.app_settings(key, value) values
  ('withdraw_enabled', 'true'),
  ('withdraw_require_verified', 'true'),
  ('withdraw_require_phone', 'false'),
  ('withdraw_min_account_days', '7'),
  ('withdraw_cooldown_hours', '24'),
  ('withdraw_daily_max_diamonds', '62500000'),
  ('withdraw_fee_pct', '0'),
  ('withdraw_methods', '["bkash","nagad","rocket","bank"]'),
  ('checkin_base', '10000'),
  ('checkin_growth', '0.2'),
  ('checkin_cycle', '7'),
  ('ai_avatar_enabled', 'true'),
  ('ai_avatar_daily_limit', '3')
on conflict (key) do nothing;

-- ---------------------------------------------------------------- withdrawals
alter table public.payouts add column if not exists amount_bdt numeric(12,2);
alter table public.payouts add column if not exists fee_usd numeric(10,2) not null default 0;
alter table public.payouts add column if not exists holder_name text;
alter table public.payouts add column if not exists note text;
alter table public.payouts add column if not exists paid_ref text;

-- every rule a withdrawal must pass, with a plain-language label the app shows as a checklist
create or replace function public._withdraw_checks(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  pr profiles; pv profile_private; w wallets; res jsonb := '[]';
  days int := setting_num('withdraw_min_account_days', 7)::int;
  cool int := setting_num('withdraw_cooldown_hours', 24)::int;
  mn bigint := setting_num('min_payout_diamonds', 6250000)::bigint;
  last_at timestamptz;
begin
  select * into pr from profiles where id = p_user;
  select * into pv from profile_private where user_id = p_user;
  select * into w from wallets where user_id = p_user;
  res := res || jsonb_build_object('key', 'enabled', 'label', 'Withdrawals are open',
           'ok', coalesce(setting('withdraw_enabled'), 'true'::jsonb) = 'true'::jsonb);
  res := res || jsonb_build_object('key', 'active', 'label', 'Account in good standing',
           'ok', pr.deleted_at is null and (pr.banned_until is null or pr.banned_until < now()));
  if coalesce(setting('withdraw_require_verified'), 'true'::jsonb) = 'true'::jsonb then
    res := res || jsonb_build_object('key', 'verified', 'label', 'Identity verified', 'ok', coalesce(pr.verified, false));
  end if;
  if coalesce(setting('withdraw_require_phone'), 'false'::jsonb) = 'true'::jsonb then
    res := res || jsonb_build_object('key', 'phone', 'label', 'Phone number verified', 'ok', coalesce(pv.phone_verified, false));
  end if;
  if days > 0 then
    res := res || jsonb_build_object('key', 'age', 'label', 'Account at least ' || days || ' days old',
             'ok', pr.created_at <= now() - make_interval(days => days),
             'detail', greatest(0, days - floor(extract(epoch from now() - pr.created_at) / 86400)::int) || ' days to go');
  end if;
  res := res || jsonb_build_object('key', 'balance', 'label', 'At least ' || mn || ' diamonds', 'ok', coalesce(w.diamonds, 0) >= mn,
           'detail', greatest(0, mn - coalesce(w.diamonds, 0)) || ' more needed');
  res := res || jsonb_build_object('key', 'pending', 'label', 'No other withdrawal in progress',
           'ok', not exists (select 1 from payouts where user_id = p_user and status in ('pending','approved')));
  if cool > 0 then
    select max(created_at) into last_at from payouts where user_id = p_user and status <> 'rejected';
    res := res || jsonb_build_object('key', 'cooldown', 'label', 'One withdrawal every ' || cool || ' hours',
             'ok', last_at is null or last_at <= now() - make_interval(hours => cool),
             'detail', case when last_at is null then null
                            else 'next after ' || to_char(last_at + make_interval(hours => cool), 'DD Mon HH24:MI') || ' UTC' end);
  end if;
  return res;
end $$;

create or replace function public.withdraw_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); checks jsonb; w wallets; today bigint;
begin
  if me is null then raise exception 'sign in first'; end if;
  checks := _withdraw_checks(me);
  select * into w from wallets where user_id = me;
  select coalesce(sum(diamonds), 0) into today from payouts where user_id = me and status <> 'rejected' and created_at >= date_trunc('day', now());
  return jsonb_build_object(
    'diamonds', coalesce(w.diamonds, 0),
    'diamonds_per_usd', setting_num('diamonds_per_usd', 625000),
    'usd_to_bdt', setting_num('usd_to_bdt', 120),
    'fee_pct', setting_num('withdraw_fee_pct', 0),
    'min', setting_num('min_payout_diamonds', 6250000),
    'daily_max', setting_num('withdraw_daily_max_diamonds', 62500000),
    'used_today', today,
    'methods', coalesce(setting('withdraw_methods'), '["bkash","nagad","rocket","bank"]'::jsonb),
    'checks', checks,
    'can', not exists (select 1 from jsonb_array_elements(checks) c where (c->>'ok')::boolean is not true)
  );
end $$;

create or replace function public.request_withdrawal(p_diamonds bigint, p_method text, p_account text, p_name text default null)
returns public.payouts language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); w wallets; p payouts; failed text; today bigint;
  per_usd numeric := setting_num('diamonds_per_usd', 625000);
  fee numeric := setting_num('withdraw_fee_pct', 0);
  mx bigint := setting_num('withdraw_daily_max_diamonds', 62500000)::bigint;
  gross numeric; fee_usd numeric;
begin
  if me is null then raise exception 'sign in first'; end if;
  select c->>'label' into failed from jsonb_array_elements(_withdraw_checks(me)) c where (c->>'ok')::boolean is not true limit 1;
  if failed is not null then raise exception 'Not yet: %', failed; end if;
  if p_diamonds < setting_num('min_payout_diamonds', 6250000) then raise exception 'below the minimum withdrawal'; end if;
  if not coalesce(setting('withdraw_methods'), '["bkash","nagad","rocket","bank"]'::jsonb) ? p_method then raise exception 'that payment method is not available'; end if;
  if coalesce(trim(p_account), '') = '' or char_length(p_account) > 80 then raise exception 'enter the account number'; end if;
  select coalesce(sum(diamonds), 0) into today from payouts where user_id = me and status <> 'rejected' and created_at >= date_trunc('day', now());
  if today + p_diamonds > mx then raise exception 'daily limit is % diamonds (% left today)', mx, greatest(0, mx - today); end if;
  select * into w from wallets where user_id = me for update;
  if w.diamonds < p_diamonds then raise exception 'not enough diamonds'; end if;
  gross := round(p_diamonds / per_usd, 2);
  fee_usd := round(gross * fee / 100, 2);
  perform _wallet_add(me, 0, -p_diamonds, 'payout', 'hold');
  insert into payouts(user_id, diamonds, amount_usd, fee_usd, amount_bdt, method, account, holder_name)
    values (me, p_diamonds, gross - fee_usd, fee_usd, round((gross - fee_usd) * setting_num('usd_to_bdt', 120), 2),
            p_method, trim(p_account), nullif(trim(coalesce(p_name, '')), ''))
    returning * into p;
  return p;
end $$;

-- the old entry point now follows the same rules
create or replace function public.request_payout(p_diamonds bigint, p_method text, p_account text)
returns public.payouts language sql security definer set search_path = public as $$
  select * from request_withdrawal(p_diamonds, p_method, p_account, null)
$$;

create or replace function public.admin_update_payout(p_id bigint, p_status text, p_note text default null, p_ref text default null)
returns void language plpgsql security definer set search_path = public as $$
declare p payouts;
begin
  if not is_super_admin() then raise exception 'super admins only'; end if;
  if p_status not in ('approved','paid','rejected') then raise exception 'bad status'; end if;
  select * into p from payouts where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if p.status in ('paid','rejected') then raise exception 'already closed'; end if;
  update payouts set status = p_status, processed_at = now(), processed_by = auth.uid(),
         note = coalesce(nullif(p_note, ''), note), paid_ref = coalesce(nullif(p_ref, ''), paid_ref)
   where id = p_id;
  if p_status = 'rejected' then perform _wallet_add(p.user_id, 0, p.diamonds, 'payout', 'refund'); end if;
  perform _notify(p.user_id,
    case p_status when 'paid' then 'Withdrawal sent 💸' when 'approved' then 'Withdrawal approved' else 'Withdrawal rejected' end,
    case p_status when 'rejected' then coalesce(nullif(p_note, ''), 'Your diamonds were returned.')
         else coalesce(p.amount_bdt::text || ' BDT', '$' || p.amount_usd) || ' via ' || p.method
              || case when p_ref is not null and p_ref <> '' then ' · ref ' || p_ref else '' end end,
    jsonb_build_object('type', 'payout', 'id', p_id));
  perform _audit('payout_' || p_status, p_id::text, jsonb_build_object('note', p_note, 'ref', p_ref));
end $$;

-- ---------------------------------------------------------------- daily reward: 7 days, growing 20% a day
alter table public.daily_checkins add column if not exists streak_day int not null default 1;

create or replace function public._checkin_amount(p_day int) returns bigint
language sql stable set search_path = public as $$
  select round(setting_num('checkin_base', 10000) * power(1 + setting_num('checkin_growth', 0.2), greatest(p_day, 1) - 1))::bigint
$$;

-- which day of the cycle today's claim is, and whether it has been claimed already
create or replace function public._checkin_state(p_user uuid, out o_claimed boolean, out o_day int)
language plpgsql stable security definer set search_path = public as $$
declare last daily_checkins; cyc int := greatest(1, setting_num('checkin_cycle', 7)::int);
begin
  select * into last from daily_checkins d where d.user_id = p_user order by d.day desc limit 1;
  if last.day = current_date then
    o_claimed := true; o_day := last.streak_day;
  elsif last.day = current_date - 1 then
    o_claimed := false; o_day := last.streak_day % cyc + 1;
  else
    o_claimed := false; o_day := 1;
  end if;
end $$;

create or replace function public.checkin_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); s record; cyc int := greatest(1, setting_num('checkin_cycle', 7)::int); days jsonb := '[]';
begin
  if me is null then raise exception 'sign in first'; end if;
  select * into s from _checkin_state(me);
  for i in 1 .. cyc loop
    days := days || jsonb_build_object('day', i, 'amount', _checkin_amount(i),
      'state', case when i < s.o_day or (i = s.o_day and s.o_claimed) then 'claimed'
                    when i = s.o_day then 'today' else 'upcoming' end);
  end loop;
  return jsonb_build_object('day', s.o_day, 'claimed_today', s.o_claimed, 'days', days,
                            'next_at', (current_date + 1)::timestamptz);
end $$;

create or replace function public.daily_checkin()
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); s record; reward bigint;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  perform pg_advisory_xact_lock(hashtext('checkin' || me::text));
  select * into s from _checkin_state(me);
  if s.o_claimed then return jsonb_build_object('ok', false, 'error', 'Already collected today — come back tomorrow'); end if;
  reward := _checkin_amount(s.o_day);
  insert into daily_checkins(user_id, reward, streak_day) values (me, reward, s.o_day);
  perform _wallet_add(me, reward, 0, 'reward', 'checkin', jsonb_build_object('day', s.o_day));
  return jsonb_build_object('ok', true, 'reward', reward, 'day', s.o_day);
end $$;

-- ---------------------------------------------------------------- AI avatars
create table if not exists public.ai_avatars (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  image_url text not null,
  style text not null,
  created_at timestamptz not null default now()
);
create index if not exists ai_avatars_user_idx on public.ai_avatars(user_id, id desc);
alter table public.ai_avatars enable row level security;
revoke all on public.ai_avatars from anon, authenticated;
grant select on public.ai_avatars to authenticated;
grant all on public.ai_avatars to service_role;
create policy ai_avatars_own on public.ai_avatars for select to authenticated using (user_id = auth.uid() or is_admin());

create or replace function public.ai_avatar_quota()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'enabled', coalesce(setting('ai_avatar_enabled'), 'true'::jsonb) = 'true'::jsonb,
    'limit', setting_num('ai_avatar_daily_limit', 3),
    'used', (select count(*) from ai_avatars where user_id = auth.uid() and created_at >= date_trunc('day', now())))
$$;

-- ---------------------------------------------------------------- admin: everything about one user
create or replace function public.admin_user_detail(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a jsonb;
begin
  if not is_admin() then raise exception 'admins only'; end if;
  select to_jsonb(u) into a from auth.users u where u.id = p_user;
  return jsonb_build_object(
    'profile', (select to_jsonb(p) from profiles p where p.id = p_user),
    'private', (select to_jsonb(v) - 'user_id' from profile_private v where v.user_id = p_user),
    'auth', jsonb_build_object('email', a->'email', 'phone', a->'phone', 'created_at', a->'created_at',
                               'last_sign_in_at', a->'last_sign_in_at', 'email_confirmed_at', a->'email_confirmed_at',
                               'phone_confirmed_at', a->'phone_confirmed_at', 'providers', a->'raw_app_meta_data'->'providers',
                               'signup_data', a->'raw_user_meta_data'),
    'wallet', (select to_jsonb(w) - 'user_id' from wallets w where w.user_id = p_user),
    'stats', jsonb_build_object(
      'followers', (select count(*) from user_follows where followee_id = p_user),
      'following', (select count(*) from user_follows where follower_id = p_user),
      'rooms_owned', (select count(*) from rooms where owner_id = p_user),
      'rooms_joined', (select count(*) from room_members where user_id = p_user),
      'gifts_sent_coins', (select coalesce(sum(total), 0) from gift_events where sender_id = p_user),
      'gifts_received_coins', (select coalesce(sum(total), 0) from gift_events where receiver_id = p_user),
      'game_bets', (select coalesce(sum(bet), 0) from game_plays where user_id = p_user),
      'game_payouts', (select coalesce(sum(payout), 0) from game_plays where user_id = p_user),
      'topups_coins', (select coalesce(sum(coins), 0) from topup_orders where user_id = p_user and status = 'approved'),
      'payments_paid', (select count(*) from payments where user_id = p_user and status = 'paid'),
      'withdrawn_usd', (select coalesce(sum(amount_usd), 0) from payouts where user_id = p_user and status = 'paid'),
      'reports_against', (select count(*) from reports where target_user = p_user),
      'messages_sent', (select count(*) from room_messages where user_id = p_user),
      'reels', (select count(*) from reels where user_id = p_user)),
    'devices', (select coalesce(jsonb_agg(jsonb_build_object('platform', platform, 'updated_at', updated_at) order by updated_at desc), '[]') from devices where user_id = p_user),
    'verifications', (select coalesce(jsonb_agg(to_jsonb(v) order by v.id desc), '[]') from verifications v where v.user_id = p_user),
    'rooms', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'status', status, 'listeners', listeners, 'created_at', created_at) order by id desc), '[]') from rooms where owner_id = p_user),
    'joined', (select coalesce(jsonb_agg(x order by x.joined_at desc), '[]') from (
                 select r.id, r.name, m.role, m.joined_at from room_members m join rooms r on r.id = m.room_id where m.user_id = p_user order by m.joined_at desc limit 30) x),
    'transactions', (select coalesce(jsonb_agg(t order by t.id desc), '[]') from (
                 select id, kind, coins, diamonds, ref, created_at from transactions where user_id = p_user order by id desc limit 60) t),
    'gifts_sent', (select coalesce(jsonb_agg(g order by g.created_at desc), '[]') from (
                 select ge.created_at, ge.total, ge.qty, gf.name gift, pr.username other, ge.room_id from gift_events ge
                   left join gifts gf on gf.id = ge.gift_id left join profiles pr on pr.id = ge.receiver_id
                  where ge.sender_id = p_user order by ge.created_at desc limit 30) g),
    'gifts_received', (select coalesce(jsonb_agg(g order by g.created_at desc), '[]') from (
                 select ge.created_at, ge.total, ge.qty, gf.name gift, pr.username other, ge.room_id from gift_events ge
                   left join gifts gf on gf.id = ge.gift_id left join profiles pr on pr.id = ge.sender_id
                  where ge.receiver_id = p_user order by ge.created_at desc limit 30) g),
    'games', (select coalesce(jsonb_agg(g order by g.id desc), '[]') from (
                 select id, game, bet, payout, room_id, created_at from game_plays where user_id = p_user order by id desc limit 40) g),
    'party_games', (select coalesce(jsonb_agg(g order by g.id desc), '[]') from (
                 select id, kind, status, stake, room_id, winner = p_user as won, created_at from room_games
                  where p_user = any(players) or host_id = p_user order by id desc limit 30) g),
    'topups', (select coalesce(jsonb_agg(t order by t.created_at desc), '[]') from (
                 select id, coins, amount, currency, method, status, trx_id, sender_number, created_at from topup_orders
                  where user_id = p_user order by created_at desc limit 30) t),
    'payments', (select coalesce(jsonb_agg(t order by t.created_at desc), '[]') from (
                 select id, provider, amount, currency, coins, status, created_at from payments where user_id = p_user order by created_at desc limit 30) t),
    'payouts', (select coalesce(jsonb_agg(to_jsonb(p) order by p.id desc), '[]') from payouts p where p.user_id = p_user),
    'checkins', (select coalesce(jsonb_agg(c order by c.day desc), '[]') from (
                 select day, reward, streak_day from daily_checkins where user_id = p_user order by day desc limit 30) c),
    'reports_against', (select coalesce(jsonb_agg(r order by r.id desc), '[]') from (
                 select r.id, r.reason, r.details, r.status, r.created_at, pr.username reporter from reports r
                   left join profiles pr on pr.id = r.reporter_id where r.target_user = p_user order by r.id desc limit 30) r),
    'reports_made', (select coalesce(jsonb_agg(r order by r.id desc), '[]') from (
                 select r.id, r.reason, r.status, r.created_at, pr.username target from reports r
                   left join profiles pr on pr.id = r.target_user where r.reporter_id = p_user order by r.id desc limit 30) r),
    'avatars', (select coalesce(jsonb_agg(to_jsonb(x) order by x.id desc), '[]') from (select * from ai_avatars where user_id = p_user order by id desc limit 12) x),
    'audit', (select coalesce(jsonb_agg(to_jsonb(x) order by x.id desc), '[]') from (select * from audit_log where target = p_user::text order by id desc limit 30) x)
  );
end $$;

revoke execute on function public._withdraw_checks(uuid), public._checkin_state(uuid) from public, anon, authenticated;
revoke execute on function public.withdraw_status(), public.request_withdrawal(bigint,text,text,text), public.checkin_status(),
  public.ai_avatar_quota(), public.admin_user_detail(uuid), public.admin_update_payout(bigint,text,text,text) from public, anon;
grant execute on function public.withdraw_status(), public.request_withdrawal(bigint,text,text,text), public.checkin_status(),
  public.ai_avatar_quota(), public.admin_user_detail(uuid), public.admin_update_payout(bigint,text,text,text) to authenticated, service_role;
