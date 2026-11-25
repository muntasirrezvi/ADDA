-- Adda: lucky games (results decided on the server), room join notices, leaderboards

alter table public.profiles add column if not exists games_ok_at timestamptz;

create table if not exists public.game_plays (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  room_id bigint references public.rooms(id) on delete set null,
  game text not null,
  bet bigint not null,
  payout bigint not null default 0,
  result jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists game_plays_user_idx on public.game_plays(user_id, created_at desc);
alter table public.game_plays enable row level security;
revoke all on public.game_plays from anon, authenticated;
grant select on public.game_plays to authenticated;
grant all on public.game_plays to service_role;
create policy game_plays_read on public.game_plays for select to authenticated using (user_id = auth.uid() or public.is_admin());

insert into public.app_settings(key, value) values
  ('games_enabled', 'true'),
  ('game_rtp', '0.95'),        -- share of bets paid back over time (0.95 = 95%)
  ('max_bet', '50000000')
on conflict (key) do nothing;

-- cryptographically random number in [0, 1)
create or replace function public._rand() returns double precision
language sql volatile as $$
  select ('x' || encode(extensions.gen_random_bytes(7), 'hex'))::bit(56)::bigint / 72057594037927936.0
$$;

create or replace function public.accept_games()
returns void language sql security definer set search_path = public as $$
  update profiles set games_ok_at = now() where id = auth.uid()
$$;

create or replace function public.my_game_status()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'enabled', coalesce(setting('games_enabled'), 'true'::jsonb) = 'true'::jsonb,
    'accepted', (select games_ok_at is not null from profiles where id = auth.uid()),
    'min_bet', setting_num('min_bet', 10000),
    'max_bet', setting_num('max_bet', 50000000),
    'daily_cap', setting_num('daily_game_loss_cap', 50000000),
    'lost_today', (select coalesce(sum(bet - payout), 0) from game_plays where user_id = auth.uid() and created_at >= date_trunc('day', now())))
$$;

-- One play of a lucky game. The server picks the result, takes the bet and pays any win in one step.
--   greedy: p_pick = {"bets": {"tomato": 10000, "steak": 20000}}  (total = sum)
--   slots:  p_bet
--   dice:   p_bet, p_pick = {"side": "big" | "small" | "seven"}
--   crash:  p_bet, p_pick = {"target": 2.5}   (cash out automatically at this multiplier)
create or replace function public.play_game(p_game text, p_bet bigint default 0, p_pick jsonb default '{}', p_room bigint default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); w wallets;
  rtp numeric := setting_num('game_rtp', 0.95);
  minb bigint := setting_num('min_bet', 10000)::bigint;
  maxb bigint := setting_num('max_bet', 50000000)::bigint;
  cap bigint := setting_num('daily_game_loss_cap', 50000000)::bigint;
  total bigint := 0; payout bigint := 0; lost bigint; u double precision; res jsonb;
  items text[] := array['tomato','corn','carrot','lettuce','fish','shrimp','steak','chicken'];
  mults int[] := array[5,5,5,5,10,15,25,45];
  k numeric := 0; acc numeric := 0; scale numeric; winner text := 'bomb'; i int; itm text; amt bigint;
  d1 int; d2 int; side text; tgt numeric; crashp numeric; outcome text := 'lose'; mult numeric := 0;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  if coalesce(setting('games_enabled'), 'true'::jsonb) <> 'true'::jsonb then raise exception 'games are switched off right now'; end if;
  if not exists (select 1 from profiles where id = me and games_ok_at is not null) then raise exception 'confirm you are 18 or older first'; end if;

  if p_game = 'greedy' then
    if jsonb_typeof(p_pick->'bets') <> 'object' then raise exception 'place a bet first'; end if;
    for itm, amt in select e.key, (e.value #>> '{}')::bigint from jsonb_each(p_pick->'bets') e loop
      if not (itm = any(items)) or amt < 0 then raise exception 'invalid bet'; end if;
      total := total + amt;
    end loop;
  elsif p_game in ('slots', 'dice', 'crash') then
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

  if p_game = 'greedy' then
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
    -- 777 x50, BAR x20, BELL x10, three cherries x5, two cherries x2 (base chances add up to 95% return)
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

-- leaderboards: wealth = coins gifted, charm = coins received as gifts
create or replace function public.leaderboard(p_kind text default 'wealth', p_period text default 'week', p_limit int default 50)
returns table (rank int, user_id uuid, username text, avatar_url text, avatar_preset int, public_id bigint, wealth_level int, score bigint)
language sql stable security definer set search_path = public as $$
  with s as (
    select case when p_kind = 'charm' then g.receiver_id else g.sender_id end as uid, sum(g.total)::bigint as score
      from gift_events g
     where g.created_at >= case p_period when 'day' then date_trunc('day', now())
                                         when 'week' then now() - interval '7 days'
                                         when 'month' then now() - interval '30 days'
                                         else '-infinity'::timestamptz end
     group by 1)
  select (row_number() over (order by s.score desc))::int, p.id, p.username, p.avatar_url, p.avatar_preset, p.public_id, p.wealth_level, s.score
    from s join profiles p on p.id = s.uid
   where p.deleted_at is null
   order by s.score desc
   limit least(p_limit, 100)
$$;

-- join_room now posts "joined the room" (at most once every 3 minutes per person)
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
  if not exists (select 1 from room_messages where room_id = p_room and user_id = me and kind = 'system'
                   and body = 'joined the room' and created_at > now() - interval '3 minutes') then
    insert into room_messages(room_id, user_id, kind, body) values (p_room, me, 'system', 'joined the room');
  end if;
  r.password_hash := null;
  return r;
end $$;

revoke execute on function public._rand() from public, anon, authenticated;
revoke execute on function public.accept_games(), public.my_game_status(), public.play_game(text,bigint,jsonb,bigint), public.leaderboard(text,text,int) from public, anon;
grant execute on function public.accept_games(), public.my_game_status(), public.play_game(text,bigint,jsonb,bigint), public.leaderboard(text,text,int) to authenticated, service_role;
