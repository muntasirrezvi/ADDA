-- Adda: Greedy (shared live rounds), Lucky 777 (5-line slot), treasure chests, no game limits.
-- Everything is played with in-app coins only.

-- ---------------------------------------------------------------- no limits
update public.app_settings set value = '0' where key in ('max_bet', 'daily_game_loss_cap');
insert into public.app_settings(key, value) values
  ('max_bet', '0'), ('daily_game_loss_cap', '0'), ('min_bet', '1000'),
  ('chest_reward_pct', '0.01')   -- a chest pays this share of its betting milestone
on conflict (key) do nothing;
update public.app_settings set value = '1000' where key = 'min_bet';

create or replace function public.play_game(p_game text, p_bet bigint default 0, p_pick jsonb default '{}', p_room bigint default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); w wallets;
  rtp numeric := setting_num('game_rtp', 0.95);
  minb bigint := setting_num('min_bet', 1000)::bigint;
  maxb bigint := setting_num('max_bet', 0)::bigint;   -- 0 = no maximum
  cap bigint := setting_num('daily_game_loss_cap', 0)::bigint;   -- 0 = no daily limit
  total bigint := 0; payout bigint := 0; lost bigint; u double precision; res jsonb;
  items text[]; mults int[];
  k numeric := 0; acc numeric := 0; scale numeric; winner text := 'bomb'; i int; itm text; amt bigint;
  d1 int; d2 int; side text; tgt numeric; crashp numeric; outcome text := 'lose'; mult numeric := 0;
  gem_names text[] := array['ruby','sapphire','emerald','amethyst','topaz','diamond'];
  drops text[] := '{}'; hits int := 0;
  wheel numeric[] := array[0, 1.5, 0, 2, 0.5, 0, 3, 0, 1.5, 0, 5, 0, 0.5, 0, 1.2, 0];
  slot int;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  if coalesce(setting('games_enabled'), 'true'::jsonb) <> 'true'::jsonb then raise exception 'games are switched off right now'; end if;
  if not exists (select 1 from profiles where id = me and games_ok_at is not null) then raise exception 'confirm you are 18 or older first'; end if;

  if p_game = 'greedy' then
    items := array['tomato','corn','carrot','lettuce','fish','shrimp','steak','chicken'];
    mults := array[5,5,5,5,10,15,25,45];
  elsif p_game = 'fruit' then
    items := array['apple','orange','lemon','grape','cherry','strawberry','watermelon','banana'];
    mults := array[5,5,5,5,10,15,25,45];
  end if;

  if p_game in ('greedy', 'fruit') then
    if jsonb_typeof(p_pick->'bets') <> 'object' then raise exception 'place a bet first'; end if;
    for itm, amt in select e.key, (e.value #>> '{}')::bigint from jsonb_each(p_pick->'bets') e loop
      if not (itm = any(items)) or amt < 0 then raise exception 'invalid bet'; end if;
      total := total + amt;
    end loop;
  elsif p_game in ('slots', 'dice', 'crash', 'gems', 'wheel') then
    total := p_bet;
  else
    raise exception 'unknown game';
  end if;
  if total < minb then raise exception 'minimum bet is % coins', minb; end if;
  if maxb > 0 and total > maxb then raise exception 'maximum bet is % coins', maxb; end if;

  if cap > 0 then
    select coalesce(sum(gp.bet - gp.payout), 0) into lost from game_plays gp where gp.user_id = me and gp.created_at >= date_trunc('day', now());
    if lost + total > cap then raise exception 'daily game limit reached, please come back tomorrow'; end if;
  end if;

  select * into w from wallets where user_id = me for update;
  if w.coins < total then raise exception 'insufficient coins'; end if;
  perform _wallet_add(me, -total, 0, 'game_bet', p_game, jsonb_build_object('room', p_room));
  u := _rand();

  if p_game in ('greedy', 'fruit') then
    -- each item's chance is inversely proportional to its multiplier; the bomb takes the house share
    for i in 1 .. 8 loop k := k + 1.0 / mults[i]; end loop;
    k := 1 / k;
    scale := least(1, rtp / k);
    for i in 1 .. 8 loop
      acc := acc + scale * k / mults[i];
      if u < acc then winner := items[i]; mult := mults[i]; exit; end if;
    end loop;
    if winner <> 'bomb' then payout := coalesce((p_pick->'bets'->>winner)::bigint, 0) * mult; end if;
    res := jsonb_build_object('winner', winner, 'mult', mult);

  elsif p_game = 'slots' then
    scale := rtp / 0.95;
    acc := 0;
    if u < (acc + 0.004 * scale) then outcome := '777'; mult := 50; end if; acc := acc + 0.004 * scale;
    if outcome = 'lose' and u < acc + 0.01 * scale then outcome := 'bar'; mult := 20; end if; acc := acc + 0.01 * scale;
    if outcome = 'lose' and u < acc + 0.02 * scale then outcome := 'bell'; mult := 10; end if; acc := acc + 0.02 * scale;
    if outcome = 'lose' and u < acc + 0.04 * scale then outcome := 'cherry3'; mult := 5; end if; acc := acc + 0.04 * scale;
    if outcome = 'lose' and u < acc + 0.075 * scale then outcome := 'cherry2'; mult := 2; end if;
    payout := floor(total * mult);
    res := jsonb_build_object('outcome', outcome, 'mult', mult);

  elsif p_game = 'dice' then
    side := coalesce(p_pick->>'side', '');
    if side not in ('big', 'small', 'seven') then raise exception 'choose Big, Small or Seven'; end if;
    d1 := floor(u * 6)::int + 1; d2 := floor(_rand() * 6)::int + 1;
    if (side = 'big' and d1 + d2 >= 8) or (side = 'small' and d1 + d2 <= 6) then mult := 2.25;
    elsif side = 'seven' and d1 + d2 = 7 then mult := 5.5; end if;
    payout := floor(total * mult);
    res := jsonb_build_object('dice', jsonb_build_array(d1, d2), 'side', side, 'mult', mult);

  elsif p_game = 'gems' then
    -- pick one of six gems; three gems drop. 1 match x1.4, 2 matches x4, 3 matches x40 (about 95% back)
    side := coalesce(p_pick->>'gem', '');
    if not (side = any(gem_names)) then raise exception 'choose a gem first'; end if;
    for i in 1 .. 3 loop
      itm := gem_names[floor((case when i = 1 then u else _rand() end) * 6)::int + 1];
      drops := drops || itm;
      if itm = side then hits := hits + 1; end if;
    end loop;
    mult := case hits when 1 then 1.4 when 2 then 4 when 3 then 40 else 0 end * rtp / 0.95;
    payout := floor(total * mult);
    res := jsonb_build_object('drops', to_jsonb(drops), 'gem', side, 'hits', hits, 'mult', round(mult, 2));

  elsif p_game = 'wheel' then
    -- 16 equal slots; the multipliers add up to 15.2, so the average return is 95%
    slot := floor(u * 16)::int + 1;
    mult := wheel[slot] * rtp / 0.95;
    payout := floor(total * mult);
    res := jsonb_build_object('slot', slot - 1, 'mult', round(mult, 2));

  else -- crash
    tgt := round(coalesce((p_pick->>'target')::numeric, 2), 2);
    if tgt < 1.1 or tgt > 100 then raise exception 'cash-out target must be between 1.1x and 100x'; end if;
    crashp := least(1000, greatest(1.0, floor(rtp / (1 - u) * 100) / 100));
    if crashp >= tgt then mult := tgt; payout := floor(total * tgt); end if;
    res := jsonb_build_object('crash', crashp, 'target', tgt, 'mult', mult);
  end if;

  if payout > 0 then
    perform _wallet_add(me, payout, 0, 'game_win', p_game, jsonb_build_object('room', p_room) || res);
  end if;
  insert into game_plays(user_id, room_id, game, bet, payout, result) values (me, p_room, p_game, total, payout, res);
  return res || jsonb_build_object('bet', total, 'payout', payout, 'coins', w.coins - total + payout);
end $$;

create or replace function public.my_game_status()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'enabled', coalesce(setting('games_enabled'), 'true'::jsonb) = 'true'::jsonb,
    'accepted', (select games_ok_at is not null from profiles where id = auth.uid()),
    'min_bet', setting_num('min_bet', 1000),
    'max_bet', setting_num('max_bet', 0),
    'daily_cap', setting_num('daily_game_loss_cap', 0),
    'lost_today', 0)
$$;

-- party games (lucky bag, stakes): no maximum either
create or replace function public.party_create(p_room bigint, p_kind text, p_opts jsonb default '{}')
returns public.room_games language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); g room_games; w wallets;
  stake bigint := coalesce((p_opts->>'stake')::bigint, 0);
  minb bigint := setting_num('min_bet', 10000)::bigint;
  maxb bigint := setting_num('max_bet', 50000000)::bigint;
  tot bigint; cnt int; a uuid; b uuid; mins int; seated uuid[]; target uuid; nplayers int;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  if not _room_member(p_room, me) then raise exception 'join the room first'; end if;
  if p_kind not in ('luckybag','pk','ludo','ttt','rps','bottle') then raise exception 'unknown game'; end if;

  if p_kind in ('pk','ludo','ttt','rps') and exists (
       select 1 from room_games where room_id = p_room
          and (case when p_kind = 'pk' then kind = 'pk' else kind in ('ludo','ttt','rps') end)
          and status in ('waiting','playing') and (ends_at is null or ends_at > now() - interval '1 minute')
          and updated_at > now() - interval '15 minutes') then
    raise exception 'a game is already running in this room';
  end if;

  if p_kind = 'luckybag' then
    tot := coalesce((p_opts->>'total')::bigint, 0);
    cnt := coalesce((p_opts->>'count')::int, 0);
    if cnt < 1 or cnt > 50 then raise exception 'a lucky bag can be shared by 1 to 50 people'; end if;
    if tot < greatest(minb, cnt * 100) then raise exception 'a lucky bag needs at least % coins', greatest(minb, cnt * 100); end if;
    if maxb > 0 and tot > maxb then raise exception 'maximum is % coins', maxb; end if;
    select * into w from wallets where user_id = me for update;
    if w.coins < tot then raise exception 'insufficient coins'; end if;
    perform _wallet_add(me, -tot, 0, 'luckybag_send', p_room::text, '{}');
    insert into room_games(room_id, kind, host_id, players, max_players, stake, status, state, ends_at)
      values (p_room, 'luckybag', me, '{}', cnt, 0, 'playing',
              jsonb_build_object('total', tot, 'count', cnt, 'left', tot, 'left_count', cnt),
              now() + interval '10 minutes')
      returning * into g;
    insert into room_messages(room_id, user_id, kind, body) values (p_room, me, 'system', 'sent a Lucky Bag 🧧 tap to grab!');
    return g;
  end if;

  if p_kind = 'pk' then
    if not _room_staff(p_room, me) then raise exception 'only the room owner or an admin can start a PK'; end if;
    a := (p_opts->>'a')::uuid; b := (p_opts->>'b')::uuid;
    mins := least(10, greatest(1, coalesce((p_opts->>'minutes')::int, 3)));
    if a is null or b is null or a = b then raise exception 'pick two different people on the mic'; end if;
    if (select count(*) from room_seats where room_id = p_room and user_id in (a, b)) < 2 then
      raise exception 'both people must be on the mic';
    end if;
    insert into room_games(room_id, kind, host_id, players, max_players, status, state, ends_at)
      values (p_room, 'pk', me, array[a, b], 2, 'playing', jsonb_build_object('minutes', mins),
              now() + make_interval(mins => mins))
      returning * into g;
    insert into room_messages(room_id, user_id, kind, body) values (p_room, me, 'system', 'started a PK battle ⚔️ send gifts to vote!');
    return g;
  end if;

  if p_kind = 'bottle' then
    if exists (select 1 from room_games where room_id = p_room and kind = 'bottle' and created_at > now() - interval '4 seconds') then
      raise exception 'the bottle is still spinning';
    end if;
    select array_agg(user_id) into seated from room_seats where room_id = p_room and user_id is not null;
    if coalesce(array_length(seated, 1), 0) < 2 then raise exception 'at least two people need to be on the mic'; end if;
    target := seated[floor(_rand() * array_length(seated, 1))::int + 1];
    insert into room_games(room_id, kind, host_id, players, status, state, winner)
      values (p_room, 'bottle', me, seated, 'done',
              jsonb_build_object('target', target, 'turns', 4 + floor(_rand() * 3)::int,
                                 'seat', (select seat from room_seats where room_id = p_room and user_id = target),
                                 'jitter', round((_rand() * 0.6 - 0.3)::numeric, 3)),
              target)
      returning * into g;
    return g;
  end if;

  -- ludo, ttt, rps: stake is held until the game ends
  if stake <> 0 and (stake < minb or (maxb > 0 and stake > maxb)) then raise exception 'stake must be 0 or at least % coins', minb; end if;
  if stake > 0 then
    if not exists (select 1 from profiles where id = me and games_ok_at is not null) then raise exception 'confirm you are 18 or older first'; end if;
    select * into w from wallets where user_id = me for update;
    if w.coins < stake then raise exception 'insufficient coins'; end if;
    perform _wallet_add(me, -stake, 0, 'party_stake', p_kind, jsonb_build_object('room', p_room));
  end if;
  nplayers := case when p_kind = 'ludo' then least(4, greatest(2, coalesce((p_opts->>'players')::int, 2))) else 2 end;
  insert into room_games(room_id, kind, host_id, players, max_players, stake, status)
    values (p_room, p_kind, me, array[me], nplayers, stake, 'waiting')
    returning * into g;
  insert into room_messages(room_id, user_id, kind, body) values (p_room, me, 'system',
    'opened ' || case p_kind when 'ttt' then 'Tic-Tac-Toe' when 'rps' then 'Rock Paper Scissors' else 'Ludo' end
    || case when stake > 0 then ' · stake ' || stake || ' coins' else '' end || ' — tap to join 🎮');
  return g;
end $$;

-- ---------------------------------------------------------------- shared helpers
create table if not exists public.game_daily (
  user_id uuid not null references public.profiles(id) on delete cascade,
  game text not null,
  day date not null,
  bet bigint not null default 0,
  win bigint not null default 0,
  primary key (user_id, game, day)
);
create table if not exists public.game_chests (
  user_id uuid not null references public.profiles(id) on delete cascade,
  game text not null,
  day date not null,
  level int not null,
  reward bigint not null,
  created_at timestamptz not null default now(),
  primary key (user_id, game, day, level)
);
alter table public.game_daily enable row level security;
alter table public.game_chests enable row level security;
revoke all on public.game_daily, public.game_chests from anon, authenticated;
grant all on public.game_daily, public.game_chests to service_role;

create or replace function public._game_day() returns date language sql stable as $$
  select (now() at time zone 'Asia/Dhaka')::date
$$;

create or replace function public._game_track(p_user uuid, p_game text, p_bet bigint, p_win bigint)
returns void language sql security definer set search_path = public as $$
  insert into game_daily(user_id, game, day, bet, win) values (p_user, p_game, _game_day(), p_bet, p_win)
  on conflict (user_id, game, day) do update set bet = game_daily.bet + excluded.bet, win = game_daily.win + excluded.win
$$;

create or replace function public._game_check(p_user uuid)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if p_user is null or not active_user(p_user) then raise exception 'account restricted'; end if;
  if coalesce(setting('games_enabled'), 'true'::jsonb) <> 'true'::jsonb then raise exception 'games are switched off right now'; end if;
  if not exists (select 1 from profiles where id = p_user and games_ok_at is not null) then raise exception 'confirm you are 18 or older first'; end if;
end $$;

-- the five treasure chests: bet this much in a game today to open one
create or replace function public._chest_levels() returns bigint[] language sql immutable as $$
  select array[5000000, 50000000, 250000000, 500000000, 2500000000]::bigint[]
$$;

create or replace function public._chest_state(p_user uuid, p_game text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'bet', coalesce((select bet from game_daily where user_id = p_user and game = p_game and day = _game_day()), 0),
    'win', coalesce((select win from game_daily where user_id = p_user and game = p_game and day = _game_day()), 0),
    'levels', to_jsonb(_chest_levels()),
    'rewards', (select jsonb_agg(floor(l * setting_num('chest_reward_pct', 0.01))) from unnest(_chest_levels()) l),
    'opened', coalesce((select jsonb_agg(level order by level) from game_chests where user_id = p_user and game = p_game and day = _game_day()), '[]'::jsonb))
$$;

create or replace function public.game_chest_claim(p_game text, p_level int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); lv bigint[] := _chest_levels(); done bigint; reward bigint; w wallets;
begin
  perform _game_check(me);
  if p_game not in ('greedy', 'slots777') or p_level < 1 or p_level > array_length(lv, 1) then raise exception 'unknown chest'; end if;
  select coalesce(bet, 0) into done from game_daily where user_id = me and game = p_game and day = _game_day();
  if coalesce(done, 0) < lv[p_level] then raise exception 'bet % more today to open this chest', lv[p_level] - coalesce(done, 0); end if;
  reward := floor(lv[p_level] * setting_num('chest_reward_pct', 0.01));
  insert into game_chests(user_id, game, day, level, reward) values (me, p_game, _game_day(), p_level, reward)
  on conflict do nothing;
  if not found then raise exception 'this chest is already open'; end if;
  w := _wallet_add(me, reward, 0, 'game_chest', p_game, jsonb_build_object('level', p_level));
  return jsonb_build_object('reward', reward, 'coins', w.coins, 'chests', _chest_state(me, p_game));
end $$;

-- ---------------------------------------------------------------- Greedy: one live round for everyone
-- every 35 s: 25 s to bet, then 10 s show (wheel runs, winners shown)
create table if not exists public.greedy_rounds (
  id bigint primary key,
  bet_until timestamptz not null,
  ends_at timestamptz not null,
  result text,                       -- public only after betting closes
  settled boolean not null default false,
  players int not null default 0,
  pool bigint not null default 0
);
create table if not exists public.greedy_secret (round_id bigint primary key, result text not null);
create table if not exists public.greedy_bets (
  round_id bigint not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  item text not null,
  amount bigint not null,
  primary key (round_id, user_id, item)
);
create table if not exists public.greedy_results (
  round_id bigint not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  bet bigint not null,
  win bigint not null,
  primary key (round_id, user_id)
);
create index if not exists greedy_results_win_idx on public.greedy_results(round_id, win desc);
alter table public.greedy_rounds enable row level security;
alter table public.greedy_secret enable row level security;
alter table public.greedy_bets enable row level security;
alter table public.greedy_results enable row level security;
revoke all on public.greedy_rounds, public.greedy_secret, public.greedy_bets, public.greedy_results from anon, authenticated;
grant all on public.greedy_rounds, public.greedy_bets, public.greedy_results to service_role;

-- items around the wheel (clockwise from the top) and what they pay
create or replace function public._greedy_items() returns table (item text, mult numeric, grp text, pos int)
language sql immutable as $$
  values ('apple', 5::numeric, 'fruit', 0), ('lemon', 5, 'fruit', 1), ('strawberry', 5, 'fruit', 2), ('mango', 5, 'fruit', 3),
         ('fish', 10, 'pizza', 4), ('burger', 15, 'pizza', 5), ('pizza', 25, 'pizza', 6), ('chicken', 45, 'pizza', 7)
$$;
-- group bets: "Fruit" wins on any of the four x5 items, "Pizza" on any of the other four
create or replace function public._greedy_group_mult(g text) returns numeric language sql immutable as $$
  select case g when 'g_fruit' then 1.25 when 'g_pizza' then 4.3 end
$$;

-- each item lands with chance proportional to 1/multiplier, so every bet pays back about 97% over time
create or replace function public._greedy_pick() returns text language plpgsql volatile as $$
declare k numeric := 0; acc numeric := 0; u double precision := _rand(); r record;
begin
  select sum(1 / mult) into k from _greedy_items();
  for r in select * from _greedy_items() order by pos loop
    acc := acc + (1 / r.mult) / k;
    if u < acc then return r.item; end if;
  end loop;
  return 'apple';
end $$;

create or replace function public._greedy_round(n bigint) returns void
language sql security definer set search_path = public as $$
  insert into greedy_rounds(id, bet_until, ends_at) values (n, to_timestamp(n * 35 + 25), to_timestamp(n * 35 + 35)) on conflict do nothing;
  insert into greedy_secret(round_id, result) values (n, _greedy_pick()) on conflict do nothing;
$$;

create or replace function public._greedy_settle(n bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r greedy_rounds; res text; m numeric; g text; x record; np int := 0; tot bigint := 0;
begin
  select * into r from greedy_rounds where id = n for update;
  if not found or r.settled or clock_timestamp() < r.bet_until then return; end if;
  select s.result into res from greedy_secret s where s.round_id = n;
  select i.mult, 'g_' || i.grp into m, g from _greedy_items() i where i.item = res;
  for x in
    select b.user_id, sum(b.amount) as bet,
           floor(coalesce(sum(b.amount) filter (where b.item = res), 0) * m
               + coalesce(sum(b.amount) filter (where b.item = g), 0) * _greedy_group_mult(g))::bigint as win
      from greedy_bets b where b.round_id = n group by b.user_id
  loop
    np := np + 1; tot := tot + x.bet;
    insert into greedy_results(round_id, user_id, bet, win) values (n, x.user_id, x.bet, x.win) on conflict do nothing;
    if x.win > 0 then
      perform _wallet_add(x.user_id, x.win, 0, 'game_win', 'greedy', jsonb_build_object('round', n, 'result', res));
      perform _game_track(x.user_id, 'greedy', 0, x.win);
    end if;
    insert into game_plays(user_id, game, bet, payout, result) values (x.user_id, 'greedy', x.bet, x.win, jsonb_build_object('round', n, 'winner', res));
  end loop;
  update greedy_rounds set settled = true, result = res, players = np, pool = tot where id = n;
end $$;

create or replace function public.greedy_state()
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); n bigint := floor(extract(epoch from now()) / 35); r greedy_rounds; old bigint; phase text;
begin
  if me is null then raise exception 'not signed in'; end if;
  perform _greedy_round(n);
  for old in select id from greedy_rounds where not settled and bet_until <= now() order by id limit 30 loop
    perform _greedy_settle(old);
  end loop;
  select * into r from greedy_rounds where id = n;
  phase := case when now() < r.bet_until then 'bet' else 'show' end;
  return jsonb_build_object(
    'round', n,
    'phase', phase,
    'now_ms', floor(extract(epoch from clock_timestamp()) * 1000),
    'bet_until_ms', floor(extract(epoch from r.bet_until) * 1000),
    'ends_ms', floor(extract(epoch from r.ends_at) * 1000),
    'result', case when phase = 'show' then r.result end,
    'my_bets', coalesce((select jsonb_object_agg(item, amount) from greedy_bets where round_id = n and user_id = me), '{}'::jsonb),
    'all_bets', coalesce((select jsonb_object_agg(item, s) from (select item, sum(amount) s from greedy_bets where round_id = n group by item) t), '{}'::jsonb),
    'players', (select count(distinct user_id) from greedy_bets where round_id = n),
    'me', case when phase = 'show' then (select jsonb_build_object('bet', bet, 'win', win) from greedy_results where round_id = n and user_id = me) end,
    'top', case when phase = 'show' then coalesce((
        select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'avatar_url', p.avatar_url, 'avatar_preset', p.avatar_preset, 'win', t.win) order by t.win desc)
          from (select * from greedy_results where round_id = n and win > 0 order by win desc limit 3) t join profiles p on p.id = t.user_id), '[]'::jsonb) end,
    'history', coalesce((select jsonb_agg(result order by id desc) from (select id, result from greedy_rounds where settled and id <= n order by id desc limit 20) h), '[]'::jsonb),
    'chests', _chest_state(me, 'greedy'),
    'coins', (select coins from wallets where user_id = me));
end $$;

create or replace function public.greedy_bet(p_item text, p_amount bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); n bigint := floor(extract(epoch from now()) / 35); r greedy_rounds; w wallets;
begin
  perform _game_check(me);
  if not exists (select 1 from _greedy_items() where item = p_item) and p_item not in ('g_fruit', 'g_pizza') then raise exception 'pick a food first'; end if;
  if p_amount is null or p_amount < setting_num('min_bet', 1000) then raise exception 'minimum bet is % coins', setting_num('min_bet', 1000); end if;
  perform _greedy_round(n);
  select * into r from greedy_rounds where id = n for share;
  if r.settled or clock_timestamp() >= r.bet_until then raise exception 'betting is closed, wait for the next round'; end if;
  select * into w from wallets where user_id = me for update;
  if w.coins < p_amount then raise exception 'insufficient coins'; end if;
  w := _wallet_add(me, -p_amount, 0, 'game_bet', 'greedy', jsonb_build_object('round', n, 'item', p_item));
  insert into greedy_bets(round_id, user_id, item, amount) values (n, me, p_item, p_amount)
  on conflict (round_id, user_id, item) do update set amount = greedy_bets.amount + excluded.amount;
  perform _game_track(me, 'greedy', p_amount, 0);
  return jsonb_build_object('coins', w.coins,
    'my_bets', (select jsonb_object_agg(item, amount) from greedy_bets where round_id = n and user_id = me),
    'chests', _chest_state(me, 'greedy'));
end $$;

-- ---------------------------------------------------------------- Lucky 777: 3 reels x 3 rows, 5 lines
-- weights per cell and what three in a line pay (times the line bet = total bet / 5); about 96% back over time
create or replace function public._slot_syms() returns table (sym text, weight int, pay int)
language sql immutable as $$
  values ('seven', 4, 500), ('bar', 7, 150), ('bell', 10, 90), ('melon', 13, 45), ('grape', 17, 28), ('lemon', 22, 18), ('cherry', 27, 13)
$$;

create or replace function public._slot_cell() returns text language plpgsql volatile as $$
declare u int := floor(_rand() * 100); acc int := 0; r record;
begin
  for r in select * from _slot_syms() loop
    acc := acc + r.weight;
    if u < acc then return r.sym; end if;
  end loop;
  return 'cherry';
end $$;

create or replace function public.slot_spin(p_bet bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); w wallets; g text[] := '{}'; i int; a text; b text; c text;
  lines int[] := array[1,2,3, 4,5,6, 7,8,9, 1,5,9, 7,5,3];   -- cells numbered row by row 1..9
  hits jsonb := '[]'; units numeric := 0; p int; payout bigint;
  factor numeric := setting_num('game_rtp', 0.95) / 0.95;
begin
  perform _game_check(me);
  if p_bet is null or p_bet < setting_num('min_bet', 1000) then raise exception 'minimum bet is % coins', setting_num('min_bet', 1000); end if;
  select * into w from wallets where user_id = me for update;
  if w.coins < p_bet then raise exception 'insufficient coins'; end if;
  perform _wallet_add(me, -p_bet, 0, 'game_bet', 'slots777', '{}');
  for i in 1 .. 9 loop g := g || _slot_cell(); end loop;
  for i in 0 .. 4 loop
    a := g[lines[i * 3 + 1]]; b := g[lines[i * 3 + 2]]; c := g[lines[i * 3 + 3]];
    if a = b and b = c then
      select pay into p from _slot_syms() where sym = a;
      hits := hits || jsonb_build_object('line', i, 'sym', a, 'pay', p);
      units := units + p;
    elsif a = 'cherry' and b = 'cherry' then
      hits := hits || jsonb_build_object('line', i, 'sym', 'cherry', 'pay', 2, 'two', true);
      units := units + 2;
    end if;
  end loop;
  payout := floor(p_bet * units / 5 * factor);
  if payout > 0 then w := _wallet_add(me, payout, 0, 'game_win', 'slots777', jsonb_build_object('lines', hits));
  else select * into w from wallets where user_id = me; end if;
  perform _game_track(me, 'slots777', p_bet, payout);
  insert into game_plays(user_id, game, bet, payout, result) values (me, 'slots777', p_bet, payout, jsonb_build_object('grid', to_jsonb(g), 'lines', hits));
  return jsonb_build_object('grid', to_jsonb(g), 'lines', hits, 'bet', p_bet, 'payout', payout, 'big', payout >= p_bet * 10,
    'coins', w.coins, 'chests', _chest_state(me, 'slots777'));
end $$;

create or replace function public.slot_info()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'chests', _chest_state(auth.uid(), 'slots777'),
    'online', (select count(distinct user_id) from game_plays where game in ('slots777', 'greedy') and created_at > now() - interval '10 minutes'),
    'big_wins', coalesce((select jsonb_agg(jsonb_build_object('username', p.username, 'avatar_url', p.avatar_url, 'avatar_preset', p.avatar_preset, 'payout', t.payout) order by t.id desc)
       from (select id, user_id, payout from game_plays where game = 'slots777' and payout >= bet * 10 order by id desc limit 3) t join profiles p on p.id = t.user_id), '[]'::jsonb),
    'coins', (select coins from wallets where user_id = auth.uid()))
$$;

revoke all on function public.greedy_state(), public.greedy_bet(text, bigint), public.slot_spin(bigint), public.slot_info(), public.game_chest_claim(text, int) from public, anon;
grant execute on function public.greedy_state(), public.greedy_bet(text, bigint), public.slot_spin(bigint), public.slot_info(), public.game_chest_claim(text, int) to authenticated;
revoke all on function public._greedy_settle(bigint), public._greedy_round(bigint), public._game_track(uuid, text, bigint, bigint), public._chest_state(uuid, text), public._game_check(uuid) from public, anon, authenticated;
