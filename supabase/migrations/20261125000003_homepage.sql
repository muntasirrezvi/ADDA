-- Adda: homepage control, cover templates and room themes (managed in the admin panel)

-- Cover templates a creator can pick when creating a room. The admin panel can add,
-- replace the image of, reorder, hide or charge for any template.
create table public.room_cover_templates (
  id text primary key,
  name text not null,
  image_url text,                 -- uploaded image; null = the app's built-in illustration
  price bigint not null default 0 check (price >= 0),
  active boolean not null default true,
  sort int not null default 0
);

-- Room background themes (free and premium)
create table public.room_themes (
  id text primary key,
  name text not null,
  image_url text,
  price bigint not null default 0 check (price >= 0),
  active boolean not null default true,
  sort int not null default 0
);
create table public.user_themes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  theme_id text not null references public.room_themes(id) on delete cascade,
  bought_at timestamptz not null default now(),
  primary key (user_id, theme_id)
);

create or replace function public.buy_theme(p_theme text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); t room_themes; w wallets;
begin
  if me is null or not active_user(me) then raise exception 'account restricted'; end if;
  select * into t from room_themes where id = p_theme and active;
  if not found then raise exception 'theme not found'; end if;
  if exists (select 1 from user_themes where user_id = me and theme_id = p_theme) then return jsonb_build_object('ok', true, 'already', true); end if;
  select * into w from wallets where user_id = me for update;
  if w.coins < t.price then raise exception 'insufficient coins'; end if;
  if t.price > 0 then perform _wallet_add(me, -t.price, 0, 'theme', p_theme); end if;
  insert into user_themes(user_id, theme_id) values (me, p_theme);
  return jsonb_build_object('ok', true, 'coins', w.coins - t.price);
end $$;

-- a room may only use a theme / template its owner can use
create or replace function public.check_room_style() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if is_admin() then return new; end if;
  if new.theme is distinct from coalesce(old.theme, '') and exists (select 1 from room_themes where id = new.theme and price > 0)
     and not exists (select 1 from user_themes where user_id = new.owner_id and theme_id = new.theme) then
    raise exception 'buy this theme first';
  end if;
  if new.cover_template is distinct from coalesce(old.cover_template, '') and exists (select 1 from room_cover_templates where id = new.cover_template and (price > 0 or not active)) then
    raise exception 'this cover template is not available';
  end if;
  if new.cover_url is distinct from old.cover_url and new.cover_url is not null
     and new.cover_url !~ ('/storage/v1/object/public/room-covers/(' || new.owner_id::text || '|admin)/') then
    raise exception 'upload the cover to your own folder first';
  end if;
  return new;
end $$;
create trigger rooms_style before insert or update on public.rooms for each row execute function public.check_room_style();

-- What the app's homepage shows: featured (pinned by admin, in admin order) first, then live rooms by activity.
create or replace function public.home_rooms(p_tab text default 'hot', p_region text default null, p_limit int default 40, p_offset int default 0)
returns table (id bigint, name text, topic text, language text, region text, cover_url text, cover_template text, cover_image text,
               theme text, seats int, locked boolean, featured boolean, listeners int, score_today bigint,
               owner_id uuid, owner_name text, owner_avatar text, owner_preset int, owner_public_id bigint, on_mic int)
language sql stable security definer set search_path = public as $$
  select r.id, r.name, r.topic, r.language, r.region, r.cover_url, r.cover_template,
         coalesce(r.cover_url, t.image_url) as cover_image,
         r.theme, r.seats, r.locked, r.featured, r.listeners, r.score_today,
         p.id, p.username, p.avatar_url, p.avatar_preset, p.public_id,
         (select count(*)::int from room_seats s where s.room_id = r.id and s.user_id is not null)
    from rooms r
    join profiles p on p.id = r.owner_id
    left join room_cover_templates t on t.id = r.cover_template
   where r.status = 'open'
     and (p_region is null or r.region = p_region)
     and (p_tab <> 'following' or exists (select 1 from room_follows f where f.room_id = r.id and f.user_id = auth.uid()))
     and (p_tab <> 'new' or r.created_at > now() - interval '7 days')
     and not exists (select 1 from blocks b where b.blocker_id = auth.uid() and b.blocked_id = r.owner_id)
   order by case when p_tab = 'new' then 0 else (case when r.featured then 0 else 1 end) end,
            case when r.featured and p_tab <> 'new' then r.home_order else 0 end,
            case when p_tab = 'new' then extract(epoch from r.created_at) else r.listeners + r.score_today / 100000.0 end desc
   limit least(p_limit, 100) offset p_offset
$$;

-- Everything the homepage needs above the room list, in one call
create or replace function public.home_feed()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'layout', coalesce(setting('home_layout'), '["banners","stories","events","rooms"]'),
    'banners', coalesce((select jsonb_agg(to_jsonb(b) order by b.sort) from banners b
                          where b.active and (b.starts_at is null or b.starts_at <= now()) and (b.ends_at is null or b.ends_at > now())), '[]'),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'room_id', e.room_id, 'room', r.name,
                          'going', (select count(*) from event_rsvps v where v.event_id = e.id),
                          'me', exists (select 1 from event_rsvps v where v.event_id = e.id and v.user_id = auth.uid())) order by e.starts_at)
                        from room_events e join rooms r on r.id = e.room_id
                        where e.starts_at > now() - interval '1 hour' and r.status = 'open' limit 10), '[]'),
    'templates', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort) from room_cover_templates t where t.active), '[]'),
    'themes', coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('owned', t.price = 0 or exists (select 1 from user_themes u where u.user_id = auth.uid() and u.theme_id = t.id)) order by t.sort)
                        from room_themes t where t.active), '[]')
  )
$$;

-- admin: create/update/delete templates and themes, reorder the featured list
create or replace function public.admin_reorder_featured(p_rooms bigint[])
returns void language plpgsql security definer set search_path = public as $$
declare i int;
begin
  if not is_admin() then raise exception 'admins only'; end if;
  update rooms set featured = false, home_order = 0 where featured and not (id = any(p_rooms));
  for i in 1 .. coalesce(array_length(p_rooms, 1), 0) loop
    update rooms set featured = true, home_order = i where id = p_rooms[i];
  end loop;
  perform _audit('reorder_featured', null, jsonb_build_object('rooms', p_rooms));
end $$;

revoke execute on function public.buy_theme(text), public.home_rooms(text,text,int,int), public.home_feed(), public.admin_reorder_featured(bigint[]), public.check_room_style() from public, anon;
grant execute on function public.buy_theme(text), public.home_rooms(text,text,int,int), public.home_feed(), public.admin_reorder_featured(bigint[]) to authenticated, service_role;
