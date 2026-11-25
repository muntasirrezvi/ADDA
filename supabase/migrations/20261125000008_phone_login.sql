-- Adda: one account per phone number, stored without spaces or dashes, so phone + password sign-in is unambiguous
create or replace function public.normalize_phone() returns trigger language plpgsql as $$
begin
  new.phone := nullif(regexp_replace(coalesce(new.phone, ''), '[\s\-()]', '', 'g'), '');
  return new;
end $$;
create trigger profile_private_phone before insert or update of phone on public.profile_private
  for each row execute function public.normalize_phone();
create unique index profile_private_phone_key on public.profile_private(phone) where phone is not null;

-- app sign-ups (which always send a username) must include a phone number;
-- users you add by hand in the Supabase dashboard are not affected
create or replace function public.require_phone() returns trigger language plpgsql as $$
begin
  if coalesce(nullif(new.phone, ''), new.raw_user_meta_data->>'phone', '') = '' and coalesce(new.raw_user_meta_data, '{}') ? 'username' then
    raise exception 'A phone number is required to sign up';
  end if;
  return new;
end $$;
drop trigger if exists require_phone on auth.users;
create trigger require_phone before insert on auth.users for each row execute function public.require_phone();
