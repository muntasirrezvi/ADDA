-- Adda casino games (coins only): live Fruit Party, live Crash (Rocket), Sic Bo, Big Six wheel, Mines.
-- Results are always decided on the server.

-- ---------------------------------------------------------------- chests for every game
create or replace function public.game_chest_claim(p_game text, p_level int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); lv bigint[] := _chest_levels(); done bigint; reward bigint; w wallets;
begin
  perform _game_check(me);
  if p_game not in ('greedy', 'fruit', 'slots777', 'crash', 'sicbo', 'bigsix', 'mines') or p_level < 1 or p_level > array_length(lv, 1) then
    raise exception 'unknown chest';
  end if;
  select coalesce(bet, 0) into done from game_daily where user_id = me and game = p_game and day = _game_day();
  if coalesce(done, 0) < lv[p_level] then raise exception 'bet % more today to open this chest', lv[p_level] - coalesce(done, 0); end if;
  reward := floor(lv[p_level] * setting_num('chest_reward_pct', 0.01));
  insert into game_chests(user_id, game, day, level, reward) values (me, p_game, _game_day(), p_level, reward)
  on conflict do nothing;
  if not found then raise exception 'this chest is already open'; end if;
  w := _wallet_add(me, reward, 0, 'game_chest', p_game, jsonb_build_object('level', p_level));
  return jsonb_build_object('reward', reward, 'coins', w.coins, 'chests', _chest_state(me, p_game));
end $$;

create or replace function public.game_chests_info(p_game text)
returns jsonb language sql stable security definer set search_path = public as $$
  select _chest_state(auth.uid(), p_game)
$$;

-- take a bet from the wallet (locks the wallet row)
create or replace function public._take_bet(p_user uuid, p_amount bigint, p_game text, p_meta jsonb default '{}')
returns wallets language plpgsql security definer set search_path = public as $$
declare w wallets;
begin
  if p_amount is null or p_amount < setting_num('min_bet', 1000) then raise exception 'minimum bet is % coins', setting_num('min_bet', 1000); end if;
  select * into w from wallets where user_id = p_user for update;
  if w.coins < p_amount then raise exception 'insufficient coins'; end if;
  w := _wallet_add(p_user, -p_amount, 0, 'game_bet', p_game, p_meta);
  perform _game_track(p_user, p_game, p_amount, 0);
  return w;
end $$;

-- ---------------------------------------------------------------- live wheels: Greedy and Fruit Party
-- Both use the same round tables; Fruit Party round ids are offset by 10^12.
create or replace function public._wheel_base(p_game text) returns bigint language sql immutable as $$
  select case p_game when 'fruit' then 1000000000000 else 0 end::bigint
$$;

create or replace function public._wheel_items(p_game text) returns table (item text, mult numeric, grp text, pos int)
language sql immutable as $$
  select v.item, v.mult, v.grp, v.pos from (values
    ('greedy', 'apple', 5::numeric, 'fruit', 0), ('greedy', 'lemon', 5, 'fruit', 1), ('greedy', 'strawberry', 5, 'fruit', 2), ('greedy', 'mango', 5, 'fruit', 3),
    ('greedy', 'fish', 10, 'pizza', 4), ('greedy', 'burger', 15, 'pizza', 5), ('greedy', 'pizza', 25, 'pizza', 6), ('greedy', 'chicken', 45, 'pizza', 7),
    ('fruit', 'cherry', 5, 'small', 0), ('fruit', 'lemon', 5, 'small', 1), ('fruit', 'orange', 5, 'small', 2), ('fruit', 'apple', 5, 'small', 3),
    ('fruit', 'grape', 10, 'big', 4), ('fruit', 'banana', 15, 'big', 5), ('fruit', 'strawberry', 25, 'big', 6), ('fruit', 'watermelon', 45, 'big', 7)
  ) v(g, item, mult, grp, pos) where v.g = p_game
$$;

create or replace function public._wheel_group_mult(g text) returns numeric language sql immutable as $$
  select case g when 'g_fruit' then 1.25 when 'g_small' then 1.25 when 'g_pizza' then 4.3 when 'g_big' then 4.3 end
$$;

create or replace function public._wheel_pick(p_game text) returns text language plpgsql volatile as $$
declare k numeric; acc numeric := 0; u double precision := _rand(); r record;
begin
  select sum(1 / mult) into k from _wheel_items(p_game);
  for r in select * from _wheel_items(p_game) order by pos loop
    acc := acc + (1 / r.mult) / k;
    if u < acc then return r.item; end if;
  end loop;
  return (select item from _wheel_items(p_game) where pos = 0);
end $$;

create or replace function public._wheel_round(p_game text, n bigint) returns void
language sql security definer set search_path = public as $$
  insert into greedy_rounds(id, bet_until, ends_at) values (_wheel_base(p_game) + n, to_timestamp(n * 35 + 25), to_timestamp(n * 35 + 35)) on conflict do nothing;
  insert into greedy_secret(round_id, result) values (_wheel_base(p_game) + n, _wheel_pick(p_game)) on conflict do nothing;
$$;

create or replace function public._wheel_settle(p_game text, rid bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r greedy_rounds; res text; m numeric; g text; x record; np int := 0; tot bigint := 0;
begin
  select * into r from greedy_rounds where id = rid for update;
  if not found or r.settled or clock_timestamp() < r.bet_until then return; end if;
  select s.result into res from greedy_secret s where s.round_id = rid;
  select i.mult, 'g_' || i.grp into m, g from _wheel_items(p_game) i where i.item = res;
  for x in
    select b.user_id, sum(b.amount) as bet,
           floor(coalesce(sum(b.amount) filter (where b.item = res), 0) * m
               + coalesce(sum(b.amount) filter (where b.item = g), 0) * _wheel_group_mult(g))::bigint as win
      from greedy_bets b where b.round_id = rid group by b.user_id
  loop
    np := np + 1; tot := tot + x.bet;
    insert into greedy_results(round_id, user_id, bet, win) values (rid, x.user_id, x.bet, x.win) on conflict do nothing;
    if x.win > 0 then
      perform _wallet_add(x.user_id, x.win, 0, 'game_win', p_game, jsonb_build_object('round', rid, 'result', res));
      perform _game_track(x.user_id, p_game, 0, x.win);
    end if;
    insert into game_plays(user_id, game, bet, payout, result) values (x.user_id, p_game, x.bet, x.win, jsonb_build_object('round', rid, 'winner', res));
  end loop;
  update greedy_rounds set settled = true, result = res, players = np, pool = tot where id = rid;
end $$;

create or replace function public.wheel_state(p_game text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); n bigint := floor(extract(epoch from now()) / 35); base bigint; rid bigint;
  r greedy_rounds; old bigint; phase text;
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_game not in ('greedy', 'fruit') then raise exception 'unknown game'; end if;
  base := _wheel_base(p_game); rid := base + n;
  perform _wheel_round(p_game, n);
  for old in select id from greedy_rounds where not settled and bet_until <= now() and id >= base and id < base + 1000000000000 order by id limit 30 loop
    perform _wheel_settle(p_game, old);
  end loop;
  select * into r from greedy_rounds where id = rid;
  phase := case when now() < r.bet_until then 'bet' else 'show' end;
  return jsonb_build_object(
    'round', n,
    'phase', phase,
    'now_ms', floor(extract(epoch from clock_timestamp()) * 1000),
    'bet_until_ms', floor(extract(epoch from r.bet_until) * 1000),
    'ends_ms', floor(extract(epoch from r.ends_at) * 1000),
    'result', case when phase = 'show' then r.result end,
    'my_bets', coalesce((select jsonb_object_agg(item, amount) from greedy_bets where round_id = rid and user_id = me), '{}'::jsonb),
    'all_bets', coalesce((select jsonb_object_agg(item, s) from (select item, sum(amount) s from greedy_bets where round_id = rid group by item) t), '{}'::jsonb),
    'players', (select count(distinct user_id) from greedy_bets where round_id = rid),
    'me', case when phase = 'show' then (select jsonb_build_object('bet', bet, 'win', win) from greedy_results where round_id = rid and user_id = me) end,
    'top', case when phase = 'show' then coalesce((
        select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'avatar_url', p.avatar_url, 'avatar_preset', p.avatar_preset, 'win', t.win) order by t.win desc)
          from (select * from greedy_results where round_id = rid and win > 0 order by win desc limit 3) t join profiles p on p.id = t.user_id), '[]'::jsonb) end,
    'history', coalesce((select jsonb_agg(result order by id desc) from (
        select id, result from greedy_rounds where settled and id <= rid and id >= base order by id desc limit 20) h), '[]'::jsonb),
    'chests', _chest_state(me, p_game),
    'coins', (select coins from wallets where user_id = me));
end $$;

create or replace function public.wheel_bet(p_game text, p_item text, p_amount bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); n bigint := floor(extract(epoch from now()) / 35); rid bigint; r greedy_rounds; w wallets;
begin
  perform _game_check(me);
  if p_game not in ('greedy', 'fruit') then raise exception 'unknown game'; end if;
  if not exists (select 1 from _wheel_items(p_game) where item = p_item)
     and p_item not in (select distinct 'g_' || grp from _wheel_items(p_game)) then raise exception 'pick an item first'; end if;
  rid := _wheel_base(p_game) + n;
  perform _wheel_round(p_game, n);
  select * into r from greedy_rounds where id = rid for share;
  if r.settled or clock_timestamp() >= r.bet_until then raise exception 'betting is closed, wait for the next round'; end if;
  w := _take_bet(me, p_amount, p_game, jsonb_build_object('round', rid, 'item', p_item));
  insert into greedy_bets(round_id, user_id, item, amount) values (rid, me, p_item, p_amount)
  on conflict (round_id, user_id, item) do update set amount = greedy_bets.amount + excluded.amount;
  return jsonb_build_object('coins', w.coins,
    'my_bets', (select jsonb_object_agg(item, amount) from greedy_bets where round_id = rid and user_id = me),
    'chests', _chest_state(me, p_game));
end $$;

-- the app shipped yesterday calls these
create or replace function public.greedy_state() returns jsonb language sql security definer set search_path = public as $$ select wheel_state('greedy') $$;
create or replace function public.greedy_bet(p_item text, p_amount bigint) returns jsonb language sql security definer set search_path = public as $$ select wheel_bet('greedy', p_item, p_amount) $$;

-- ---------------------------------------------------------------- Rocket: live crash rounds
-- 7 s to bet, then the rocket flies; the multiplier is e^(0.09 t) after t seconds.
-- Cash out any time before it explodes. Next round starts 4 s after the explosion.
create table if not exists public.crash_rounds (
  id bigint generated always as identity primary key,
  starts_at timestamptz not null,
  fly_at timestamptz not null,
  crash_at timestamptz not null,
  crash_point numeric,            -- public once it has exploded
  settled boolean not null default false
);
create table if not exists public.crash_secret (round_id bigint primary key, crash_point numeric not null);
create table if not exists public.crash_bets (
  round_id bigint not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount bigint not null,
  auto numeric,                   -- cash out automatically at this multiplier
  cashed numeric,                 -- multiplier cashed out at
  win bigint not null default 0,
  created_at timestamptz not null default now(),
  primary key (round_id, user_id)
);
alter table public.crash_rounds enable row level security;
alter table public.crash_secret enable row level security;
alter table public.crash_bets enable row level security;
revoke all on public.crash_rounds, public.crash_secret, public.crash_bets from anon, authenticated;
grant all on public.crash_rounds, public.crash_bets to service_role;

create or replace function public._crash_k() returns numeric language sql immutable as $$ select 0.09::numeric $$;

create or replace function public._crash_settle(rid bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r crash_rounds; cp numeric; b record;
begin
  select * into r from crash_rounds where id = rid for update;
  if not found or r.settled or clock_timestamp() < r.crash_at then return; end if;
  select crash_point into cp from crash_secret where round_id = rid;
  for b in select * from crash_bets where round_id = rid for update loop
    if b.cashed is null and b.auto is not null and b.auto <= cp then
      update crash_bets set cashed = b.auto, win = floor(b.amount * b.auto) where round_id = rid and user_id = b.user_id;
      perform _wallet_add(b.user_id, floor(b.amount * b.auto)::bigint, 0, 'game_win', 'crash', jsonb_build_object('round', rid, 'at', b.auto));
      perform _game_track(b.user_id, 'crash', 0, floor(b.amount * b.auto)::bigint);
    end if;
  end loop;
  insert into game_plays(user_id, game, bet, payout, result)
    select user_id, 'crash', amount, win, jsonb_build_object('round', rid, 'crash', cp, 'cashed', cashed) from crash_bets where round_id = rid;
  update crash_rounds set settled = true, crash_point = cp where id = rid;
end $$;

-- the current round (creates the next one when the last has finished)
create or replace function public._crash_current() returns crash_rounds
language plpgsql security definer set search_path = public as $$
declare r crash_rounds; cp numeric; st timestamptz; u double precision;
begin
  select * into r from crash_rounds order by id desc limit 1;
  if found and clock_timestamp() < r.crash_at + interval '4 seconds' then return r; end if;
  perform pg_advisory_xact_lock(778899);
  select * into r from crash_rounds order by id desc limit 1;
  if found and clock_timestamp() < r.crash_at + interval '4 seconds' then return r; end if;
  if found then perform _crash_settle(r.id); end if;
  st := greatest(clock_timestamp(), coalesce(r.crash_at + interval '4 seconds', clock_timestamp()));
  u := _rand();
  cp := greatest(1.0, least(1000, floor(setting_num('game_rtp', 0.95) / (1 - u) * 100) / 100))::numeric(12, 2);
  insert into crash_rounds(starts_at, fly_at, crash_at)
    values (st, st + interval '7 seconds', st + interval '7 seconds' + make_interval(secs => ln(cp) / _crash_k()))
    returning * into r;
  insert into crash_secret(round_id, crash_point) values (r.id, cp);
  return r;
end $$;

create or replace function public.crash_state()
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r crash_rounds; now_ts timestamptz := clock_timestamp(); phase text; old bigint;
begin
  if me is null then raise exception 'not signed in'; end if;
  r := _crash_current();
  for old in select id from crash_rounds where not settled and crash_at <= now_ts order by id limit 20 loop
    perform _crash_settle(old);
  end loop;
  select * into r from crash_rounds where id = r.id;
  phase := case when now_ts < r.fly_at then 'bet' when now_ts < r.crash_at then 'fly' else 'crashed' end;
  return jsonb_build_object(
    'round', r.id,
    'phase', phase,
    'k', _crash_k(),
    'now_ms', floor(extract(epoch from now_ts) * 1000),
    'fly_ms', floor(extract(epoch from r.fly_at) * 1000),
    'next_ms', case when phase = 'crashed' then floor(extract(epoch from r.crash_at + interval '4 seconds') * 1000) end,
    'crash', case when phase = 'crashed' then (select crash_point from crash_secret where round_id = r.id) end,
    'me', (select jsonb_build_object('amount', amount, 'auto', auto, 'cashed', cashed, 'win', win) from crash_bets where round_id = r.id and user_id = me),
    'players', coalesce((select jsonb_agg(jsonb_build_object('username', p.username, 'avatar_url', p.avatar_url, 'avatar_preset', p.avatar_preset,
                                 'amount', b.amount, 'cashed', b.cashed, 'win', b.win) order by b.amount desc)
       from (select * from crash_bets where round_id = r.id order by amount desc limit 30) b join profiles p on p.id = b.user_id), '[]'::jsonb),
    'count', (select count(*) from crash_bets where round_id = r.id),
    'history', coalesce((select jsonb_agg(crash_point order by id desc) from (select id, crash_point from crash_rounds where settled and id < r.id order by id desc limit 20) h), '[]'::jsonb),
    'chests', _chest_state(me, 'crash'),
    'coins', (select coins from wallets where user_id = me));
end $$;

create or replace function public.crash_bet(p_amount bigint, p_auto numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r crash_rounds; w wallets;
begin
  perform _game_check(me);
  if p_auto is not null and (p_auto < 1.01 or p_auto > 1000) then raise exception 'auto cash out must be between 1.01x and 1000x'; end if;
  r := _crash_current();
  select * into r from crash_rounds where id = r.id for share;
  if clock_timestamp() >= r.fly_at then raise exception 'the rocket already took off, wait for the next round'; end if;
  if exists (select 1 from crash_bets where round_id = r.id and user_id = me) then raise exception 'you already have a bet in this round'; end if;
  w := _take_bet(me, p_amount, 'crash', jsonb_build_object('round', r.id));
  insert into crash_bets(round_id, user_id, amount, auto) values (r.id, me, p_amount, round(p_auto, 2));
  return jsonb_build_object('coins', w.coins, 'round', r.id, 'chests', _chest_state(me, 'crash'));
end $$;

create or replace function public.crash_cashout()
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r crash_rounds; b crash_bets; cp numeric; m numeric; t numeric; v_win bigint; w wallets;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into r from crash_rounds order by id desc limit 1;
  select * into b from crash_bets where round_id = r.id and user_id = me for update;
  if not found then raise exception 'no bet in this round'; end if;
  if b.cashed is not null then raise exception 'already cashed out'; end if;
  t := extract(epoch from clock_timestamp() - r.fly_at);
  if t < 0 then raise exception 'the rocket has not taken off yet'; end if;
  select crash_point into cp from crash_secret where round_id = r.id;
  m := (floor(exp(_crash_k() * t) * 100) / 100)::numeric(12, 2);
  if m >= cp or clock_timestamp() >= r.crash_at then raise exception 'too late, the rocket exploded at %x', cp; end if;
  if b.auto is not null and b.auto <= m then m := b.auto; end if;
  v_win := floor(b.amount * m);
  update crash_bets set cashed = m, win = v_win where round_id = r.id and user_id = me;
  w := _wallet_add(me, v_win, 0, 'game_win', 'crash', jsonb_build_object('round', r.id, 'at', m));
  perform _game_track(me, 'crash', 0, v_win);
  return jsonb_build_object('cashed', m, 'win', v_win, 'coins', w.coins, 'chests', _chest_state(me, 'crash'));
end $$;

-- ---------------------------------------------------------------- Dice: Sic Bo (three dice)
-- returns include the stake: Big/Small/Odd/Even x2 (lose on any triple), Any triple x31,
-- totals 4/17 x61, 5/16 x31, 6/15 x18, 7/14 x13, 8/13 x9, 9-12 x7, single number x2/x3/x4 by how many dice show it
create or replace function public.sicbo_roll(p_bets jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); w wallets; k text; amt bigint; total bigint := 0; payout bigint := 0;
  d int[]; s int; triple boolean; m numeric; wins jsonb := '{}'; n int;
  tot_mult int[] := array[0,0,0,61,31,18,13,9,7,7,7,7,9,13,18,31,61];   -- index = total (4..17)
begin
  perform _game_check(me);
  if jsonb_typeof(p_bets) <> 'object' then raise exception 'place a bet first'; end if;
  for k, amt in select e.key, (e.value #>> '{}')::bigint from jsonb_each(p_bets) e loop
    if amt is null or amt <= 0 then continue; end if;
    if k not in ('big', 'small', 'odd', 'even', 'any_triple') and k !~ '^total_([4-9]|1[0-7])$' and k !~ '^single_[1-6]$' then raise exception 'unknown bet %', k; end if;
    total := total + amt;
  end loop;
  if total = 0 then raise exception 'place a bet first'; end if;
  w := _take_bet(me, total, 'sicbo', jsonb_build_object('bets', p_bets));
  d := array[floor(_rand() * 6)::int + 1, floor(_rand() * 6)::int + 1, floor(_rand() * 6)::int + 1];
  s := d[1] + d[2] + d[3];
  triple := d[1] = d[2] and d[2] = d[3];
  for k, amt in select e.key, (e.value #>> '{}')::bigint from jsonb_each(p_bets) e loop
    if amt is null or amt <= 0 then continue; end if;
    m := 0;
    if k = 'big' and not triple and s between 11 and 17 then m := 2;
    elsif k = 'small' and not triple and s between 4 and 10 then m := 2;
    elsif k = 'odd' and not triple and s % 2 = 1 then m := 2;
    elsif k = 'even' and not triple and s % 2 = 0 then m := 2;
    elsif k = 'any_triple' and triple then m := 31;
    elsif k like 'total_%' and substr(k, 7)::int = s then m := tot_mult[s];
    elsif k like 'single_%' then
      n := (d[1] = substr(k, 8)::int)::int + (d[2] = substr(k, 8)::int)::int + (d[3] = substr(k, 8)::int)::int;
      if n > 0 then m := 1 + n; end if;
    end if;
    if m > 0 then
      payout := payout + floor(amt * m);
      wins := wins || jsonb_build_object(k, floor(amt * m));
    end if;
  end loop;
  if payout > 0 then
    w := _wallet_add(me, payout, 0, 'game_win', 'sicbo', jsonb_build_object('dice', to_jsonb(d)));
    perform _game_track(me, 'sicbo', 0, payout);
  end if;
  insert into game_plays(user_id, game, bet, payout, result) values (me, 'sicbo', total, payout, jsonb_build_object('dice', to_jsonb(d), 'sum', s));
  return jsonb_build_object('dice', to_jsonb(d), 'sum', s, 'triple', triple, 'wins', wins, 'bet', total, 'payout', payout,
    'coins', w.coins, 'chests', _chest_state(me, 'sicbo'),
    'history', (select jsonb_agg(result order by id desc) from (select id, result from game_plays where user_id = me and game = 'sicbo' order by id desc limit 12) h));
end $$;

-- ---------------------------------------------------------------- Lucky Wheel: Big Six (54 segments)
create or replace function public._bigsix_segments() returns text[] language sql immutable as $$
  select array['5','joker','10','20','1','2','1','1','2','5','1','1','2','1','1','2','10','5','1','2','1','1','1','2','5','1','2','1',
               'logo','10','20','2','5','2','1','1','1','2','1','1','5','2','1','10','2','1','1','5','2','1','1','2','1','2']
$$;
create or replace function public._bigsix_mult(k text) returns numeric language sql immutable as $$
  select case k when '1' then 2.1 when '2' then 3.4 when '5' then 7.3 when '10' then 12.8 when '20' then 25.6 when 'joker' then 51 when 'logo' then 51 end
$$;

create or replace function public.bigsix_info()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('segments', to_jsonb(_bigsix_segments()),
    'mults', (select jsonb_object_agg(k, _bigsix_mult(k)) from unnest(array['1','2','5','10','20','joker','logo']) k),
    'chests', _chest_state(auth.uid(), 'bigsix'),
    'history', coalesce((select jsonb_agg(result->>'segment' order by id desc) from (select id, result from game_plays where user_id = auth.uid() and game = 'bigsix' order by id desc limit 15) h), '[]'::jsonb))
$$;

create or replace function public.bigsix_spin(p_bets jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); w wallets; k text; amt bigint; total bigint := 0; payout bigint := 0; seg text[] := _bigsix_segments(); i int; hit text;
begin
  perform _game_check(me);
  if jsonb_typeof(p_bets) <> 'object' then raise exception 'place a bet first'; end if;
  for k, amt in select e.key, (e.value #>> '{}')::bigint from jsonb_each(p_bets) e loop
    if amt is null or amt <= 0 then continue; end if;
    if _bigsix_mult(k) is null then raise exception 'unknown bet %', k; end if;
    total := total + amt;
  end loop;
  if total = 0 then raise exception 'place a bet first'; end if;
  w := _take_bet(me, total, 'bigsix', jsonb_build_object('bets', p_bets));
  i := floor(_rand() * 54)::int;     -- 0-based segment index
  hit := seg[i + 1];
  payout := floor(coalesce((p_bets->>hit)::bigint, 0) * _bigsix_mult(hit));
  if payout > 0 then
    w := _wallet_add(me, payout, 0, 'game_win', 'bigsix', jsonb_build_object('segment', hit));
    perform _game_track(me, 'bigsix', 0, payout);
  end if;
  insert into game_plays(user_id, game, bet, payout, result) values (me, 'bigsix', total, payout, jsonb_build_object('index', i, 'segment', hit));
  return jsonb_build_object('index', i, 'segment', hit, 'bet', total, 'payout', payout, 'coins', w.coins, 'chests', _chest_state(me, 'bigsix'));
end $$;

-- ---------------------------------------------------------------- Gems: Mines (5x5)
-- pick how many bombs; every safe gem raises the multiplier; cash out any time.
create table if not exists public.mines_games (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  bet bigint not null,
  bombs int not null,
  board int[] not null,            -- bomb tiles 0..24 (secret until the game ends)
  picks int[] not null default '{}',
  status text not null default 'playing',   -- playing, cashed, boom
  mult numeric not null default 1,
  win bigint not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists mines_user_idx on public.mines_games(user_id, status);
alter table public.mines_games enable row level security;
revoke all on public.mines_games from anon, authenticated;
grant all on public.mines_games to service_role;

-- multiplier after k safe picks with b bombs: 0.97 x C(25,k) / C(25-b,k)
create or replace function public._mines_mult(b int, k int) returns numeric language plpgsql immutable as $$
declare m numeric := 0.97; i int;
begin
  if k = 0 then return 1; end if;
  for i in 0 .. k - 1 loop m := m * (25 - i)::numeric / (25 - b - i); end loop;
  return (floor(m * 100) / 100)::numeric(12, 2);
end $$;

create or replace function public._mines_view(g mines_games) returns jsonb language sql stable as $$
  select jsonb_build_object('id', g.id, 'bet', g.bet, 'bombs', g.bombs, 'picks', to_jsonb(g.picks), 'status', g.status,
    'mult', g.mult, 'next', case when g.status = 'playing' and cardinality(g.picks) < 25 - g.bombs then _mines_mult(g.bombs, cardinality(g.picks) + 1) end,
    'win', g.win, 'board', case when g.status <> 'playing' then to_jsonb(g.board) end)
$$;

create or replace function public.mines_active()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'game', (select _mines_view(g) from mines_games g where g.user_id = auth.uid() and g.status = 'playing' order by id desc limit 1),
    'chests', _chest_state(auth.uid(), 'mines'),
    'history', coalesce((select jsonb_agg(jsonb_build_object('mult', case when status = 'cashed' then mult else 0 end) order by id desc)
       from (select id, status, mult from mines_games where user_id = auth.uid() and status <> 'playing' order by id desc limit 15) h), '[]'::jsonb))
$$;

create or replace function public._mines_finish(g mines_games, p_status text) returns mines_games
language plpgsql security definer set search_path = public as $$
declare v_win bigint := case when p_status = 'cashed' then floor(g.bet * g.mult) else 0 end;
begin
  update mines_games set status = p_status, win = v_win where id = g.id returning * into g;
  if v_win > 0 then
    perform _wallet_add(g.user_id, v_win, 0, 'game_win', 'mines', jsonb_build_object('game', g.id, 'mult', g.mult));
    perform _game_track(g.user_id, 'mines', 0, v_win);
  end if;
  insert into game_plays(user_id, game, bet, payout, result) values (g.user_id, 'mines', g.bet, v_win, jsonb_build_object('bombs', g.bombs, 'picks', cardinality(g.picks), 'mult', g.mult));
  return g;
end $$;

create or replace function public.mines_start(p_bet bigint, p_bombs int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); g mines_games; w wallets; tiles int[];
begin
  perform _game_check(me);
  if p_bombs < 1 or p_bombs > 24 then raise exception 'choose 1 to 24 bombs'; end if;
  if exists (select 1 from mines_games where user_id = me and status = 'playing') then raise exception 'finish your current game first'; end if;
  w := _take_bet(me, p_bet, 'mines', jsonb_build_object('bombs', p_bombs));
  select array_agg(t) into tiles from (select t from generate_series(0, 24) t order by _rand() limit p_bombs) x;
  insert into mines_games(user_id, bet, bombs, board) values (me, p_bet, p_bombs, tiles) returning * into g;
  return jsonb_build_object('game', _mines_view(g), 'coins', w.coins, 'chests', _chest_state(me, 'mines'));
end $$;

create or replace function public.mines_pick(p_game bigint, p_tile int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); g mines_games;
begin
  select * into g from mines_games where id = p_game and user_id = me for update;
  if not found or g.status <> 'playing' then raise exception 'this game is over'; end if;
  if p_tile < 0 or p_tile > 24 or p_tile = any(g.picks) then raise exception 'pick another tile'; end if;
  if p_tile = any(g.board) then
    update mines_games set picks = picks || p_tile, mult = 0 where id = g.id returning * into g;
    g := _mines_finish(g, 'boom');
    return jsonb_build_object('boom', true, 'game', _mines_view(g), 'coins', (select coins from wallets where user_id = me));
  end if;
  update mines_games set picks = picks || p_tile, mult = _mines_mult(bombs, cardinality(picks) + 1) where id = g.id returning * into g;
  if cardinality(g.picks) >= 25 - g.bombs then g := _mines_finish(g, 'cashed'); end if;   -- every gem found
  return jsonb_build_object('boom', false, 'game', _mines_view(g), 'coins', (select coins from wallets where user_id = me), 'chests', _chest_state(me, 'mines'));
end $$;

create or replace function public.mines_cashout(p_game bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); g mines_games;
begin
  select * into g from mines_games where id = p_game and user_id = me for update;
  if not found or g.status <> 'playing' then raise exception 'this game is over'; end if;
  if cardinality(g.picks) = 0 then raise exception 'find at least one gem first'; end if;
  g := _mines_finish(g, 'cashed');
  return jsonb_build_object('game', _mines_view(g), 'coins', (select coins from wallets where user_id = me), 'chests', _chest_state(me, 'mines'));
end $$;

-- ---------------------------------------------------------------- permissions
revoke all on function public.wheel_state(text), public.wheel_bet(text, text, bigint), public.crash_state(), public.crash_bet(bigint, numeric),
  public.crash_cashout(), public.sicbo_roll(jsonb), public.bigsix_info(), public.bigsix_spin(jsonb), public.mines_active(),
  public.mines_start(bigint, int), public.mines_pick(bigint, int), public.mines_cashout(bigint), public.game_chests_info(text) from public, anon;
grant execute on function public.wheel_state(text), public.wheel_bet(text, text, bigint), public.crash_state(), public.crash_bet(bigint, numeric),
  public.crash_cashout(), public.sicbo_roll(jsonb), public.bigsix_info(), public.bigsix_spin(jsonb), public.mines_active(),
  public.mines_start(bigint, int), public.mines_pick(bigint, int), public.mines_cashout(bigint), public.game_chests_info(text) to authenticated;
revoke all on function public._take_bet(uuid, bigint, text, jsonb), public._wheel_settle(text, bigint), public._wheel_round(text, bigint),
  public._crash_settle(bigint), public._crash_current(), public._mines_finish(mines_games, text) from public, anon, authenticated;
