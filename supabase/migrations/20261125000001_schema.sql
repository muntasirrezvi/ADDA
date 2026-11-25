-- Adda: core schema
-- Run with: supabase db push

create extension if not exists pgcrypto with schema extensions;

do $$ begin
  create type public.user_role as enum ('user','host','agent','moderator','admin');
exception when duplicate_object then null; end $$;

-- ---------- people ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  public_id bigint generated always as identity (start with 10000) unique,
  username text not null check (char_length(username) between 3 and 20),
  avatar_url text,
  avatar_preset int not null default 0 check (avatar_preset between 0 and 99),
  cover_url text,
  cover_preset int not null default 0,
  bio text not null default '' check (char_length(bio) <= 120),
  country text,
  role public.user_role not null default 'user',
  lifetime_usd numeric(12,2) not null default 0,
  wealth_xp bigint not null default 0,
  wealth_level int not null default 1,
  charm_xp bigint not null default 0,
  vip_tier text,
  vip_until timestamptz,
  verified boolean not null default false,
  banned_until timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

-- email and phone are private: only the owner and admins can read them
create table public.profile_private (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  email text,
  phone text,
  phone_verified boolean not null default false
);

-- ---------- money ----------
create table public.wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  coins bigint not null default 0 check (coins >= 0),
  diamonds bigint not null default 0 check (diamonds >= 0),
  updated_at timestamptz not null default now()
);

create table public.transactions (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null,
  coins bigint not null default 0,
  diamonds bigint not null default 0,
  ref text,
  meta jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index transactions_user_idx on public.transactions(user_id, created_at desc);
create index transactions_kind_idx on public.transactions(kind, created_at desc);

create table public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

create table public.coin_packs (
  id text primary key,
  usd numeric(10,2) not null,
  bdt numeric(12,2) not null,
  coins bigint not null check (coins > 0),
  discount_pct int not null default 0 check (discount_pct between 0 and 20),
  play_product_id text unique,
  active boolean not null default true,
  sort int not null default 0
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  provider text not null check (provider in ('sslcommerz','google_play','apple','agent','admin')),
  pack_id text references public.coin_packs(id),
  amount numeric(12,2) not null,
  currency text not null,
  coins bigint not null,
  status text not null default 'pending' check (status in ('pending','paid','failed','cancelled','refunded')),
  provider_ref text,
  raw jsonb,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  unique (provider, provider_ref)
);
create index payments_user_idx on public.payments(user_id, created_at desc);
create index payments_status_idx on public.payments(status, created_at desc);

-- ---------- gifts ----------
create table public.gifts (
  id text primary key,
  name text not null,
  price bigint not null check (price > 0),
  tier text not null check (tier in ('classic','luxury','exclusive','event')),
  icon_url text,
  animation_url text,
  active boolean not null default true,
  sort int not null default 0,
  starts_at timestamptz,
  ends_at timestamptz
);

-- ---------- rooms ----------
create table public.rooms (
  id bigint generated always as identity (start with 200) primary key,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 30),
  topic text not null default 'Talk',
  language text not null default 'English',
  region text not null default 'Global',
  announcement text not null default '' check (char_length(announcement) <= 120),
  cover_url text,                          -- uploaded image shown on the homepage card
  cover_template text not null default 'lantern', -- built-in illustrated cover when no image
  theme text not null default 'majlis',
  seats int not null default 8 check (seats in (8,12,16)),
  locked boolean not null default false,
  password_hash text,
  featured boolean not null default false, -- admin: pin to the top of the homepage
  home_order int not null default 0,       -- admin: lower shows first among featured
  status text not null default 'open' check (status in ('open','closed','suspended')),
  listeners int not null default 0,
  score_today bigint not null default 0,
  created_at timestamptz not null default now()
);
create index rooms_home_idx on public.rooms(status, featured desc, home_order, listeners desc);
create index rooms_owner_idx on public.rooms(owner_id);

create table public.room_seats (
  room_id bigint not null references public.rooms(id) on delete cascade,
  seat int not null check (seat between 0 and 16),
  user_id uuid references public.profiles(id) on delete set null,
  locked boolean not null default false,
  muted boolean not null default false,
  primary key (room_id, seat)
);
create unique index room_seats_one_per_user on public.room_seats(room_id, user_id) where user_id is not null;

create table public.room_members (
  room_id bigint not null references public.rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('member','admin','banned')),
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

create table public.room_messages (
  id bigint generated always as identity primary key,
  room_id bigint not null references public.rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'text' check (kind in ('text','voice','system')),
  body text check (char_length(body) <= 200),
  media_url text,
  created_at timestamptz not null default now()
);
create index room_messages_idx on public.room_messages(room_id, id desc);

create table public.gift_events (
  id bigint generated always as identity primary key,
  room_id bigint references public.rooms(id) on delete set null,
  sender_id uuid references public.profiles(id) on delete set null,
  receiver_id uuid references public.profiles(id) on delete set null,
  gift_id text references public.gifts(id),
  qty int not null,
  total bigint not null,
  created_at timestamptz not null default now()
);
create index gift_events_room_idx on public.gift_events(room_id, id desc);

create table public.room_follows (
  user_id uuid not null references public.profiles(id) on delete cascade,
  room_id bigint not null references public.rooms(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, room_id)
);

create table public.room_events (
  id bigint generated always as identity primary key,
  room_id bigint not null references public.rooms(id) on delete cascade,
  title text not null check (char_length(title) between 2 and 40),
  starts_at timestamptz not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table public.event_rsvps (
  event_id bigint not null references public.room_events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (event_id, user_id)
);

-- ---------- social ----------
create table public.user_follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followee_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);
create table public.reports (
  id bigint generated always as identity primary key,
  reporter_id uuid references public.profiles(id) on delete set null,
  target_user uuid references public.profiles(id) on delete cascade,
  target_room bigint references public.rooms(id) on delete set null,
  target_reel uuid,
  reason text not null,
  details text,
  status text not null default 'new' check (status in ('new','actioned','dismissed')),
  action text,
  handled_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  handled_at timestamptz
);

create table public.direct_messages (
  id bigint generated always as identity primary key,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'text' check (kind in ('text','voice','call','gift')),
  body text check (char_length(body) <= 1000),
  media_url text,
  meta jsonb not null default '{}',
  created_at timestamptz not null default now(),
  read_at timestamptz,
  check (sender_id <> receiver_id)
);
create index dm_pair_idx on public.direct_messages (least(sender_id, receiver_id), greatest(sender_id, receiver_id), id desc);

create table public.calls (
  id uuid primary key default gen_random_uuid(),
  caller_id uuid not null references public.profiles(id) on delete cascade,
  callee_id uuid not null references public.profiles(id) on delete cascade,
  type text not null check (type in ('audio','video')),
  channel text not null unique default ('call_' || replace(gen_random_uuid()::text, '-', '')),
  status text not null default 'ringing' check (status in ('ringing','active','ended','missed','declined')),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  ended_at timestamptz
);

-- ---------- reels ----------
create table public.music_tracks (
  id text primary key,
  title text not null,
  artist text not null,
  audio_url text not null,
  cover_url text,
  duration_s int,
  bpm int,
  uses bigint not null default 0,
  active boolean not null default true,
  sort int not null default 0
);

create table public.reels (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  video_url text not null,
  cover_url text,
  caption text not null default '' check (char_length(caption) <= 150),
  track_id text references public.music_tracks(id) on delete set null,
  filter text,
  effect text,
  text_overlay text check (char_length(text_overlay) <= 40),
  allow_donations boolean not null default true,
  views bigint not null default 0,
  likes int not null default 0,
  comments int not null default 0,
  coins_earned bigint not null default 0,
  status text not null default 'active' check (status in ('active','hidden','removed')),
  created_at timestamptz not null default now()
);
create index reels_feed_idx on public.reels(status, created_at desc);

create table public.reel_likes (
  reel_id uuid not null references public.reels(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (reel_id, user_id)
);
create table public.reel_comments (
  id bigint generated always as identity primary key,
  reel_id uuid not null references public.reels(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 200),
  created_at timestamptz not null default now()
);

-- ---------- notifications ----------
create table public.notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text,
  data jsonb not null default '{}',
  read boolean not null default false,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications(user_id, id desc);

create table public.devices (
  token text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text,
  updated_at timestamptz not null default now()
);

-- ---------- homepage (managed in the admin panel) ----------
create table public.banners (
  id bigint generated always as identity primary key,
  title text not null,
  subtitle text,
  image_url text,
  cta_label text,
  action text,              -- e.g. 'room:201', 'events', 'invite', 'topup:first'
  color_from text default '#d6506e',
  color_to text default '#4a0c1e',
  sort int not null default 0,
  active boolean not null default true,
  starts_at timestamptz,
  ends_at timestamptz
);

-- ---------- hosts, agencies, agents ----------
create table public.agencies (
  id bigint generated always as identity primary key,
  name text not null unique,
  owner_id uuid references public.profiles(id) on delete set null,
  commission_pct int not null default 10 check (commission_pct between 0 and 50),
  created_at timestamptz not null default now()
);
create table public.hosts (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  agency_id bigint references public.agencies(id) on delete set null,
  joined_at timestamptz not null default now()
);
create table public.verifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  id_doc_path text not null,
  selfie_path text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  note text,
  reviewed_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create table public.payouts (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id),
  diamonds bigint not null check (diamonds > 0),
  amount_usd numeric(10,2) not null,
  method text not null,
  account text not null,
  status text not null default 'pending' check (status in ('pending','approved','paid','rejected')),
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  processed_by uuid references public.profiles(id)
);
create table public.agent_stock (
  agent_id uuid primary key references public.profiles(id) on delete cascade,
  coins bigint not null default 0 check (coins >= 0)
);
create table public.agent_sales (
  id bigint generated always as identity primary key,
  agent_id uuid not null references public.profiles(id),
  buyer_id uuid not null references public.profiles(id),
  coins bigint not null check (coins > 0),
  method text,
  amount_local numeric(12,2),
  created_at timestamptz not null default now()
);

create table public.daily_checkins (
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null default current_date,
  reward bigint not null,
  primary key (user_id, day)
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null,
  target text,
  meta jsonb not null default '{}',
  created_at timestamptz not null default now()
);
