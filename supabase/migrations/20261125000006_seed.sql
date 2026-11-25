-- Adda: starting data. Everything here can be edited later in the admin panel.

insert into public.app_settings(key, value) values
  ('coins_per_usd',       '500000'),
  ('usd_to_bdt',          '122'),
  ('welcome_bonus',       '100000'),
  ('diamond_rate',        '0.5'),     -- receiver gets 0.5 diamond per coin gifted
  ('diamond_to_coins',    '1'),       -- 1 diamond -> 1 coin. Never set diamond_rate x diamond_to_coins >= 1, or gifting becomes a coin loop
  ('diamonds_per_usd',    '625000'),  -- host payout: hosts receive 40% of gift value in cash
  ('min_payout_diamonds', '6250000'), -- $10
  ('creator_share',       '0.8'),     -- reel donations: creator keeps 80%
  ('min_bet',             '10000'),
  ('daily_game_loss_cap', '50000000'),
  ('blocked_words',       '["idiot","stupid","scam"]'),
  ('home_layout',         '["banners","stories","events","rooms"]'),
  ('support_contact',     '"support@adda.app"'),
  ('maintenance',         'false'),
  ('min_app_version',     '"1.0.0"')
on conflict (key) do nothing;

-- 500,000 coins = $1. BDT prices are for SSLCommerz (bKash, Nagad, cards); Google Play uses the
-- price set on each product in Play Console.
insert into public.coin_packs(id, usd, bdt, coins, discount_pct, play_product_id, sort) values
  ('p1',   1,   122,   500000,    0,  'coins_500k', 1),
  ('p5',   5,   610,   2500000,   2,  'coins_2_5m', 2),
  ('p10',  10,  1220,  5000000,   4,  'coins_5m',   3),
  ('p20',  20,  2440,  10000000,  6,  'coins_10m',  4),
  ('p50',  50,  6100,  25000000,  8,  'coins_25m',  5),
  ('p100', 100, 12200, 50000000,  10, 'coins_50m',  6),
  ('p200', 200, 24400, 100000000, 12, 'coins_100m', 7)
on conflict (id) do nothing;

insert into public.gifts(id, name, price, tier, sort) values
  ('rose',      'Rose',          10000,     'classic',   1),
  ('coffee',    'Karak Chai',    20000,     'classic',   2),
  ('kiss',      'Kiss',          50000,     'classic',   3),
  ('perfume',   'Oud Perfume',   100000,    'classic',   4),
  ('teddy',     'Teddy',         200000,    'classic',   5),
  ('ring',      'Diamond Ring',  500000,    'luxury',    6),
  ('crown',     'Crown',         1000000,   'luxury',    7),
  ('car',       'Supercar',      2000000,   'luxury',    8),
  ('falcon',    'Golden Falcon', 5000000,   'luxury',    9),
  ('yacht',     'Yacht',         10000000,  'luxury',    10),
  ('jet',       'Private Jet',   20000000,  'luxury',    11),
  ('palace',    'Palace',        50000000,  'exclusive', 12),
  ('dragon',    'Jade Dragon',   100000000, 'exclusive', 13),
  ('phoenix',   'Phoenix',       200000000, 'exclusive', 14),
  ('snowflake', 'Snowflake',     30000,     'event',     15),
  ('moon',      'Crescent Moon', 300000,    'event',     16),
  ('firework',  'Firework',      1500000,   'event',     17)
on conflict (id) do nothing;

insert into public.room_cover_templates(id, name, price, sort) values
  ('lantern', 'Lantern', 0, 1), ('dunes', 'Dunes', 0, 2), ('lotus', 'Lotus', 0, 3), ('neon', 'Neon City', 0, 4),
  ('mic', 'Golden Mic', 0, 5), ('stars', 'Starry Night', 0, 6), ('waves', 'Waves', 0, 7), ('garden', 'Garden', 0, 8)
on conflict (id) do nothing;

insert into public.room_themes(id, name, price, sort) values
  ('majlis', 'Majlis', 0, 1), ('midnight', 'Midnight', 0, 2), ('garden', 'Garden', 0, 3), ('ocean', 'Ocean', 0, 4),
  ('palace', 'Royal Palace', 5000000, 5), ('galaxy', 'Galaxy', 8000000, 6), ('sakura', 'Sakura', 8000000, 7), ('gold', 'Gold Lounge', 15000000, 8)
on conflict (id) do nothing;

insert into public.banners(title, subtitle, cta_label, action, color_from, color_to, sort) values
  ('First top-up: double coins', 'Your first recharge gets 100% bonus', 'Top up', 'topup:first', '#d8b77a', '#5a3d12', 1),
  ('Weekly Gift King', 'Top gifters win a golden frame', 'See ranking', 'leaderboard', '#c9506c', '#3d0c1c', 2),
  ('Invite friends', 'Earn 200K coins for every friend', 'Invite', 'invite', '#2a9d7f', '#0b3328', 3);
