-- Adda: more lucky games (fruit, gems, lucky wheel) and live party games played together in a room:
-- Lucky Bag, PK battle, Ludo, Tic-Tac-Toe, Rock-Paper-Scissors and Spin the Bottle.
-- Every result and every move is checked on the server; coins only move inside these functions.

insert into public.app_settings(key, value) values ('party_fee', '0.05') on conflict (key) do nothing;

create table if not exists public.room_games (
  id bigint generated always as identity primary key,
  room_id bigint not null references public.rooms(id) on delete cascade,
  kind text not null check (kind in ('luckybag','pk','ludo','ttt','rps','bottle')),
  host_id uuid not null references public.profiles(id) on delete cascade,
  players uuid[] not null default '{}',
  max_players int not null default 2,
  stake bigint not null default 0,
  status text not null default 'waiting' check (status in ('waiting','playing','done','cancelled')),
  state jsonb not null default '{}',
  winner uuid references public.profiles(id) on delete set null,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists room_games_room_idx on public.room_games(room_id, id desc);
alter table public.room_games enable row level security;
revoke all on public.room_games from anon, authenticated;
grant select on public.room_games to authenticated;
grant all on public.room_games to service_role;
create policy room_games_read on public.room_games for select to authenticated using (true);

-- hidden moves (rock-paper-scissors) that the other player must not see yet
create table if not exists public.room_game_secrets (
  game_id bigint not null references public.room_games(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  round int not null default 1,
  data jsonb not null,
  primary key (game_id, user_id, round)
);
alter table public.room_game_secrets enable row level security;
revoke all on public.room_game_secrets from anon, authenticated;
grant all on public.room_game_secrets to service_role;

create table if not exists public.luckybag_grabs (
  game_id bigint not null references public.room_games(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount bigint not null,
  created_at timestamptz not null default now(),
  primary key (game_id, user_id)
);
alter table public.luckybag_grabs enable row level security;
revoke all on public.luckybag_grabs from anon, authenticated;
grant select on public.luckybag_grabs to authenticated;
grant all on public.luckybag_grabs to service_role;
create policy luckybag_grabs_read on public.luckybag_grabs for select to authenticated using (true);

alter publication supabase_realtime add table public.room_games, public.luckybag_grabs;

-- ---------------------------------------------------------------- lucky games
-- New branches: fruit (8-fruit party wheel), gems (pick a gem, three gems drop), wheel (16-slot lucky wheel).
create or replace function public.play_game(p_game text, p_bet bigint default 0, p_pick jsonb default '{}', p_room bigint default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); w wallets;
  rtp numeric := setting_num('game_rtp', 0.95);
  minb bigint := setting_num('min_bet', 10000)::bigint;
  maxb bigint := setting_num('max_bet', 50000000)::bigint;
  cap bigint := setting_num('daily_game_loss_cap', 50000000)::bigint;
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
  if total > maxb then raise exception 'maximum bet is % coins', maxb; end if;

  select coalesce(sum(gp.bet - gp.payout), 0) into lost from game_plays gp where gp.user_id = me and gp.created_at >= date_trunc('day', now());
  if lost + total > cap then raise exception 'daily game limit reached, please come back tomorrow'; end if;

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

-- ---------------------------------------------------------------- party games: helpers
create or replace function public._room_member(p_room bigint, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from room_members where room_id = p_room and user_id = p_user and role <> 'banned')
      or exists (select 1 from rooms where id = p_room and owner_id = p_user)
$$;

create or replace function public._room_staff(p_room bigint, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from rooms where id = p_room and owner_id = p_user)
      or exists (select 1 from room_members where room_id = p_room and user_id = p_user and role = 'admin')
$$;

-- pay the pot to the winner (minus the platform fee) and close the game
create or replace function public._party_win(g room_games, p_winner uuid, p_extra jsonb default '{}')
returns room_games language plpgsql security definer set search_path = public as $$
declare pot bigint := g.stake * coalesce(array_length(g.players, 1), 0); prize bigint;
begin
  prize := floor(pot * (1 - setting_num('party_fee', 0.05)));
  if prize > 0 then
    perform _wallet_add(p_winner, prize, 0, 'party_win', g.kind, jsonb_build_object('game', g.id, 'room', g.room_id));
  end if;
  update room_games set status = 'done', winner = p_winner, updated_at = now(),
         state = state || p_extra || jsonb_build_object('prize', prize)
   where id = g.id returning * into g;
  insert into room_messages(room_id, user_id, kind, body)
    values (g.room_id, p_winner, 'system',
            left('won ' || case g.kind when 'ttt' then 'Tic-Tac-Toe' when 'rps' then 'Rock Paper Scissors'
                                       when 'ludo' then 'Ludo' else g.kind end
                 || case when prize > 0 then ' · +' || prize || ' coins' else '' end || ' 🏆', 200));
  return g;
end $$;

-- give everyone their stake back
create or replace function public._party_refund(g room_games, p_status text default 'cancelled', p_extra jsonb default '{}')
returns room_games language plpgsql security definer set search_path = public as $$
declare p uuid;
begin
  if g.stake > 0 then
    foreach p in array g.players loop
      perform _wallet_add(p, g.stake, 0, 'party_refund', g.kind, jsonb_build_object('game', g.id));
    end loop;
  end if;
  update room_games set status = p_status, updated_at = now(), state = state || p_extra
   where id = g.id returning * into g;
  return g;
end $$;

create or replace function public._ludo_colors(n int) returns jsonb language sql immutable as $$
  select case n when 2 then '["red","yellow"]'::jsonb when 3 then '["red","green","yellow"]'::jsonb
                else '["red","green","yellow","blue"]'::jsonb end
$$;

create or replace function public._ludo_offset(c text) returns int language sql immutable as $$
  select case c when 'red' then 0 when 'green' then 13 when 'yellow' then 26 else 39 end
$$;

-- start the game once everyone is in
create or replace function public._party_start(g room_games) returns room_games
language plpgsql security definer set search_path = public as $$
declare n int := array_length(g.players, 1); toks jsonb := '[]';
begin
  if g.kind = 'ttt' then
    update room_games set status = 'playing', updated_at = now(),
           state = jsonb_build_object('board', '["","","","","","","","",""]'::jsonb, 'turn', 0)
     where id = g.id returning * into g;
  elsif g.kind = 'rps' then
    update room_games set status = 'playing', updated_at = now(),
           state = jsonb_build_object('round', 1, 'moved', '[]'::jsonb, 'history', '[]'::jsonb)
     where id = g.id returning * into g;
  elsif g.kind = 'ludo' then
    for i in 1 .. n loop toks := toks || jsonb_build_array(jsonb_build_array(-1, -1, -1, -1)); end loop;
    update room_games set status = 'playing', updated_at = now(),
           state = jsonb_build_object('turn', 0, 'dice', null, 'rolled', false, 'sixes', 0,
                                      'tokens', toks, 'colors', _ludo_colors(n), 'movable', '[]'::jsonb,
                                      'out', '[]'::jsonb, 'last', null)
     where id = g.id returning * into g;
  end if;
  return g;
end $$;

-- ---------------------------------------------------------------- party games: public API
-- p_opts:
--   luckybag: {"total": 100000, "count": 10}
--   pk:       {"a": "<uuid>", "b": "<uuid>", "minutes": 3}
--   ludo:     {"stake": 10000, "players": 2..4}
--   ttt, rps: {"stake": 0 | >= min bet}
--   bottle:   {}
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
    if tot > maxb then raise exception 'maximum is % coins', maxb; end if;
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
  if stake <> 0 and (stake < minb or stake > maxb) then raise exception 'stake must be 0 or between % and % coins', minb, maxb; end if;
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

create or replace function public.party_join(p_id bigint)
returns public.room_games language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); g room_games; w wallets;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  select * into g from room_games where id = p_id for update;
  if not found or g.kind not in ('ludo','ttt','rps') then raise exception 'game not found'; end if;
  if not _room_member(g.room_id, me) then raise exception 'join the room first'; end if;
  if g.status <> 'waiting' then raise exception 'this game has already started'; end if;
  if me = any(g.players) then return g; end if;
  if array_length(g.players, 1) >= g.max_players then raise exception 'this game is full'; end if;
  if g.stake > 0 then
    if not exists (select 1 from profiles where id = me and games_ok_at is not null) then raise exception 'confirm you are 18 or older first'; end if;
    select * into w from wallets where user_id = me for update;
    if w.coins < g.stake then raise exception 'insufficient coins'; end if;
    perform _wallet_add(me, -g.stake, 0, 'party_stake', g.kind, jsonb_build_object('room', g.room_id, 'game', g.id));
  end if;
  update room_games set players = players || me, updated_at = now() where id = p_id returning * into g;
  if array_length(g.players, 1) >= g.max_players then g := _party_start(g); end if;
  return g;
end $$;

-- the host can start Ludo early with 2 or 3 people
create or replace function public.party_start(p_id bigint)
returns public.room_games language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); g room_games;
begin
  select * into g from room_games where id = p_id for update;
  if not found or g.host_id <> me then raise exception 'only the host can start'; end if;
  if g.status <> 'waiting' then return g; end if;
  if array_length(g.players, 1) < 2 then raise exception 'waiting for another player'; end if;
  update room_games set max_players = array_length(players, 1) where id = p_id returning * into g;
  return _party_start(g);
end $$;

create or replace function public.party_leave(p_id bigint)
returns public.room_games language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); g room_games; others uuid[]; outs jsonb; idx int; alive uuid[];
begin
  select * into g from room_games where id = p_id for update;
  if not found then raise exception 'game not found'; end if;
  if not (me = any(g.players)) and g.host_id <> me then raise exception 'you are not in this game'; end if;
  if g.status = 'waiting' then
    if g.host_id = me then return _party_refund(g, 'cancelled'); end if;
    if g.stake > 0 then perform _wallet_add(me, g.stake, 0, 'party_refund', g.kind, jsonb_build_object('game', g.id)); end if;
    update room_games set players = array_remove(players, me), updated_at = now() where id = p_id returning * into g;
    return g;
  end if;
  if g.status <> 'playing' or g.kind not in ('ludo','ttt','rps') then return g; end if;
  -- leaving a running game forfeits it
  if g.kind = 'ludo' and array_length(g.players, 1) > 2 then
    idx := array_position(g.players, me) - 1;
    outs := coalesce(g.state->'out', '[]'::jsonb);
    if not outs @> to_jsonb(idx) then outs := outs || to_jsonb(idx); end if;
    select array_agg(p) into alive from unnest(g.players) with ordinality as t(p, n) where not outs @> to_jsonb((n - 1)::int);
    if array_length(alive, 1) = 1 then return _party_win(g, alive[1], jsonb_build_object('out', outs)); end if;
    update room_games set state = state || jsonb_build_object('out', outs), updated_at = now() where id = p_id returning * into g;
    if (g.state->>'turn')::int = idx then g := _ludo_next(g, false); end if;
    return g;
  end if;
  select array_agg(p) into others from unnest(g.players) p where p <> me;
  return _party_win(g, others[1], jsonb_build_object('forfeit', me));
end $$;

-- ---------------------------------------------------------------- ludo engine
-- token progress: -1 yard · 0..50 main track · 51..55 home lane · 56 finished
create or replace function public._ludo_abs(c text, p int) returns int language sql immutable as $$
  select (_ludo_offset(c) + p) % 52
$$;

create or replace function public._ludo_movable(g room_games, d int) returns jsonb
language plpgsql stable as $$
declare t int := (g.state->>'turn')::int; toks jsonb := g.state->'tokens'->t; res jsonb := '[]'; p int;
begin
  for i in 0 .. 3 loop
    p := (toks->>i)::int;
    if (p = -1 and d = 6) or (p >= 0 and p + d <= 56) then res := res || to_jsonb(i); end if;
  end loop;
  return res;
end $$;

create or replace function public._ludo_next(g room_games, p_again boolean)
returns room_games language plpgsql security definer set search_path = public as $$
declare n int := array_length(g.players, 1); t int := (g.state->>'turn')::int; outs jsonb := coalesce(g.state->'out', '[]'::jsonb);
begin
  if not p_again then
    loop
      t := (t + 1) % n;
      exit when not outs @> to_jsonb(t);
    end loop;
  end if;
  update room_games set updated_at = now(),
         state = state || jsonb_build_object('turn', t, 'rolled', false, 'movable', '[]'::jsonb,
                                             'sixes', case when p_again then (state->>'sixes')::int else 0 end)
   where id = g.id returning * into g;
  return g;
end $$;

create or replace function public._ludo_move(g room_games, me uuid, mv jsonb)
returns room_games language plpgsql security definer set search_path = public as $$
declare
  st jsonb := g.state; t int := (g.state->>'turn')::int; d int; tok int; p int; np int;
  col text; ab int; captured boolean := false; safe int[] := array[0,8,13,21,26,34,39,47];
  toks jsonb; other text; done boolean;
begin
  if g.players[t + 1] <> me then raise exception 'not your turn'; end if;
  if mv->>'action' = 'roll' then
    if (st->>'rolled')::boolean then raise exception 'move a token first'; end if;
    d := floor(_rand() * 6)::int + 1;
    st := st || jsonb_build_object('dice', d, 'last', jsonb_build_object('roll', d, 'by', t));
    if d = 6 and (st->>'sixes')::int >= 2 then
      -- third six in a row: turn is lost
      update room_games set state = st || jsonb_build_object('sixes', 0) where id = g.id returning * into g;
      return _ludo_next(g, false);
    end if;
    if d = 6 then st := st || jsonb_build_object('sixes', (st->>'sixes')::int + 1); end if;
    update room_games set state = st, updated_at = now() where id = g.id returning * into g;
    if jsonb_array_length(_ludo_movable(g, d)) = 0 then
      return _ludo_next(g, false);
    end if;
    update room_games set state = state || jsonb_build_object('rolled', true, 'movable', _ludo_movable(g, d))
     where id = g.id returning * into g;
    return g;
  end if;

  if mv->>'action' <> 'move' then raise exception 'unknown move'; end if;
  if not (st->>'rolled')::boolean then raise exception 'roll the dice first'; end if;
  tok := (mv->>'token')::int;
  if not (st->'movable') @> to_jsonb(tok) then raise exception 'that token cannot move'; end if;
  d := (st->>'dice')::int;
  col := st->'colors'->>t;
  p := (st->'tokens'->t->>tok)::int;
  np := case when p = -1 then 0 else p + d end;
  toks := jsonb_set(st->'tokens', array[t::text, tok::text], to_jsonb(np));
  -- capture opponents on the main track (not on safe squares)
  if np <= 50 then
    ab := _ludo_abs(col, np);
    if not (ab = any(safe)) then
      for o in 0 .. jsonb_array_length(toks) - 1 loop
        continue when o = t;
        other := st->'colors'->>o;
        for j in 0 .. 3 loop
          p := (toks->o->>j)::int;
          if p between 0 and 50 and _ludo_abs(other, p) = ab then
            toks := jsonb_set(toks, array[o::text, j::text], '-1'::jsonb);
            captured := true;
          end if;
        end loop;
      end loop;
    end if;
  end if;
  st := st || jsonb_build_object('tokens', toks, 'rolled', false, 'movable', '[]'::jsonb,
                                 'last', jsonb_build_object('by', t, 'token', tok, 'from', (g.state->'tokens'->t->>tok)::int,
                                                            'to', np, 'captured', captured, 'dice', d));
  update room_games set state = st, updated_at = now() where id = g.id returning * into g;
  select bool_and((x)::int = 56) into done from jsonb_array_elements_text(toks->t) x;
  if done then return _party_win(g, me); end if;
  return _ludo_next(g, d = 6 or captured or np = 56);
end $$;

-- ---------------------------------------------------------------- moves
--   ttt:  {"cell": 0..8}
--   rps:  {"hand": "rock" | "paper" | "scissors"}
--   ludo: {"action": "roll"} or {"action": "move", "token": 0..3}
--   any:  {"action": "timeout"} claims the win (or skips, in Ludo) when the other side has been idle for 40 seconds
create or replace function public.party_move(p_id bigint, p_move jsonb)
returns public.room_games language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); g room_games; st jsonb; t int; cell int; b jsonb; mark text;
  lines int[] := array[0,1,2, 3,4,5, 6,7,8, 0,3,6, 1,4,7, 2,5,8, 0,4,8, 2,4,6];
  hand text; h1 text; h2 text; moved jsonb; win uuid; idle uuid; hist jsonb;
begin
  select * into g from room_games where id = p_id for update;
  if not found then raise exception 'game not found'; end if;
  if g.status <> 'playing' then raise exception 'this game is not running'; end if;
  if not (me = any(g.players)) then raise exception 'you are not playing in this game'; end if;
  st := g.state;

  if p_move->>'action' = 'timeout' then
    if g.updated_at > now() - interval '40 seconds' then raise exception 'give them a moment'; end if;
    if g.kind = 'ludo' then
      if g.players[(st->>'turn')::int + 1] = me then raise exception 'it is your turn'; end if;
      return _ludo_next(g, false);
    elsif g.kind = 'ttt' then
      idle := g.players[(st->>'turn')::int + 1];
    else
      select p into idle from unnest(g.players) p where not (st->'moved') @> to_jsonb(p::text) limit 1;
    end if;
    if idle is null or idle = me then raise exception 'it is your move'; end if;
    select p into win from unnest(g.players) p where p <> idle limit 1;
    return _party_win(g, win, jsonb_build_object('timeout', idle));
  end if;

  if g.kind = 'ttt' then
    t := (st->>'turn')::int;
    if g.players[t + 1] <> me then raise exception 'not your turn'; end if;
    cell := (p_move->>'cell')::int;
    if cell is null or cell < 0 or cell > 8 then raise exception 'pick a square'; end if;
    b := st->'board';
    if b->>cell <> '' then raise exception 'that square is taken'; end if;
    mark := case t when 0 then 'X' else 'O' end;
    b := jsonb_set(b, array[cell::text], to_jsonb(mark));
    update room_games set state = state || jsonb_build_object('board', b, 'turn', 1 - t, 'last', cell), updated_at = now()
     where id = p_id returning * into g;
    for i in 0 .. 7 loop
      if b->>lines[i*3+1] = mark and b->>lines[i*3+2] = mark and b->>lines[i*3+3] = mark then
        return _party_win(g, me, jsonb_build_object('line', jsonb_build_array(lines[i*3+1], lines[i*3+2], lines[i*3+3])));
      end if;
    end loop;
    if not exists (select 1 from jsonb_array_elements_text(b) x where x = '') then
      return _party_refund(g, 'done', jsonb_build_object('draw', true));
    end if;
    return g;

  elsif g.kind = 'rps' then
    hand := p_move->>'hand';
    if hand not in ('rock','paper','scissors') then raise exception 'pick rock, paper or scissors'; end if;
    if (st->'moved') @> to_jsonb(me::text) then raise exception 'waiting for the other player'; end if;
    insert into room_game_secrets(game_id, user_id, round, data) values (p_id, me, (st->>'round')::int, jsonb_build_object('hand', hand))
      on conflict (game_id, user_id, round) do update set data = excluded.data;
    moved := (st->'moved') || to_jsonb(me::text);
    update room_games set state = state || jsonb_build_object('moved', moved), updated_at = now() where id = p_id returning * into g;
    if jsonb_array_length(moved) < 2 then return g; end if;
    select data->>'hand' into h1 from room_game_secrets where game_id = p_id and user_id = g.players[1] and round = (st->>'round')::int;
    select data->>'hand' into h2 from room_game_secrets where game_id = p_id and user_id = g.players[2] and round = (st->>'round')::int;
    hist := (st->'history') || jsonb_build_array(jsonb_build_array(h1, h2));
    if h1 = h2 then
      if (st->>'round')::int >= 5 then
        return _party_refund(g, 'done', jsonb_build_object('draw', true, 'history', hist, 'moved', '[]'::jsonb));
      end if;
      update room_games set updated_at = now(),
             state = state || jsonb_build_object('round', (st->>'round')::int + 1, 'moved', '[]'::jsonb, 'history', hist)
       where id = p_id returning * into g;
      return g;
    end if;
    win := case when (h1 = 'rock' and h2 = 'scissors') or (h1 = 'paper' and h2 = 'rock') or (h1 = 'scissors' and h2 = 'paper')
                then g.players[1] else g.players[2] end;
    return _party_win(g, win, jsonb_build_object('history', hist, 'moved', '[]'::jsonb));

  elsif g.kind = 'ludo' then
    return _ludo_move(g, me, p_move);
  end if;
  raise exception 'this game has no moves';
end $$;

-- ---------------------------------------------------------------- lucky bag & PK
create or replace function public.luckybag_grab(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); g room_games; amt bigint; left_c int; left_t bigint; mx bigint;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  select * into g from room_games where id = p_id and kind = 'luckybag' for update;
  if not found then raise exception 'lucky bag not found'; end if;
  if not _room_member(g.room_id, me) then raise exception 'join the room first'; end if;
  if exists (select 1 from luckybag_grabs where game_id = p_id and user_id = me) then
    return jsonb_build_object('amount', (select amount from luckybag_grabs where game_id = p_id and user_id = me), 'again', true);
  end if;
  if g.status <> 'playing' or g.ends_at < now() then raise exception 'this lucky bag is empty'; end if;
  left_c := (g.state->>'left_count')::int; left_t := (g.state->>'left')::bigint;
  if left_c <= 1 then amt := left_t;
  else
    -- random share between 1 coin and twice the average of what is left
    mx := greatest(1, floor(left_t::numeric / left_c * 2));
    amt := greatest(1, least(left_t - (left_c - 1), floor(_rand() * mx)::bigint + 1));
  end if;
  insert into luckybag_grabs(game_id, user_id, amount) values (p_id, me, amt);
  perform _wallet_add(me, amt, 0, 'luckybag_grab', p_id::text, jsonb_build_object('room', g.room_id));
  update room_games set updated_at = now(), status = case when left_c - 1 <= 0 then 'done' else status end,
         state = state || jsonb_build_object('left', left_t - amt, 'left_count', left_c - 1)
   where id = p_id;
  return jsonb_build_object('amount', amt, 'again', false);
end $$;

-- return what nobody grabbed once a bag has expired; anyone in the room may call it
create or replace function public.party_tidy(p_room bigint)
returns void language plpgsql security definer set search_path = public as $$
declare g room_games;
begin
  for g in select * from room_games where room_id = p_room and kind = 'luckybag' and status = 'playing' and ends_at < now() for update loop
    if (g.state->>'left')::bigint > 0 then
      perform _wallet_add(g.host_id, (g.state->>'left')::bigint, 0, 'luckybag_return', g.id::text, '{}');
    end if;
    update room_games set status = 'done', state = state || jsonb_build_object('left', 0) where id = g.id;
  end loop;
  -- abandoned waiting tables
  for g in select * from room_games where room_id = p_room and kind in ('ludo','ttt','rps') and status = 'waiting'
              and updated_at < now() - interval '10 minutes' for update loop
    perform _party_refund(g, 'cancelled');
  end loop;
  -- finished PK battles
  update room_games rg set status = 'done', updated_at = now(),
         winner = (select s.uid from (
                     select x.uid, coalesce(sum(ge.total), 0) sc from unnest(rg.players) x(uid)
                       left join gift_events ge on ge.receiver_id = x.uid and ge.room_id = rg.room_id
                            and ge.created_at between rg.created_at and rg.ends_at
                      group by x.uid order by sc desc limit 1) s
                    where (select count(distinct sc2) from (
                             select coalesce(sum(ge2.total), 0) sc2 from unnest(rg.players) y(uid)
                               left join gift_events ge2 on ge2.receiver_id = y.uid and ge2.room_id = rg.room_id
                                    and ge2.created_at between rg.created_at and rg.ends_at group by y.uid) z) > 1)
   where rg.room_id = p_room and rg.kind = 'pk' and rg.status = 'playing' and rg.ends_at < now();
end $$;

create or replace function public.pk_scores(p_id bigint)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(x.uid, x.sc), '{}') from (
    select u.uid, coalesce(sum(ge.total), 0) sc
      from room_games g cross join unnest(g.players) u(uid)
      left join gift_events ge on ge.receiver_id = u.uid and ge.room_id = g.room_id
           and ge.created_at between g.created_at and coalesce(g.ends_at, now())
     where g.id = p_id and g.kind = 'pk'
     group by u.uid) x
$$;

revoke execute on function public._room_member(bigint,uuid), public._room_staff(bigint,uuid),
  public._party_win(room_games,uuid,jsonb), public._party_refund(room_games,text,jsonb), public._party_start(room_games),
  public._ludo_next(room_games,boolean), public._ludo_move(room_games,uuid,jsonb), public._ludo_movable(room_games,int)
  from public, anon, authenticated;
revoke execute on function public.party_create(bigint,text,jsonb), public.party_join(bigint), public.party_start(bigint),
  public.party_leave(bigint), public.party_move(bigint,jsonb), public.luckybag_grab(bigint), public.party_tidy(bigint),
  public.pk_scores(bigint) from public, anon;
grant execute on function public.party_create(bigint,text,jsonb), public.party_join(bigint), public.party_start(bigint),
  public.party_leave(bigint), public.party_move(bigint,jsonb), public.luckybag_grab(bigint), public.party_tidy(bigint),
  public.pk_scores(bigint) to authenticated, service_role;
