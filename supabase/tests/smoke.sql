-- Smoke test for a local Postgres 16 (not Supabase): run local_stubs.sql, then every migration, then this file.
\set ON_ERROR_STOP 1
set client_min_messages = notice;
insert into auth.users(id,email,phone,raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000a','admin@x.com','+8801','{"username":"rezvi"}'),
 ('00000000-0000-0000-0000-00000000000b','b@x.com','+8802','{"username":"bob"}'),
 ('00000000-0000-0000-0000-00000000000c','c@x.com','+8803','{"username":"cara"}');
update profiles set role='admin' where username='rezvi';
select username, public_id, (select coins from wallets w where w.user_id=p.id) coins from profiles p order by public_id;

create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claim.sub', u, false); execute 'set role authenticated'; end $$;
-- bob: create room, buy pack, send gift
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select id, name, cover_template from create_room('Bob Lounge','Music','English',8,null,'dunes','majlis','1234');
select count(*) seats from room_seats where room_id=200;
\echo -- password_hash hidden:
do $$ begin perform password_hash from rooms; raise exception 'LEAK'; exception when insufficient_privilege then raise notice 'ok hidden'; end $$;
\echo -- try to give self coins (must fail):
do $$ begin update wallets set coins=999999999; if found then raise exception 'LEAK'; end if; raise notice 'no rows updated: ok'; exception when insufficient_privilege then raise notice 'ok denied'; end $$;
do $$ begin update rooms set featured=true where id=200; raise exception 'LEAK'; exception when insufficient_privilege then raise notice 'ok featured denied'; end $$;
update rooms set cover_template='lotus', name='Bob Lounge 2' where id=200;
do $$ begin update rooms set theme='palace' where id=200; raise exception 'LEAK'; exception when others then raise notice 'premium theme blocked: %', sqlerrm; end $$;
do $$ begin update rooms set cover_url='https://x.supabase.co/storage/v1/object/public/room-covers/00000000-0000-0000-0000-00000000000c/a.jpg' where id=200; raise exception 'LEAK'; exception when others then raise notice 'foreign cover blocked: %', sqlerrm; end $$;
update rooms set cover_url='https://x.supabase.co/storage/v1/object/public/room-covers/00000000-0000-0000-0000-00000000000b/a.jpg' where id=200;
select * from my_coin_packs() limit 3;
select id, amount, currency, coins from create_payment('p10') \gset pay_
reset role;
select complete_payment(:'pay_id', 'VAL1', '{}', 999, 'BDT') mismatch;
update payments set status='pending' where id=:'pay_id';
select complete_payment(:'pay_id', 'VAL1', '{}', :pay_amount, 'BDT') ok;
select complete_payment(:'pay_id', 'VAL1', '{}', :pay_amount, 'BDT') again;
select record_store_purchase('00000000-0000-0000-0000-00000000000c','google_play','coins_500k','tok1','{}') play1;
select record_store_purchase('00000000-0000-0000-0000-00000000000c','google_play','coins_500k','tok1','{}') play_dup;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select * from join_room(200,'1234') \gset
do $$ begin perform join_room(200,'0000'); exception when others then raise notice 'n/a'; end $$;
select take_seat(200,3);
select send_gift(200, array['00000000-0000-0000-0000-00000000000b']::uuid[], 'ring', 1) gift;
do $$ begin perform send_gift(200, array['00000000-0000-0000-0000-00000000000b']::uuid[], 'palace', 10); exception when others then raise notice 'bad qty: %', sqlerrm; end $$;
insert into room_messages(room_id,user_id,body) values (200,'00000000-0000-0000-0000-00000000000c','you stupid fellow');
do $$ begin insert into room_messages(room_id,user_id,body) values (200,'00000000-0000-0000-0000-00000000000c','visit spam.com'); exception when others then raise notice 'link: %', sqlerrm; end $$;
select body from room_messages;
select count(*) other_wallets_visible from wallets where user_id <> auth.uid();
select count(*) other_private_visible from profile_private where user_id <> auth.uid();
select * from start_call('00000000-0000-0000-0000-00000000000b','video') \gset call_
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select status from update_call(:'call_id','active');
select status from update_call(:'call_id','ended');
select kind, body from direct_messages;
select coins, diamonds from wallets;
select daily_checkin(); select daily_checkin();
select name, cover_image, featured, on_mic, owner_name from home_rooms();
select jsonb_array_length(home_feed()->'banners') banners, jsonb_array_length(home_feed()->'templates') templates;
do $$ begin perform admin_stats(); exception when others then raise notice 'non-admin stats: %', sqlerrm; end $$;
-- admin
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select featured, cover_url from admin_update_room(200, '{"featured":true,"cover_url":"https://x.supabase.co/storage/v1/object/public/room-covers/admin/hero.jpg","cover_template":"neon"}');
select admin_stats(7)->>'revenue_usd' rev, admin_stats(7)->>'total_users' users;
select username, coins from admin_find_users('cara');
select admin_adjust_coins('00000000-0000-0000-0000-00000000000c', 5000, 'test');
update room_cover_templates set image_url='https://x/storage/v1/object/public/room-covers/admin/lantern.jpg' where id='lantern';
select admin_set_role('00000000-0000-0000-0000-00000000000b','agent'); select admin_add_agent_stock('00000000-0000-0000-0000-00000000000b', 10000000);
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select agent_sell((select public_id from profiles where username='cara'), 2000000, 'bkash', 500);
reset role;
select action, target from audit_log order by id;
select kind, count(*) from transactions group by 1 order by 1;
\set ON_ERROR_STOP 1
set client_min_messages = notice;
create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$ begin
  reset role; perform set_config('request.jwt.claim.sub', u, false); execute 'set role authenticated'; end $$;
-- admin=a, agents b and d, user c
insert into auth.users(id,email,phone,raw_user_meta_data) values ('00000000-0000-0000-0000-00000000000d','d@x.com','+8804','{"username":"dina","phone":"+8804"}');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select admin_set_role('00000000-0000-0000-0000-00000000000d','agent');
select admin_add_agent_stock('00000000-0000-0000-0000-00000000000d', 100000000);
select admin_set_topup_agent('00000000-0000-0000-0000-00000000000b', true, 'Agent Bob');
select admin_set_topup_agent('00000000-0000-0000-0000-00000000000d', true, 'Agent Dina');
insert into agent_pay_accounts(agent_id, method, account_number, account_name, instructions) values
 ('00000000-0000-0000-0000-00000000000b','bkash','01711111111','Bob','Send Money only'),
 ('00000000-0000-0000-0000-00000000000d','bkash','01722222222','Dina',null),
 ('00000000-0000-0000-0000-00000000000d','nagad','01822222222','Dina',null);
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select * from topup_methods() order by 1;
select create_topup_order('p10','bkash') o1 \gset
\echo :o1
select (:'o1'::jsonb)->>'id' as oid, (:'o1'::jsonb)->>'pay_to' as payto \gset
\set ON_ERROR_STOP 0
select submit_topup_proof(:'oid', '01799', 'x1');
\set ON_ERROR_STOP 1
select status, trx_id from submit_topup_proof(:'oid', '01799999999', 'bkh 8a7d6c5b');
select count(*) agent_accounts_visible_to_user from agent_pay_accounts;
-- second order reuses trx -> fail
select (create_topup_order('p1','bkash'))->>'id' as oid2 \gset
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
\set ON_ERROR_STOP 0
select submit_topup_proof(:'oid2', '01799999999', 'BKH8A7D6C5B');
\set ON_ERROR_STOP 1
select cancel_topup_order(:'oid2');
-- the wrong agent cannot approve
select agent_id = '00000000-0000-0000-0000-00000000000b' as is_bob from topup_orders where id = :'oid' \gset
select pg_temp.as_user(case when :'is_bob' then '00000000-0000-0000-0000-00000000000d' else '00000000-0000-0000-0000-00000000000b' end);
\set ON_ERROR_STOP 0
select approve_topup(:'oid');
\set ON_ERROR_STOP 1
select count(*) orders_visible_to_other_agent from topup_orders;
-- right agent approves
select pg_temp.as_user(case when :'is_bob' then '00000000-0000-0000-0000-00000000000b' else '00000000-0000-0000-0000-00000000000d' end);
select username, coins, waiting from agent_overview();
select approve_topup(:'oid');
\set ON_ERROR_STOP 0
select approve_topup(:'oid');
\set ON_ERROR_STOP 1
reset role;
select u.username, w.coins from wallets w join profiles u on u.id=w.user_id order by u.public_id;
select provider, amount, currency, coins, status from payments where provider='agent';
select status, count(*) from topup_orders group by 1;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select admin_stats(7)->>'revenue_usd' rev;
reset role;
-- games, leaderboards, join notices
\set ON_ERROR_STOP 1
create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$ begin
  reset role; perform set_config('request.jwt.claim.sub', u, false); execute 'set role authenticated'; end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
\set ON_ERROR_STOP 0
select play_game('slots', 10000);
\set ON_ERROR_STOP 1
select accept_games();
select my_game_status();
reset role; update wallets set coins = 100000000000 where user_id = '00000000-0000-0000-0000-00000000000c'; update app_settings set value='1000000000000' where key='daily_game_loss_cap';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select play_game('greedy', 0, '{"bets":{"tomato":10000,"steak":20000}}');
select play_game('dice', 10000, '{"side":"seven"}');
select play_game('crash', 10000, '{"target":2}');
\set ON_ERROR_STOP 0
select play_game('slots', 5000);
select play_game('greedy', 0, '{"bets":{"pizza":10000}}');
\set ON_ERROR_STOP 1
-- simulate return-to-player over many plays
do $$ declare g text; i int; begin
  foreach g in array array['greedy','slots','dice','crash'] loop
    for i in 1..200 loop
      perform play_game(g, 10000, case g when 'greedy' then '{"bets":{"tomato":2500,"corn":2500,"fish":2500,"chicken":2500}}'::jsonb when 'dice' then '{"side":"big"}'::jsonb when 'crash' then '{"target":2}'::jsonb else '{}'::jsonb end);
    end loop; end loop; end $$;
reset role;
select game, count(*), round(sum(payout)::numeric / sum(bet), 3) as rtp from game_plays group by 1 order by 1;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select rank, username, score from leaderboard('wealth','week');
select rank, username, score from leaderboard('charm','all');
reset role; select body, user_id is not null from room_messages where kind='system' order by id;
-- new lucky games and party games
reset role;
\set ON_ERROR_STOP 1
update wallets set coins = 100000000000 where user_id in ('00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000d');
update profiles set games_ok_at = now();
insert into room_members(room_id, user_id) select r.id, u from (select min(id) id from rooms) r,
  unnest(array['00000000-0000-0000-0000-00000000000c','00000000-0000-0000-0000-00000000000d']::uuid[]) u on conflict do nothing;
update room_seats set user_id = null where user_id in ('00000000-0000-0000-0000-00000000000c','00000000-0000-0000-0000-00000000000d');
insert into room_seats(room_id, seat, user_id) select (select min(id) from rooms), 1, '00000000-0000-0000-0000-00000000000c'
  on conflict (room_id, seat) do update set user_id = excluded.user_id;
insert into room_seats(room_id, seat, user_id) select (select min(id) from rooms), 2, '00000000-0000-0000-0000-00000000000d'
  on conflict (room_id, seat) do update set user_id = excluded.user_id;
select min(id) as rid from rooms \gset
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select play_game('fruit', 0, '{"bets":{"apple":10000,"banana":10000}}');
select play_game('gems', 10000, '{"gem":"ruby"}');
select play_game('wheel', 10000);
do $$ declare g text; i int; begin
  foreach g in array array['fruit','gems','wheel'] loop
    for i in 1..300 loop
      perform play_game(g, 10000, case g when 'fruit' then '{"bets":{"apple":2500,"grape":2500,"cherry":2500,"banana":2500}}'::jsonb when 'gems' then '{"gem":"topaz"}'::jsonb else '{}'::jsonb end);
    end loop; end loop; end $$;
reset role;
select game, count(*), round(sum(payout)::numeric / sum(bet), 3) as rtp from game_plays group by 1 order by 1;
-- spin the bottle
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select kind, status, state ? 'target' as has_target from party_create(:rid, 'bottle');
-- lucky bag: d sends 100000 for 3 people; b, c, d grab
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select id as bag from party_create(:rid, 'luckybag', '{"total":100000,"count":3}') \gset
select luckybag_grab(:bag);
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select luckybag_grab(:bag);
select luckybag_grab(:bag);
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select luckybag_grab(:bag);
select sum(amount) = 100000 as bag_ok, count(*) from luckybag_grabs where game_id = :bag;
-- tic-tac-toe: c (X) beats d (O) on the top row
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select id as t from party_create(:rid, 'ttt', '{"stake":10000}') \gset
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select status from party_join(:t);
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');  select (party_move(:t, '{"cell":0}')).state->'board';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');  select (party_move(:t, '{"cell":4}')).state->'turn';
\set ON_ERROR_STOP 0
select party_move(:t, '{"cell":5}');
\set ON_ERROR_STOP 1
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');  select (party_move(:t, '{"cell":1}')).status;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');  select (party_move(:t, '{"cell":8}')).status;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');  select g.status, g.winner, g.state->'line', g.state->'prize' from party_move(:t, '{"cell":2}') g;
-- rock paper scissors (one draw, then paper beats rock)
select id as r from party_create(:rid, 'rps', '{"stake":0}') \gset
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');  select status from party_join(:r);
select (party_move(:r, '{"hand":"rock"}')).state->'moved';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');  select (party_move(:r, '{"hand":"rock"}')).state->'round';
select (party_move(:r, '{"hand":"paper"}')).status;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');  select g.status, g.winner, g.state->'history' from party_move(:r, '{"hand":"rock"}') g;
-- PK between c and d
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select id as pk from party_create(:rid, 'pk', jsonb_build_object('a','00000000-0000-0000-0000-00000000000c','b','00000000-0000-0000-0000-00000000000d','minutes',1)) \gset
select pk_scores(:pk);
-- ludo: two players play to the end with random rolls
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select id as lu from party_create(:rid, 'ludo', '{"stake":10000,"players":2}') \gset
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');  select status, state->'colors' from party_join(:lu);
reset role;
grant select on room_games to authenticated;
do $$ declare g room_games; who uuid; n int := 0; begin
  loop
    select * into g from room_games where id = (select max(id) from room_games where kind = 'ludo');
    exit when g.status <> 'playing' or n > 5000;
    who := g.players[(g.state->>'turn')::int + 1];
    perform set_config('request.jwt.claim.sub', who::text, true);
    if (g.state->>'rolled')::boolean then
      perform party_move(g.id, jsonb_build_object('action','move','token', (g.state->'movable'->>0)::int));
    else
      perform party_move(g.id, '{"action":"roll"}');
    end if;
    n := n + 1;
  end loop;
  raise notice 'ludo finished after % actions, status %', n, g.status;
end $$;
select status, winner is not null as has_winner, state->'tokens', state->'prize' from room_games where kind = 'ludo';
select kind, status from room_games order by id;
select u.username, w.coins from wallets w join profiles u on u.id=w.user_id order by u.public_id;
-- withdrawals, 7-day reward, admin user detail
reset role;
update wallets set diamonds = 20000000 where user_id = '00000000-0000-0000-0000-00000000000c';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select (withdraw_status())->'can' as can_before, jsonb_path_query_array(withdraw_status()->'checks', '$[*] ? (@.ok == false).key') as failing;
\set ON_ERROR_STOP 0
select request_withdrawal(6250000, 'bkash', '01700000000', 'Test');
\set ON_ERROR_STOP 1
reset role;
update profiles set verified = true, created_at = now() - interval '30 days' where id = '00000000-0000-0000-0000-00000000000c';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
-- withdrawals are switched off: every request must fail
\set ON_ERROR_STOP 0
select request_withdrawal(6250000, 'bkash', '01700000000', 'Test');
\set ON_ERROR_STOP 1
select count(*) as payouts_after from payouts;
-- daily reward: day 1 today, then simulate a streak
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select checkin_status()->'days' as days;
select daily_checkin();
select daily_checkin();
reset role;
update daily_checkins set day = current_date - 1 where user_id = '00000000-0000-0000-0000-00000000000d';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select daily_checkin() as day2;
reset role;
update daily_checkins set day = day - 10 where user_id = '00000000-0000-0000-0000-00000000000d';
insert into daily_checkins(user_id, day, reward, streak_day) values ('00000000-0000-0000-0000-00000000000d', current_date - 1, 1, 7);
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select daily_checkin() as after_day7_restarts;
select ai_avatar_quota();
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select jsonb_object_keys(admin_user_detail('00000000-0000-0000-0000-00000000000c')) k order by 1;
select admin_user_detail('00000000-0000-0000-0000-00000000000c')->'stats';
-- presence, room people, transfers, agent store, exchange, custom top-up
reset role;
update profiles set role = 'user' where id = '00000000-0000-0000-0000-00000000000d';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select touch_presence();
select set_presence_privacy(true);
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select online, last_seen is null as time_hidden, hidden from user_presence(array['00000000-0000-0000-0000-00000000000c'::uuid]);
select (join_room(:rid)).listeners as listeners_after_join;
select room_ping(:rid);
select jsonb_array_length(room_people(:rid)->'active') as active_n;
select leave_room(:rid);
select jsonb_array_length(room_people(:rid)->'left') as left_n;
-- admin grants unlimited coins + diamonds, makes c an agent and fills the store
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select admin_grant('00000000-0000-0000-0000-00000000000d', 999000000000, 5000, 'test');
select admin_set_role('00000000-0000-0000-0000-00000000000c', 'agent');
select admin_stock('00000000-0000-0000-0000-00000000000c', 50000000, 1000, 'load');
select (find_user((select public_id from profiles where id = '00000000-0000-0000-0000-00000000000b')))->>'username' as found;
-- agent sends from store
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select store_transfer((select public_id from profiles where id = '00000000-0000-0000-0000-00000000000d'), 1000000, 10, 'promo');
select (my_store())->'coins' as store_coins_left, (my_store())->'diamonds' as store_dia_left;
\set ON_ERROR_STOP 0
select store_transfer((select public_id from profiles where id = '00000000-0000-0000-0000-00000000000d'), 999999999999, 0);
select store_transfer((select public_id from profiles where id = '00000000-0000-0000-0000-00000000000c'), 1000, 0);
\set ON_ERROR_STOP 1
-- user to user
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select user_transfer((select public_id from profiles where id = '00000000-0000-0000-0000-00000000000b'), 50000, 3, 'hi');
\set ON_ERROR_STOP 0
select user_transfer((select public_id from profiles where id = '00000000-0000-0000-0000-00000000000d'), 50000, 0);
\set ON_ERROR_STOP 1
select exchange_coins(2);
select custom_topup_quote('coins', 123456), custom_topup_quote('diamonds', 1);
select jsonb_array_length((wallet_info())->'recent') as my_transfers;
reset role;
select kind, coins, diamonds from coin_transfers order by id;
-- reel options
reset role;
insert into reels(id, user_id, video_url) values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000b', 'x');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
update reels set caption = 'edited', comments_off = true, hide_likes = true, pinned = true, edited_at = now() where id = '11111111-1111-1111-1111-111111111111';
select caption, comments_off, pinned from reels where id = '11111111-1111-1111-1111-111111111111';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
\set ON_ERROR_STOP 0
insert into reel_comments(reel_id, user_id, body) values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000d', 'hi');
update reels set caption = 'hacked' where id = '11111111-1111-1111-1111-111111111111';
\set ON_ERROR_STOP 1
insert into reel_saves(user_id, reel_id) values ('00000000-0000-0000-0000-00000000000d', '11111111-1111-1111-1111-111111111111');
insert into reel_hidden(user_id, reel_id) values ('00000000-0000-0000-0000-00000000000d', '11111111-1111-1111-1111-111111111111');
select count(*) as saved from reel_saves;
reset role;
select caption from reels where id = '11111111-1111-1111-1111-111111111111';
