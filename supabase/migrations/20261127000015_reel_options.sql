-- Adda: Instagram-style reel options — edit caption, pin to profile, hide like count,
-- turn commenting off, save reels, "not interested", report.

alter table public.reels add column if not exists comments_off boolean not null default false;
alter table public.reels add column if not exists hide_likes boolean not null default false;
alter table public.reels add column if not exists pinned boolean not null default false;
alter table public.reels add column if not exists edited_at timestamptz;
grant update (caption, allow_donations, status, comments_off, hide_likes, pinned, edited_at) on public.reels to authenticated;

-- nobody can comment when the owner turned comments off
create or replace function public._reel_comment_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from reels where id = new.reel_id and comments_off and user_id <> new.user_id) then
    raise exception 'comments are turned off for this reel';
  end if;
  return new;
end $$;
create or replace trigger reel_comments_guard before insert on public.reel_comments
  for each row execute function public._reel_comment_guard();

-- at most 3 pinned reels per person, like Instagram
create or replace function public._reel_pin_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.pinned and not old.pinned and (select count(*) from reels where user_id = new.user_id and pinned and id <> new.id) >= 3 then
    raise exception 'you can pin up to 3 reels — unpin one first';
  end if;
  return new;
end $$;
create or replace trigger reels_pin_guard before update of pinned on public.reels
  for each row execute function public._reel_pin_guard();

create table if not exists public.reel_saves (
  user_id uuid not null references public.profiles(id) on delete cascade,
  reel_id uuid not null references public.reels(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, reel_id)
);
alter table public.reel_saves enable row level security;
revoke all on public.reel_saves from anon, authenticated;
grant select, insert, delete on public.reel_saves to authenticated;
grant all on public.reel_saves to service_role;
create policy reel_saves_own on public.reel_saves for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create table if not exists public.reel_hidden (
  user_id uuid not null references public.profiles(id) on delete cascade,
  reel_id uuid not null references public.reels(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, reel_id)
);
alter table public.reel_hidden enable row level security;
revoke all on public.reel_hidden from anon, authenticated;
grant select, insert, delete on public.reel_hidden to authenticated;
grant all on public.reel_hidden to service_role;
create policy reel_hidden_own on public.reel_hidden for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
