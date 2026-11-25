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
